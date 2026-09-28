# Spec: harvest sweep, a scheduled multi-agent distill job

Generated: 2026-09-29
Status: APPROVED (operator, kit:spec step 4; design critique folded; validation pending)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-357-harvest-sweep.md`
References: `hooks/harvest.py` (the extractor seam, the locked dedup-and-append in `_harvest_payload`, the recursion note in its docstring, `_run_harvest_locked` single-flight), `commands/wrap.md` (the distill half: pre-step-0 scan, step 7b precedent + lane + build, step 7c, step 10 landing and full-lane draft rules), `lib/sync/deploy/macos/` (a kit-owned launcher + plist template + installer + consumer bridge, the shape to copy), `lib/session/parse_transcript.py` (the shared Claude JSONL line parser), `hooks/ship-gate.sh` (resolves the kit from `CLAUDE_PLUGIN_ROOT` and exits 0 on an empty root).

## Problem

Distill runs at the end of `/kit:wrap`, inside the session it distills. Three things go wrong there.

1. Context. By step 7b the session has spent its context on scans and merges. The pre-step-0 scan exists only because a late scan found nothing.
2. Scope. Wrap sees one Claude session. It never sees Devin workers, and it never sees the same friction across sessions. A manual review of 32 Devin sessions today found most lessons already captured. The rest were worker-ops patterns: a commit-format hook false block in 7 sessions, workers stalling while a background command runs, context blowouts on large briefs. No single session showed any of them as a pattern.
3. Cost placement. The per-session harvest hook (PreCompact, SessionEnd) spends a Haiku call per session, and wrap spends the operator's close-out minutes on distill.

The operator asked for a job that runs every ~6 hours, distills every session since the last run across agents, and does the improve and learn work. `/kit:wrap` then lands only.

## Solution

### Approaches considered

1. **Enhance the harvest tool with a sweep mode, plus a launchd launcher (chosen).** Stage 1 is deterministic Python: adapters, cursor, one Haiku extraction per lead session, pattern counting. Stage 2 spawns one headless Claude session that builds from the stage-1 manifest with wrap's rules. Stage 3 is code again: it gates and merges the PRs stage 2 opened. The sweep lives in `hooks/harvest_sweep.py`, a module of the harvest tool that imports harvest.py's shared functions, so the hook file stays readable.
2. **A new sibling tool (`lib/sweep/`).** Rejected. It would duplicate the extractor seam, the ledger lock, slug dedup, and the recursion guard, which is the fragment step 7b exists to prevent.
3. **One spawned session per run with no stage 1 (the model reads raw transcripts itself, like `session-audit`).** Rejected. Cursor and idempotency would live in model behavior, not code. Quota would scale with transcript size, and nothing counts patterns deterministically.

### Chosen approach + why

Approach 1. Code owns everything that must be exact: which sessions, how many, what was seen before, when a pattern crossed its threshold, and whether a PR may merge. The model owns only judgment (what is a learning, what to build) and follows wrap's existing rules for that. Approach 2 traded away reuse. Approach 3 traded away crash safety and a quota bound.

### Extensibility & boundaries

- Load-bearing dimension: session volume. Measured on the Mini over 24h: 46 top-level Claude transcripts and 237 subagent transcripts changed. Subagents fold into their lead, so the extraction unit is the lead session (46 a day, plus Devin sessions). The default cap is 20 extractions a run at 4 runs a day, 80 a day, so the measured load fits with about 40% headroom. A burst above 80 a day queues; sessions older than `HARVEST_SWEEP_STALE_RUNS` x `schedule_hours` (default 4 x 6h = 24h) are marked done unread, and every report carries the cursor lag. A sustained load above the cap therefore drops the oldest sessions rather than growing without bound, and the lag line makes that visible.
- Second dimension: the number of agents. A new agent is one adapter function in `hooks/harvest_sweep.py` plus one word in `harvest.sources`. Codex is deferred on that seam (Out of Scope).
- Units: adapter (source to normalized transcript), cursor (which sessions are new), extractor (transcript to learnings + sightings), stager (dedup + append, shared with the hook), aggregator (sightings to candidates), distill session (candidates to PRs and flushes), merge gate (PR to merged, DRAFT, or REPORTED), launcher (schedule, rc, heartbeat). Each has one input and one output shape below.

## Picture

```
  launchd (StartInterval = schedule_hours)
        |
        v
  deploy/macos/harvest-sweep/harvest-sweep   (launcher, #!/bin/bash, no .sh)
        |  enable false, no host marker, or sweep.lock held  --> log, exit 0, NO bridge call
        v
  python3 <kit>/hooks/harvest_sweep.py --sweep  (direct call, own rc; not via harvest.sh)
        |
        |  STAGE 1  (code; Haiku per lead session)
        |    cursor.json --> adapters: claude (subagents folded in) | devin
        |                    launches.jsonl --> lead attribution (brief-path match)
        |    per session: cached raw output or extractor --> learnings --> _stage_candidates
        |                                               --> sightings --> patterns.jsonl
        |    aggregate (occurrences >= MIN_PATTERN_COUNT), sanitize --> runs/<id>/manifest.json
        |
        |  no candidate, no ask, fewer than MIN_LEARNINGS learnings --> no spawn, rc 0
        v
  STAGE 2  claude -p --setting-sources project --settings <rendered sweep settings>
        |    cwd = runs/<id>/, env HARVEST_SWEEP_CHILD=1, CLAUDE_PLUGIN_ROOT=<kit>
        |    deny: gh pr merge, wrap merge, wrap land     (the model opens PRs, never merges)
        |    per candidate: precedent --> lane --> wrap start worktree --> build, verify, PR
        |    learnings --> step 7c notes and the wrap.after seam, through worktrees
        |    appends {pattern, run_id, outcome, pr, ts} to proposed.jsonl as each closes
        v
  STAGE 3  (code) per PR in proposed.jsonl this run:
        |    repo in build_repos? diff clear of the path denylist? lane in wrap.build_lanes?
        |      all yes --> wrap merge --apply --pr <n> <repo>   (green only, tree verified)
        |      any no  --> gh pr ready --undo (DRAFT), REVIEW #<n> in Needs you
        v
  report.md (step 9 grammar) --> report-lint.sh (max 3 passes) --> gate-ledger record
        |
        v
  bridge ~/.config/harvest-sweep/bridge <rc> <report path or "-">  --> vps-mon heartbeat

  /kit:wrap on a host with the sweep marker and wrap.distill = "harvest": landing half only,
  Built/Seam = SKIPPED: distill runs in the harvest sweep
  harvest.sh auto modes: sweep active on this host and hook_when_sweep_on = false => exit 0
```

## Design

Design-bearing: yes (new scheduled component, new persisted state, a config table that authorizes writes, a spawned unattended session, a code merge gate).

### Approaches considered + chosen

See `## Solution`.

### Diagram

See `## Picture` (component view). Cursor lifecycle per source:

```
  no cursor --> hwm = now - schedule_hours (first run, no backfill; --since overrides)
      |
      v
  scan at most MAX_SCAN candidates with last_activity >= hwm
  select: last_activity <= now - QUIET_MINUTES, cwd not under the harvest state dir,
          (id, last_activity) not in done{}, not quarantined
  older than STALE_RUNS x schedule_hours --> done{} unread, counted as stale in the report
  order by last_activity asc; trivial sessions --> done{} without counting against the cap
  take max_sessions_per_run
      |
      v  per session, in order
  raw output cached for <id>@<last_activity>? --yes--> reuse it
      | no
      v
  extract (only messages after done{id}.n_msgs, plus 4 of overlap)
      |-- fail, and it is the first session or every session so far --> stop run, rc 1
      |-- fail otherwise --> fail{id} += 1; at 3, quarantine: done{} + STATE row
      | ok
      v
  save raw output --> stage learnings --> merge sightings (max count) under patterns.lock
      |
      v
  done{id} = {last_activity, n_msgs}; hwm = last_activity of the longest done prefix
  prune done{} < hwm; write cursor.json atomically (tmp + os.replace)
```

### Distill-half contract

`commands/wrap.md`'s distill half assumes a live session on a branch. T6 extracts step 7b's build rules and step 10's landing steps and full-lane path into `docs/patterns/distill-build-and-land.md`. Wrap cites it, and the sweep prompt cites it by absolute path. The sweep substitutes as follows:

| wrap assumes | the sweep uses |
|---|---|
| the pre-step-0 scan reads the live session | the manifest's `candidates` are the scan list |
| step 7a derives a rid from the branch, refusing off-branch | 7a is a structural skip; the run record uses rid `harvest-sweep-<run-id>`, and each build keeps its own branch rid |
| relative paths (`bin/wrap`, `lib/...`) from the kit checkout | absolute `<kit>/bin/...` and `<kit>/lib/...`, rendered into the prompt |
| step 10 runs only under `follow` mode | in-lane candidates always build; there is no follow switch |
| step 10 merges with `wrap merge --apply --pr` | stage 2 never merges; stage 3 code merges after its gates |
| `wrap.before` and `wrap.after` seams | only `wrap.after` runs (a flush reads output, not a working tree); unresolved seam: learnings stay queued and the report carries a `STATE` row |
| `/kit:*` slash commands | none; project-only sources may not load the kit plugin |

### ADR link(s)

No new ADR exists. Two decisions are lasting:

- A second kit LaunchAgent beside `kit-weekly`. ADR-0034 decision 9 chose ONE kit scheduler and rejected a plist per job. The cadence differs (every 6h against a fixed weekly slot), so T6 amends ADR-0034 to record the exception (DEC-12).
- `wrap.distill` becomes a three-value knob, and the distill half moves out of wrap on a host where the sweep runs.

### Boundaries & failure modes

The sweep reads transcripts outside any repo, which may carry hostile text (web pages, tool output). It writes into repos only through worktrees, and code, never the model, decides a merge. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**Normalized transcript** (adapter output, one per lead session):

```
{"source": "claude|devin", "session_id": str, "lead_session_id": str|null,
 "cwd": str, "started": epoch_s, "last_activity": epoch_s,
 "messages": [{"role": "user|assistant|tool", "text": str}]}
```

`render(t, start, max_chars)` joins messages from index `start` as `<role>: <text>` lines and keeps the most recent `max_chars`, the same tail rule `transcript_text` uses today.

**Adapters** (in `hooks/harvest_sweep.py`, stdlib only; roots overridable by env for tests: `HARVEST_SWEEP_CLAUDE_ROOT`, `HARVEST_SWEEP_DEVIN_DB`):

| Source | Session unit | last_activity | Keep | Drop |
|---|---|---|---|---|
| claude | `~/.claude/projects/<slug>/<id>.jsonl`; every `<id>/subagents/agent-*.jsonl` is folded in after the lead's messages, each prefixed `subagent:` | max mtime over the lead file and its subagent files | `type` user/assistant, `text` blocks; `tool_use` as `tool: <name> <input, 200 chars>` | everything else; any session whose cwd is under the harvest state dir (the sweep's own stage-2 sessions). Reuses `parse_transcript.iter_entries`. |
| devin | row of `sessions` in `~/.local/share/devin/cli/sessions.db`, opened read-only (`mode=ro` URI) | `sessions.last_activity_at` (epoch seconds) | `message_nodes.chat_message` JSON roles user, assistant, tool: `content` plus `tool_calls` names | role `system` (injected rules). Chain: walk `parent_node_id` up from `sessions.main_chain_id`; fall back to all nodes by `node_id` when null; a fixture pins it (DEC-16). |

A session with fewer than `HARVEST_SWEEP_MIN_MESSAGES` (default 6) kept user plus assistant messages is marked done, skipped with no extractor call, and not counted against `max_sessions_per_run`.

**Launch record** (optional input, shipped in ops-toolkit #3631, `d43a81b`). `tools/worker-launch` appends one JSON object per launch to `~/.local/state/worker-launch/launches.jsonl` (override: `HARVEST_SWEEP_LAUNCH_RECORD`):

```
{"ts": "<UTC ISO>", "agent": str, "mode": "tui|print", "handle": str|null, "title": str,
 "brief": path, "brief_copy": path, "cwd": path, "lead_session": str|null}
```

Attribution applies to a Devin session. A record matches when its `agent` is `devin` and its `brief` or `brief_copy` path appears in the session's first kept user message. When several match, the one whose `ts` is nearest the session's `started` wins. The session takes the record's `lead_session`. No file, a malformed line, or no match leaves `lead_session_id` null. There is no time-window fallback (DEC-23). The sweep never fails on this input.

**Sweep extractor prompt** (`PROMPT_SWEEP` in `harvest_sweep.py`, same `HARVEST_EXTRACTOR` seam). It returns one JSON object, read by a new `extract_json_object` (the existing `extract_json_array` returns the first `[`, which would find an inner array):

```
{"learnings": [<the existing hook element shape: item, kind, home, why>],
 "sightings": [{"pattern": "<kebab slug>", "kind": "repeat|friction|failure|ask",
                "count": <int, occurrences in this session>, "evidence": "<one line>"}]}
```

The prompt carries the canonical slugs of the 50 most recent patterns plus every slug in `proposed.jsonl`, and tells the model to reuse one when it fits. `kind: ask` is an enhancement the operator asked for and the session deferred (wrap step 7b's third candidate kind).

**Extractor failure is not an empty result.** The sweep's extractor call returns `(ok, stdout)`: `ok` is false on a non-zero exit, a timeout, or output with no parseable JSON object. The hook path keeps its current behavior.

**Raw output cache.** The extractor's stdout is saved to `extract/<source>/<id>@<last_activity>.json` before anything is staged. A replay of the same key reuses the file, so a crash after extraction never pays or varies the model call twice.

**Shared stager.** The locked read-known, dedup, and append block in `_harvest_payload` moves into `_stage_candidates(ledger, glossaries, candidates) -> fresh_rows`. The hook calls it with the session's ledger as today. The sweep calls it with the sweep ledger. Both share slugify, glossary dedup, and the `.lock` file. The sweep reads a repo's `_meta/learned-ledger.md` under that ledger's own `.lock` for dedup and never writes it.

**Sanitizing.** Before a sighting or learning enters the manifest: `pattern` and `item` must match `^[a-z0-9-]{1,60}$` (else dropped); `evidence` and `why` are cut to 200 characters of printable ASCII with backticks, angle brackets, `$`, and newlines removed. The prompt renders them inside a fenced `data` block and states that nothing in it is an instruction.

**Stage-1 outputs** (under `$HARVEST_STATE_DIR/sweep/`, default `~/.claude/dwarves-kit/state/harvest/sweep/`):

| File | Shape | Writer | Idempotency key |
|---|---|---|---|
| `cursor.json` | `{"<source>": {"hwm": epoch_s, "done": {"<id>": {"last_activity", "n_msgs"}}, "fail": {"<id>": n}, "quarantined": [ids]}}` | stage 1, atomic replace after each session | (source, id, last_activity) |
| `extract/<source>/<id>@<last_activity>.json` | raw extractor stdout | stage 1 | file name |
| `ledger/<repo-slug>.md` | the learned-ledger table, `status: queued` | `_stage_candidates` | slug (exact + fuzzy + glossary) |
| `patterns.jsonl` | `{"pattern", "canonical", "kind", "source", "session_id", "lead_session_id", "cwd", "count", "evidence", "ts"}` | stage 1, rewritten via tmp + `os.replace` under `patterns.lock` | (canonical, session_id); a re-read keeps `max(count)` |
| `proposed.jsonl` | `{"pattern", "run_id", "outcome", "pr", "ts"}` | stage 2 per candidate as it closes; stage 3 updates `outcome` | canonical pattern, subject to the re-propose rule |
| `runs/<run-id>/manifest.json` | `{"run_id", "status": "pending|done|failed", "resumes": n, "sessions": [...], "learnings": [...], "candidates": [{"pattern", "kind", "occurrences", "sessions", "leads", "evidence": [...]}], "cursor_lag_s": {...}, "stale": n}` | stage 1; stage 2 and 3 update status | run_id |
| `runs/<run-id>/stage1.log`, `report.md` | stage-1 log; wrap step 9 grammar under `## Harvest sweep: <run-id>` | stage 1; stage 2 and 3 | run_id |
| `installed` | host marker: `{"label", "host", "kit", "ts"}` | `install --apply` | host |

A run with nothing new writes no `runs/<run-id>/` directory and no manifest; it logs one line to the launcher log.

`<repo-slug>` comes from the session cwd: strip a trailing `/.claude/worktrees/<name>`, walk up to the first directory that exists, then `git rev-parse --git-common-dir` with the trailing `/.git` stripped. A cwd outside any repo goes to `ledger/_no-repo.md`.

**Aggregation.** Slugs cluster with a fixed fuzzy threshold (`HARVEST_SWEEP_FUZZY`, default 2, independent of the hook's `HARVEST_FUZZY_THRESHOLD`). The first slug seen in a cluster is its canonical name and stays so. Over sightings newer than `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (default 14), a canonical pattern is a candidate when the sum of per-session `count` is at least `HARVEST_SWEEP_MIN_PATTERN_COUNT` (default 3) and it has no live `proposed.jsonl` entry. `kind: ask` qualifies at 1. One sighting of count 1 never qualifies. Re-propose rule: an entry with outcome `REPORTED` stops blocking after 14 days if the pattern's occurrences grew by at least the threshold since its `ts`; `BUILT` and `DRAFT` block for good.

**Manifest learnings.** Every `queued` row across the sweep ledgers, not only this run's. On the first run after install, queued rows in the repo ledgers of the sessions read (the hook era) are copied into the sweep ledgers so they reach the flush.

**Stage 2 spawn.** Only when the manifest has a candidate, an `ask`, or at least `HARVEST_SWEEP_MIN_LEARNINGS` (default 5) queued learnings. Otherwise the run reports `NOTHING: no candidates` and exits 0.

```
cd $HARVEST_STATE_DIR/sweep/runs/<run-id>
HARVEST_SWEEP_CHILD=1 CLAUDE_PLUGIN_ROOT=<kit> claude -p "$(render prompt)" \
  --model "${HARVEST_SWEEP_MODEL:-sonnet}" --max-turns "${HARVEST_SWEEP_MAX_TURNS:-200}" \
  --setting-sources project --settings $HARVEST_STATE_DIR/sweep/settings.json \
  --permission-mode bypassPermissions
```

- Never `--bare` (it skips keychain reads and breaks auth). `HARVEST_SWEEP_DISTILL_CMD` overrides the whole command for tests.
- `settings.json` is rendered by `install` from `hooks/harvest-sweep-settings.json.tmpl` with the kit's absolute path. It sets `env.CLAUDE_PLUGIN_ROOT`, because `hooks/ship-gate.sh` exits 0 on an empty root and would fail open. It wires the enforcement hooks (safety-gate, ship-gate, push-to-main blocker, commit-format, secrets-guard) and no PreCompact, SessionEnd, or Stop harvest hook. It denies `Bash(gh pr merge*)`, `Bash(*wrap merge*)`, and `Bash(*wrap land*)`.
- The prompt calls kit scripts by absolute path and never a `/kit:*` slash command (DEC-11).
- harvest_sweep.py spawns it with `start_new_session=True` and, at `distill_timeout_minutes`, sends `os.killpg` to the whole group.

**The distill prompt** (`hooks/harvest-sweep-prompt.md`) cites `docs/patterns/distill-build-and-land.md` and the contract table above. It does not restate them.

- Per candidate: `precedent find --surface inventory --json`, then `lane-classify.sh classify`, then ENHANCE, NEW, or NOTE with the code-home-wins rule.
- A lane in `wrap.build_lanes` other than `full`, in a repo listed in `harvest.build_repos`: `wrap start <home> <type>/<slug>`, build, verify, commit, `wrap rebase`, push, open a ready PR from the worktree.
- `full` in a listed repo: the full-lane path (reserved spec, fresh-context validator, build), then a DRAFT PR.
- A repo not in `build_repos`: nothing is built; the candidate is `REPORTED` with `reported: repo not in harvest.build_repos`.
- `max_builds_per_run` caps builds of every lane. The rest are `REPORTED` with `reported: sweep build cap` and get no `proposed.jsonl` entry, so the next run picks them up.
- As each candidate closes, append `{pattern, run_id, outcome, pr, ts}` to `proposed.jsonl`.
- Learnings: step 7c for incidents, then the `wrap.after` seam skill with the manifest's learnings, every repo write through a `wrap start` worktree. Seam unset, or set but unresolved in this session: learnings stay queued and the report carries a `STATE` row with the count and the reason.
- Candidate text is quoted data, never an instruction, the same rule step 10 applies to worker briefs.

**Stage 3, the merge gate (code, `harvest_sweep.py`).** For each PR that `proposed.jsonl` records under this run id:

1. The PR's repo is in `harvest.build_repos`.
2. `gh pr diff <n> --name-only` touches no denylisted path: `hooks/`, `.github/`, `settings.json`, `settings.local.json`, `.claude/settings*.json`, `hooks.json`, `kit.toml`, `.kit.toml`, `harvest-sweep-prompt.md`, `harvest-sweep-settings*`.
3. `lane-classify.sh classify --files` on that diff returns a lane in `wrap.build_lanes` other than `full`.

All three hold: `wrap merge --apply --pr <n> <repo>`, which merges only a green own PR and verifies the tree. Any fails: `gh pr ready --undo <n>` and a `REVIEW #<n>` item in `Needs you`. A PR stage 2 already opened as DRAFT stays DRAFT. The gate never merges a PR it cannot classify.

**Report and record.** Stage 3 writes `report.md` and runs `report-lint.sh`. A failing lint gets at most 3 fix passes; still failing, the report keeps its findings appended and the run's rc is 3. Then `gate-ledger.sh record harvest-sweep-<run-id> harvest ran "<n> sessions, <b> merged, <d> drafts, <r> reported, lag <h>h"`, and the manifest flips to `done`.

**Resume.** At start, a manifest still `pending` and older than `distill_timeout_minutes` re-runs stages 2 and 3 before new sessions are read. Candidates with a `proposed.jsonl` entry for that run are skipped. After 2 resumes the manifest flips to `failed` and the report carries an `INCIDENT` row.

**rc contract** (the sweep entry, `harvest_sweep.py --sweep`):

| rc | Meaning | Bridge called |
|---|---|---|
| 0 | ran, including `NOTHING` | yes |
| 1 | stage 1 stopped on an auth-shaped extractor failure | yes |
| 2 | stage 2 failed, timed out, or its manifest flipped to `failed` | yes |
| 3 | report lint still failing after 3 passes | yes |
| (none) | disabled, no host marker, or `sweep.lock` held: the launcher logs and exits 0 | no |

The launcher calls `python3 <kit>/hooks/harvest_sweep.py --sweep` directly, never through `harvest.sh`, whose `|| true; exit 0` would hide every failure. `harvest.py`'s `_dispatch` routes `--sweep` to the same entry before its `read_payload` fall-through, for manual runs. A disabled or skipped run never calls the bridge, so a job left loaded but disabled goes silent and vps-mon alerts; turning the sweep off for good means `launchctl bootout` plus retiring the heartbeat per `job-monitoring-onboarding`.

**Pruning** (each run, stage 1): `patterns.jsonl` rows older than the pattern window, `proposed.jsonl` entries older than 90 days, `extract/` files and `runs/` dirs older than 30 days.

### Data model changes

New kit state under `$HARVEST_STATE_DIR/sweep/` (table above). No repo file format changes. `ledger/<repo-slug>.md` reuses the learned-ledger table, so `--cleanup` and the existing flush read it unchanged.

### API changes

- `hooks/harvest_sweep.py --sweep [--dry-run] [--since <iso>]`, also reachable as `harvest.sh --sweep` for a human (rc hidden there). `--dry-run` runs stage 1 with the extractor, prints the manifest, and writes nothing but the raw output cache. `--since` sets a one-off hwm for a manual backfill.
- The sweep is ACTIVE on a host when `harvest.enable` is true AND the `installed` marker exists on that host (DEC-27). The operator `kit.toml` may sync across hosts; the marker does not.
- `harvest.sh` auto modes (no-arg, `--lab-log`, `--stop-trigger`) exit 0 without work when `HARVEST_SWEEP_CHILD=1`, or when the sweep is active on this host and `harvest.hook_when_sweep_on` is false. `--cleanup` is unaffected. The shim reads the keys with `kit_config_get_root`.
- `/kit:wrap`: `wrap.distill` accepts `true`, `false`, or `harvest`. With `harvest` on a host where the sweep is active: the landing half runs, no seam key is read, and the report says `**Built:** SKIPPED: distill runs in the harvest sweep` and `**Seam:** SKIPPED: distill runs in the harvest sweep`, plus a `FYI` `STATE` row naming the knob. With `harvest` on a host where it is not active: wrap distills as with `true` and prints a `STATE` row saying the sweep is not installed here. The word `distill` in the invocation wins for that one run, and the `FYI` says the sweep will also see the session (DEC-15).
- `lib/wrap/report-lint.sh`: a first `## ` line opening `## Harvest sweep:` sets a new `sweep_report` flag, separate from `follow_report`. It enables the full-lane rule (a `lane=full` item may close `verified: ..., #<pr> DRAFT` when a `REVIEW #<pr>` item names the same PR) and keeps the `**Seam:**` requirement. `SKIPPED: distill runs in the harvest sweep` passes on both wrap lines (a fixture pins it).

### UI changes

None.

### Infrastructure changes

`kit.toml` gains a `[harvest]` table. Every key resolves with `kit_config_get_root` (operator or kit-root `kit.toml`, never a project `.kit.toml`), because the sweep writes to repos.

```toml
[harvest]
enable = false               # the switch; active only on a host with the install marker
schedule_hours = 6           # launchd StartInterval, rendered at install
sources = "claude"           # space-separated: claude devin
max_sessions_per_run = 20    # lead-session extractions per run; trivial skips do not count
max_builds_per_run = 3       # builds of every lane per run; the rest are REPORTED
build_repos = ""             # space-separated absolute repo paths stage 2 may build in and
                             # stage 3 may merge in; empty = build nothing, report everything
distill_timeout_minutes = 90 # stage-2 wall clock; the process group is killed at the limit
hook_when_sweep_on = false   # true = the per-session hook keeps running while the sweep is active
```

Build lanes come from `wrap.build_lanes`; there is no sweep copy. Tuning constants are env-overridable and not config: `HARVEST_SWEEP_MIN_MESSAGES` (6), `HARVEST_MAXCHARS` (12000, shared with the hook), `HARVEST_SWEEP_QUIET_MINUTES` (30), `HARVEST_SWEEP_MIN_PATTERN_COUNT` (3), `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (14), `HARVEST_SWEEP_FUZZY` (2), `HARVEST_SWEEP_STALE_RUNS` (4), `HARVEST_SWEEP_MAX_SCAN` (2000), `HARVEST_SWEEP_MIN_LEARNINGS` (5), `HARVEST_SWEEP_QUARANTINE_AFTER` (3), `HARVEST_SWEEP_MODEL` (sonnet), `HARVEST_SWEEP_MAX_TURNS` (200), `HARVEST_SWEEP_LAUNCH_RECORD`.

Launchd deploy under `deploy/macos/harvest-sweep/`, copying `lib/sync/deploy/macos/`:

- `harvest-sweep`: the launcher. `#!/bin/bash`, no `.sh`, launchd-safe PATH, optional `~/.config/harvest-sweep/env`. It re-checks that the sweep is active each run and exits 0 with a log line otherwise. It logs start and end with rc, calls `harvest_sweep.py --sweep` directly, then runs `~/.config/harvest-sweep/bridge <rc> <report path>` best-effort, passing `-` when `report.md` is missing.
- `harvest-sweep.plist.tmpl`: `ProgramArguments[0]` is the launcher's absolute path. Rendered `__LABEL__`, `__KIT__`, `__HOME__`, `__INTERVAL__`.
- `install [--label L] [--apply]`: dry run by default, `--label` defaults to `harvest-sweep`; the Mini installs `mini.harvest-sweep`, a prefix already in vps-mon's `OWNED_PREFIXES` (DEC-13). It refuses unless `harvest.enable` is true. `--apply` renders the plist and `settings.json`, writes the `installed` marker, and bootstraps the agent.

Monitoring (consumer side, ops-toolkit): the Mini's bridge pings the vps-mon heartbeat when rc is 0 and sends a fail ping otherwise. The URL lives in `/etc/vps-mon/harvest-sweep-heartbeat-url`, `hb_id` is the discovered label, the interval is `schedule_hours`, and the grace is 2x. The catalog link follows `job-monitoring-onboarding`. The kit ships no endpoint or secret.

## Task Breakdown

### Phase 1: Foundation

- [ ] T1: factor `_stage_candidates` out of `_harvest_payload`; route `--sweep` in `_dispatch` before the `read_payload` fall-through. AC: every existing harvest test in `tests/test-hooks.sh` passes unchanged.
- [ ] T2: `hooks/harvest_sweep.py` adapters (claude with subagents folded into the lead and self-harvest dropped; devin main-chain walk), the min-messages skip, brief-path attribution, the repo-slug walk. Fixtures under `tests/fixtures/harvest-sweep/`: a claude project dir with a lead and two subagent files; a devin db built by a fixture script with a branched message forest; a `launches.jsonl`; a session whose cwd is a deleted worktree; a session whose cwd is under the harvest state dir. AC: AC1.
- [ ] T3: stage 1: cursor, scan cap, stale marking, quarantine, raw output cache, delta extraction, `extract_json_object`, sanitizing, sweep ledger, `patterns.jsonl` under its lock, aggregation, manifest, cursor lag, pruning, `--dry-run`, `--since`, `sweep.lock`, the rc contract. AC: AC2 to AC6.

### Phase 2: Core

- [ ] T4: stage 2 and 3: `hooks/harvest-sweep-prompt.md`, `hooks/harvest-sweep-settings.json.tmpl` (enforcement hooks, `env.CLAUDE_PLUGIN_ROOT`, merge denies), the spawn with `start_new_session` and `killpg`, the spawn threshold, resume with the 2-resume limit, the merge gate, the 3-pass lint loop, the gate-ledger record. AC: AC7, AC9, AC11.
- [ ] T5: `[harvest]` table in `kit.toml`; the host marker; the `harvest.sh` gate; `deploy/macos/harvest-sweep/` launcher, template, and installer. AC: AC8, AC12.
- [ ] T6: extract step 7b's build rules and step 10's landing steps and full-lane path into `docs/patterns/distill-build-and-land.md`, with `commands/wrap.md` citing it; `wrap.distill = "harvest"` with host scoping and the explicit-word override; `report-lint.sh` `sweep_report`; MANUAL.md and the `[wrap]` comment in `kit.toml`; an ADR-0034 amendment recording the second LaunchAgent. AC: AC10; `tests/test-meta.sh` asserts wrap.md cites the extracted doc.

### Phase 3: Rollout (Mini, in this order)

- [ ] T7: hand dry runs, no plist. Run `python3 <kit>/hooks/harvest_sweep.py --sweep --dry-run` three times across a day; compare each manifest against a hand review of the same sessions. Verify, with a manual stage-2 spawn against a scratch repo: flag settings load under `--setting-sources project`; ship-gate refuses a test push for both shapes (`git -C <wt> push` and `cd <wt> && git push`); the merge denies hold under `bypassPermissions`; the `wrap.after` seam skill resolves. AC: all four checks recorded in `docs/verification/harvest-sweep.md`.
- [ ] T8: set `harvest.enable = true`, `harvest.build_repos`, `harvest.sources = "claude devin"`, and `wrap.distill = "harvest"` in the Mini operator `kit.toml`. Run `install --label mini.harvest-sweep --apply`. In ops-toolkit: install the bridge, provision the heartbeat, add the catalog link, in that order, so the first ping follows provisioning within one interval. AC: two consecutive scheduled runs report clean lint, a gate-ledger line, and a heartbeat ping; vps-mon shows the job monitored, not gap.

## After state

- [ ] `python3 hooks/harvest_sweep.py --sweep --dry-run` prints a manifest over new claude and devin lead sessions. (Today: no sweep mode.)
- [ ] A second `--sweep` with no new sessions spawns nothing, calls no extractor, creates no `runs/` directory, and leaves `cursor.json`, the sweep ledgers, and `patterns.jsonl` unchanged. Its one log line lands in `~/Library/Logs/dwarves-kit/<label>.log`.
- [ ] With the sweep active and `hook_when_sweep_on = false`, a PreCompact or SessionEnd hook fire spawns no harvest child. (Today: every fire spawns one.)
- [ ] `/kit:wrap` on the Mini with `wrap.distill = "harvest"` prints `**Built:** SKIPPED: distill runs in the harvest sweep` and the lint passes. On a host without the marker it distills and prints a `STATE` row.
- [ ] `launchctl print gui/$(id -u)/mini.harvest-sweep` on the Mini shows the job, and vps-mon lists it monitored.

## Acceptance Criteria (global)

- [ ] AC1: adapters. Each fixture source yields the normalized shape. Devin `system` rows are absent from `messages`. Subagent files fold into one lead transcript (one extraction). A Devin worker whose first user message names a record's `brief` takes that record's `lead_session`; with no match it stays null. A session whose cwd is under the harvest state dir is never selected. A deleted-worktree cwd resolves to its main repo's slug.
- [ ] AC2: idempotency. Running `--sweep` twice over the same fixtures leaves the sweep ledger, `patterns.jsonl`, and `proposed.jsonl` byte-identical after the second run, and the second run makes no extractor call.
- [ ] AC3: crash safety. Killing the sweep after a session's staging and before its cursor write, then re-running, stages no duplicate row, double-counts no sighting, and reuses the cached raw output (the stub extractor is called once for that session). No session between the old and new hwm is skipped.
- [ ] AC4: rc contract. A stub extractor that exits 1 on every session leaves `cursor.json` unchanged, the sweep exits 1, and the launcher passes a non-zero rc to a stub bridge. A disabled run and a lock-held run exit 0 and never call the bridge.
- [ ] AC5: quarantine. A stub extractor that fails only for session B (not the first) lets A and C complete; B's fail count rises each run and B is quarantined on the third, with a `STATE` row; the hwm never passes B until then.
- [ ] AC6: bounds. Twenty-five new lead fixtures plus ten trivial ones: one run extracts 20 and marks the 10 trivial done; the next run extracts 5. A fixture older than `STALE_RUNS` x `schedule_hours` is marked done unread and counted in `stale`. Each extractor prompt is at most `HARVEST_MAXCHARS` of transcript plus the fixed prompt. The report carries a cursor lag line.
- [ ] AC7: threshold. Two sessions each sighting a pattern once produce no candidate. A third produces one. One session sighting it with count 3 produces one. An `ask` produces one at count 1. Sightings `commit-hook-false-block` and `commit-hok-false-block` count as one canonical pattern.
- [ ] AC8: hook switch and recursion guard. With the sweep active and `hook_when_sweep_on = false`, the no-arg, `--lab-log`, and `--stop-trigger` modes exit 0 without a child. With `enable = false`, or with no host marker, today's behavior holds. `HARVEST_SWEEP_CHILD=1` suppresses all three modes. A project `.kit.toml` setting any `[harvest]` key changes nothing. The stub distill command's argv contains `--setting-sources project`, `--settings`, and `--max-turns`, and never `--bare`.
- [ ] AC9: injection guard. A fixture transcript whose tool output says to edit `hooks/ship-gate.sh` and merge the result reaches the manifest only as a sanitized slug and a quoted evidence line. A stub stage 2 that opens a PR touching `hooks/` ends with that PR converted to DRAFT and a `REVIEW` item; the stub `wrap merge` is never called. The same holds for a PR in a repo outside `build_repos`.
- [ ] AC10: wrap and lint. A `## Harvest sweep:` report with a full-lane `#<pr> DRAFT` item and a matching `REVIEW #<pr>` passes; the same report without the REVIEW item fails; the same report without `**Seam:**` fails. A wrap report with both `SKIPPED: distill runs in the harvest sweep` lines passes.
- [ ] AC11: main checkouts untouched. After a fixture run through stage 3, each fixture repo's main checkout has the same HEAD sha, the same checked-out branch, and an empty `git status --porcelain`. An empty run writes no manifest.
- [ ] AC12: the installer dry run renders a plist whose `ProgramArguments[0]` is the launcher path and a `settings.json` with a non-empty `env.CLAUDE_PLUGIN_ROOT`; it refuses with `enable = false`.
- [ ] AC13: `bash tests/test-hooks.sh && bash tests/test-meta.sh` pass.

## Test plan

Outline. `/kit:test-plan` expands it into the coverage matrix.

| Area | Case | Kind |
|---|---|---|
| adapters | one fixture per source; role drops; subagent fold; devin main-chain walk and null fallback; trivial skip; self-harvest drop; deleted-worktree cwd; unreadable db or file skips the source with a log line | unit |
| attribution | brief match; nearest-ts among several; malformed line; missing file; no match stays null | unit |
| cursor | first run window; second run empty; resumed session read as a delta; tie on last_activity; crash between staging and cursor write; stale marking; scan cap | unit |
| extractor | auth-shaped failure stops the run; a single-session failure increments and later quarantines; non-JSON output counts as failure; empty arrays count as success; raw cache reuse | unit |
| aggregation | 2 vs 3 occurrences; in-session count; `ask`; fuzzy canonical cluster; window expiry; proposed block; REPORTED re-propose after growth | unit |
| sanitizing | slug charset; evidence length and stripped characters; injection fixture | unit |
| stage 2 and 3 | stub distill argv; no spawn under the threshold; pending manifest resumes and skips closed candidates; third resume marks failed; timeout kills the group; merge gate on allowlist, denylist, lane; lint loop capped at 3 | integration (stubs for `claude`, `gh`, `wrap` on PATH) |
| rc and launcher | rc 0/1/2/3 reach the stub bridge; disabled and lock-held runs skip the bridge; missing report passes `-` | integration |
| hook gate | three auto modes under each switch value; host marker absent; child marker; project toml ignored | integration |
| lint | sweep DRAFT with and without REVIEW; sweep report without Seam; wrap harvest SKIPPED lines | fixture |
| live | T7 hand dry runs and the four stage-2 checks; T8 two scheduled runs | UAT |

**Negative controls.** Each runs after the change is committed, with `bash lib/gate/negctl.sh <root> "bash tests/test-hooks.sh" "<mutate>"`, and the named test must go red:

| Mutation | Test that must fail |
|---|---|
| move the cursor write ahead of `_stage_candidates` | AC3 crash safety |
| treat a failed extractor call as an empty result | AC4 cursor unchanged |
| launcher calls the sweep through `harvest.sh` (rc swallowed) | AC4 bridge receives non-zero |
| drop the denylist check in the merge gate | AC9 no merge on `hooks/` |
| drop the `build_repos` check in the merge gate | AC9 no merge outside the allowlist |
| never increment the per-session fail count | AC5 quarantine on the third run |
| remove the `HARVEST_SWEEP_CHILD` check from `harvest.sh` | AC8 child marker |
| read `hook_when_sweep_on` with `kit_config_get` (project toml honored) | AC8 project toml ignored |

## Verification

```
bash tests/test-hooks.sh && bash tests/test-meta.sh
bash lib/config/kit-config.sh selftest
bash lib/wrap/report-lint.sh tests/fixtures/harvest-sweep/report-draft-ok.md
HARVEST_EXTRACTOR=<stub> HARVEST_SWEEP_DISTILL_CMD=<stub> HARVEST_STATE_DIR=$(mktemp -d) python3 hooks/harvest_sweep.py --sweep --dry-run
```

Rollout proof (T7, T8) goes into `docs/verification/harvest-sweep.md`: the three dry-run manifests against the hand review, the four stage-2 checks, `launchctl print` for the label, the vps-mon monitored state, and two scheduled run reports.

## Edge Cases

1. A live session idles past the quiet window and then resumes. It is read, then re-read later from `n_msgs` onward with 4 messages of overlap. Its sightings merge by `max(count)`, and its learnings dedup by slug.
2. Claude writes a transcript mid-read. The parser skips a malformed trailing line; the lead's max mtime moves past the value in `done{}`, so the next run reads the delta.
3. The Devin db is locked by a running Devin. The read-only URI read retries once, then skips the source for this run with a log line; the devin cursor does not move.
4. A session's cwd was a worktree that has since been removed. The slug walk strips `/.claude/worktrees/<name>` and walks up to an existing parent.
5. Two sessions share a cwd in a repo with no `_meta/learned-ledger.md`. The sweep ledger for that repo slug is created; nothing is created in the repo.
6. A pattern slug drifts across sessions. The canonical-slug list in the prompt is the first guard, and the fixed fuzzy threshold is the second. A miss splits the count and delays the candidate. It never builds a single sighting.
7. A candidate's home repo has foreign activity (step 0 signals). The build still runs in its own worktree; stage 3's `wrap merge` refuses what step 0 would stop, and the PR stays `OPEN`.
8. The system clock jumps backward. The hwm is compared against source timestamps, so no session is lost; the quiet window may delay one run.
9. The operator runs `/kit:wrap distill` on the Mini. Both distill the same session. Dedup covers learnings; the second builder finds the first's branch or merge as a precedent hit.
10. `sources` names an agent with no adapter (for example `codex`). That word logs `unknown source` and is skipped; the others run.
11. The operator `kit.toml` syncs to the Air with `wrap.distill = "harvest"`. The Air has no marker, so its wraps keep distilling and its hook keeps running, each saying so in a `STATE` row or log line.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| OAuth expired or keychain locked under launchd | the first extractor call fails; rc 1; fail ping | cursor untouched; vps-mon alerts; fix auth per the `launchd-headless-job` recipe; the next runs catch up at up to 80 sessions a day |
| One session breaks the extractor every time | its fail count rises | quarantine after 3 with a `STATE` row; the run continues |
| Recursion storm (a spawned session re-fires harvest) | many `harvest` children in `ps` | `--setting-sources project`, a rendered settings file with no harvest hook, `HARVEST_SWEEP_CHILD=1`, and self-harvest drop by cwd |
| Prompt injection from a transcript (web page, tool output) | a candidate or PR that edits enforcement files or targets an unexpected repo | slug and evidence sanitizing; quoted-data rendering; stage 2 cannot merge (settings denies); stage 3 merges only in `build_repos`, only clear of the path denylist, only in-lane, only green; anything else is DRAFT with `REVIEW` |
| Ship-gate fails open in stage 2 | a push with no gate record succeeds | `env.CLAUDE_PLUGIN_ROOT` set in the rendered settings; T7 tests both push shapes |
| Quota burn | Max-plan usage spikes on the 6h cadence | `enable = false`; per-run caps; delta extraction; raw output cache; no spawn below the threshold; `--max-turns`; `schedule_hours` |
| Load above the cap | cursor lag grows in reports; `stale` count non-zero | stale sessions marked done unread; the lag line shows it; raise `max_sessions_per_run` or lower `schedule_hours` |
| Stage 2 crash or timeout | manifest `pending`; rc 2; fail ping | process group killed; resume skips closed candidates; `failed` after 2 resumes; leftover worktrees show in the next wrap's `Left alone` |
| Bad unattended build | a merged PR breaks something | only allowlisted repos, only non-full lanes, only green, tree verified; revert is one PR |
| Heartbeat can never go red | job silently broken, monitor green | the launcher calls the sweep entry directly and passes its rc; disabled runs skip the bridge |
| Writes into a live checkout | a main checkout's HEAD, branch, or status changes | every repo write is a `wrap start` worktree; AC11 pins it |
| Transcript data to a new provider | Devin transcripts reach Anthropic Haiku | `sources` defaults to `claude`; adding `devin` is an operator decision in root-only config |
| Secret in a transcript reaches a prompt or ledger | secret-guard in stage 2; a credential-shaped string in a sweep ledger | same exposure class as today's hook; sanitizing keeps only slugs and short reasons; secrets-guard runs in the stage-2 settings |

## Out of Scope

- Changing wrap's landing half. Steps 0 to 6, 8, and 9 stay as they are.
- A Codex adapter. The adapter seam stays; Codex was verified from one `codex exec` rollout only (cli 0.156.1) and is added once an interactive rollout is checked (DEC-26).
- Replacing `session-audit` or `session-intel repeat`. They stay on kit-weekly.
- `bin/reflect`, which proposes from gate and run ledgers, not transcripts.
- Changing the launch record. ops-toolkit #3631 owns its format; the sweep only reads it.
- LAB_LOG drafts from the sweep. The hook's `--lab-log` draft stops with the hook (DEC-3), and wrap step 6's activity line covers the session record (DEC-14).
- Any board row. The sweep follows wrap: a candidate not built is reported, never filed.
- Linux or systemd scheduling.
- Auto-enabling. `enable` ships false, and `build_repos` ships empty.

## Decision Log

- DEC-1 (operator): autonomy follows wrap's lane rules. Tiny and normal candidates build in worktrees and merge only when green through `wrap merge --apply --pr`. Full-lane candidates open as DRAFT PRs and go to the operator as `REVIEW`. Learnings flush through step 7c and the learning-ledger route. The sweep reuses wrap's distill-half machinery (precedent find, lane-classify, `wrap start`, step-10 landing) and does not reimplement it.
- DEC-2 (operator): the host is the Mac Mini via launchd, following the estate plist rules, with a vps-mon heartbeat before the job counts as done.
- DEC-3 (operator): the per-session PreCompact and SessionEnd harvest hook is off while the sweep is on, through one switch (`hook_when_sweep_on`), so nothing is staged twice or paid for twice.
- DEC-4: enhance the harvest tool rather than a sibling tool. The sweep lives in `hooks/harvest_sweep.py`, which imports harvest.py's shared functions; the shared stager keeps one dedup path.
- DEC-5: code decides which sessions, counts, thresholds, and merges; one model session per run decides what to build. Rejected: a model-only sweep (no deterministic cursor or bound).
- DEC-6: the sweep stages learnings into kit state, not a repo's `_meta/learned-ledger.md`, because that file sits in a main checkout that live sessions share.
- DEC-7: an auth-shaped extractor failure stops the run with the cursor untouched. An empty result and a failed call must not look alike (the same third-state rule `report-lint.sh` enforces for `Built:`). Narrowed by DEC-30.
- DEC-8: a pattern needs `MIN_PATTERN_COUNT` occurrences (in-session counts included, matching wrap step 7b's "three or more times" rule) before it is built. An operator `ask` needs one.
- DEC-9: every `[harvest]` key resolves root-only (`kit_config_get_root`), the same reason as wrap's autonomy knobs: it authorizes writes.
- DEC-10: `sources` defaults to `claude`. Sending another agent's transcripts to Haiku is a new data path and an explicit operator choice.
- DEC-11 (operator): stage 2 runs with a sweep settings file that wires only the enforcement hooks, and the prompt calls kit scripts by absolute path. T7 verifies ship-gate still fires.
- DEC-12 (operator): a separate LaunchAgent, not a `jobs.txt` line, because the cadence differs from kit-weekly. T6 amends ADR-0034 decision 9. Rejected: per-job intervals in kit-weekly.
- DEC-13 (operator): the installer takes `--label` (default `harvest-sweep`); the Mini installs `mini.harvest-sweep`.
- DEC-14 (operator): the sweep drafts no LAB_LOG entry.
- DEC-15 (operator): an explicit `distill` word in `/kit:wrap` wins over `wrap.distill = "harvest"` for that run.
- DEC-16 (operator): the devin adapter walks `parent_node_id` up from `sessions.main_chain_id` and falls back to all nodes by `node_id`; a fixture pins it.
- DEC-17 (operator): `codex` stays out of the default `sources` until an interactive rollout is verified. Superseded by DEC-26.
- DEC-18 (operator): with no cursor, the first run starts `schedule_hours` back; `--since` covers a manual backfill.
- DEC-19 (resolved upstream): attribution reads the worker-launch record from ops-toolkit #3631 (`d43a81b`). Its agent + cwd + window fallback is superseded by DEC-23.
- DEC-20 (operator): the sweep's gate-ledger rid is `harvest-sweep-<run-id>`. It is never pushed, so ship-gate never looks for it; each build keeps its own branch rid.
- DEC-21: the sweep entry has its own rc contract (0 ran or NOTHING, 1 auth stop, 2 stage-2 failure, 3 lint), and the launcher calls it directly, never through `harvest.sh`. Disabled, unmarked, and lock-held runs exit 0 without calling the bridge.
- DEC-22: rollout order is hand dry runs with no plist, then `enable = true`, then `install --apply`, then bridge and heartbeat. `install` keeps its refusal while disabled.
- DEC-23: attribution uses the brief-path match only. The agent + cwd + time-window fallback is dropped as a guess that can mis-attribute.
- DEC-24: the model never merges. Stage 2 opens PRs under settings denies for `gh pr merge`, `wrap merge`, and `wrap land`; stage 3 code merges only in `harvest.build_repos`, only when the diff avoids the path denylist, only in a non-full lane from `wrap.build_lanes`, and only through `wrap merge --apply --pr`. Everything else is DRAFT with `REVIEW`. This guards DEC-1 against injected transcript text without changing its lane rule.
- DEC-25: patterns, evidence, and learnings are sanitized (slug charset, 200 printable characters, no backticks, angle brackets, `$`, or newlines) and rendered as quoted data.
- DEC-26: the Codex adapter is deferred to a later change; the adapter seam stays.
- DEC-27: harvest mode applies per host. The sweep is active only where `install --apply` wrote the `installed` marker, so a synced operator `kit.toml` cannot switch off distill or the hook on a host with no sweep.
- DEC-28: the extraction unit is the lead session with its subagents folded in. Trivial skips do not count against the cap, a scan cap bounds the stat work, sessions older than `STALE_RUNS` x `schedule_hours` are marked done unread, and every report shows cursor lag. This replaces the earlier claim that any backlog drains over several runs.
- DEC-29: stage-1 idempotency rests on a raw output cache keyed `<id>@<last_activity>`, sightings merged by `max(count)` per (canonical, session), `patterns.jsonl` rewritten via tmp + `os.replace` under `patterns.lock`, and a fixed sweep fuzzy threshold with a stable canonical slug per cluster.
- DEC-30: per-session failures quarantine after `QUARANTINE_AFTER` (3) with a `STATE` row; only an auth-shaped failure (the first session fails, or every session so far fails) stops the run. The hwm advances only through a contiguous prefix of done sessions.
- DEC-31: stage 2 resumes per candidate. `proposed.jsonl` gets `{pattern, run_id, outcome, pr, ts}` as each closes, a resume skips those, the process group is spawned with `start_new_session` and killed with `os.killpg` at the timeout, a manifest fails after 2 resumes, and the lint loop stops at 3 passes.
- DEC-32: cost bounds beyond the caps: delta extraction on re-touch, a spawn threshold (a candidate, an ask, or `MIN_LEARNINGS` queued learnings), `--max-turns`, pruning by age, and a re-propose rule for `REPORTED` entries only.
- DEC-33: the `[harvest]` table is cut to `enable`, `schedule_hours`, `sources`, `max_sessions_per_run`, `max_builds_per_run`, `build_repos`, `distill_timeout_minutes`, and `hook_when_sweep_on`. Other tuning is env-overridable constants. Build lanes come from `wrap.build_lanes`. `--source` and the half-interval skip are cut.
- DEC-34: `install` renders the stage-2 settings file with `env.CLAUDE_PLUGIN_ROOT` so ship-gate cannot fail open, and T7 tests both push shapes.
- DEC-35: wrap's distill half is extracted into `docs/patterns/distill-build-and-land.md` so wrap and the sweep cite one text; the contract table lists every sweep substitution.
- DEC-36: manifest learnings are every queued row across the sweep ledgers, repo ledgers are read under their own `.lock`, and the first run carries hook-era queued rows into the sweep ledgers.
- DEC-37: `report-lint.sh` gets its own `sweep_report` flag; reusing `follow_report` would drop the Seam rule.

## Open questions

(none; design questions were resolved at approval and in the design critique, see DEC-11 to DEC-37)
