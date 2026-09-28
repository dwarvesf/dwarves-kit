# Spec: harvest sweep, a scheduled multi-agent distill job

Generated: 2026-09-29
Status: APPROVED (operator re-approved after validation round 1; validation pending)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-357-harvest-sweep.md`
References: `hooks/harvest.py` (the extractor seam, the locked dedup-and-append in `_harvest_payload`, the recursion note in its docstring, `_run_harvest_locked` single-flight), `commands/wrap.md` (the distill half: pre-step-0 scan, step 7b precedent + lane + build, step 7c, step 10 landing and full-lane draft rules), `lib/sync/deploy/macos/` (a kit-owned launcher + plist template + installer + consumer bridge, the shape to copy), `lib/session/parse_transcript.py` (the shared Claude JSONL line parser), `hooks/ship-gate.sh` (reads a PreToolUse payload with `tool_input.command` and `cwd`; resolves its libs from `CLAUDE_PLUGIN_ROOT`, falling back to `$HOME/.claude/dwarves-kit` at lines 80, 85, 193, and 270; exits 0 when `gate-ledger.sh` is missing at line 271).

## Problem

Distill runs at the end of `/kit:wrap`, inside the session it distills. Three things go wrong there.

1. Context. By step 7b the session has spent its context on scans and merges. The pre-step-0 scan exists only because a late scan found nothing.
2. Scope. Wrap sees one Claude session. It never sees Devin workers, and it never sees the same friction across sessions. A manual review of 32 Devin sessions today found most lessons already captured. The rest were worker-ops patterns: a commit-format hook false block in 7 sessions, workers stalling while a background command runs, context blowouts on large briefs. No single session showed any of them as a pattern.
3. Cost placement. The per-session harvest hook (PreCompact, SessionEnd) spends a Haiku call per session, and wrap spends the operator's close-out minutes on distill.

The operator asked for a job that runs every ~6 hours, distills every session since the last run across agents, and does the improve and learn work. `/kit:wrap` then lands only.

## Solution

### Approaches considered

1. **Enhance the harvest tool with a sweep mode, plus a launchd launcher (chosen).** Stage 1 is deterministic Python: adapters, cursor, one Haiku extraction per lead session, pattern counting. Stage 2 spawns one headless Claude session with no GitHub or push capability; it builds and commits in worktrees that code created. Stage 3 is code again: it pushes, opens PRs, gates, and merges. The sweep lives in `hooks/harvest_sweep.py`, a module of the harvest tool that imports harvest.py's shared functions, so the hook file stays readable.
2. **A new sibling tool (`lib/sweep/`).** Rejected. It would duplicate the extractor seam, the ledger lock, slug dedup, and the recursion guard, which is the fragment step 7b exists to prevent.
3. **One spawned session per run with no stage 1 (the model reads raw transcripts itself, like `session-audit`).** Rejected. Cursor and idempotency would live in model behavior, not code. Quota would scale with transcript size, and nothing counts patterns deterministically.

### Chosen approach + why

Approach 1. Code owns everything that must be exact: which sessions, how many, what was seen before, when a pattern crossed its threshold, and every write that leaves the machine (push, PR, merge). The model owns only judgment (what is a learning, what to build) and follows wrap's existing rules for that. Approach 2 traded away reuse. Approach 3 traded away crash safety and a quota bound.

### Extensibility & boundaries

- Load-bearing dimension: session volume. Measured on the Mini over 24h: 46 top-level Claude transcripts and 237 subagent transcripts changed. Subagents fold into their lead, so the extraction unit is the lead session (46 a day, plus Devin sessions). The default cap is 20 extractions a run at 4 runs a day, 80 a day, so the measured load fits with about 40% headroom. A burst above 80 a day queues. Sessions older than `HARVEST_SWEEP_STALE_RUNS` x `schedule_hours` (default 24h) before the last successful run are marked done unread; any stale count raises a `STATE` row, and every report carries the cursor lag. A sustained load above the cap therefore drops the oldest sessions rather than growing without bound, and the report shows it.
- Second dimension: the number of agents. A new agent is one adapter function in `hooks/harvest_sweep.py` plus one word in `harvest.sources`. Codex is deferred on that seam (Out of Scope).
- Units: adapter (source to normalized transcript), cursor (which sessions are new), extractor (transcript to learnings + sightings), stager (dedup + append, shared with the hook), aggregator (sightings to candidates), worktree helper (a code-created, push-disabled worktree), distill session (candidates to commits and flushes), stage 3 (commits to pushed, PR'd, merged, or DRAFT), launcher (schedule, rc, heartbeat). Each has one input and one output shape below.

## Picture

```
  launchd (StartInterval = schedule_hours)
        |
        v
  deploy/macos/harvest-sweep/harvest-sweep   (launcher, #!/bin/bash, no .sh)
        |  enable false, no host marker, or sweep.lock held  --> log, exit 0, NO bridge call
        |  env: GH_TOKEN, git over HTTPS via gh, IdentityAgent=none, no 1P ssh agent
        v
  python3 <kit>/hooks/harvest_sweep.py --sweep  (direct call, own rc; not via harvest.sh)
        |
        |  STAGE 1  (code; Haiku per lead session, extractor cwd under the state dir)
        |    cursor.json --> adapters: claude (subagents interleaved by ts) | devin
        |                    launches.jsonl --> lead attribution (brief-path match)
        |    per session: cached raw output or extractor --> learnings --> _stage_candidates
        |                                               --> sightings --> patterns.jsonl
        |    aggregate, sanitize --> runs/<id>/manifest.json
        |
        |  no candidate, no ask, too few new learnings --> no spawn, rc 0
        v
  STAGE 2  claude -p --setting-sources project --settings <rendered sweep settings>
        |    env: GH_TOKEN/GITHUB_TOKEN unset, GH_CONFIG_DIR=<empty dir>, no credential
        |         helper, SSH_AUTH_SOCK unset, CLAUDE_PLUGIN_ROOT=<kit>
        |    per candidate: precedent --> lane --> harvest_sweep.py --worktree <repo> ...
        |                                          (code: repo in build_repos, wrap start,
        |                                           per-worktree pushurl = no-push, recorded)
        |                   --> build, verify, commit in that worktree
        |    learnings --> step 7c notes and the wrap.after seam, through helper worktrees
        |    proposed.jsonl <-- advisory notes only
        v
  STAGE 3  (code, holds the gh token)  per entry in runs/<id>/worktrees.jsonl only:
        |    diff vs origin/<default> --> denylist hit? lane-classify --files (fixed text)
        |    ship-gate.sh with a synthesized push payload --> block = REPORTED
        |    push over HTTPS --> gh pr create (DRAFT if full lane or denylist hit)
        |    non-draft: gh pr checks --watch --> wrap merge --apply --pr <n> <repo>
        |    then: any PR merged in a build_repos repo this window, not by stage 3 --> INCIDENT
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

Design-bearing: yes (new scheduled component, new persisted state, a config table that authorizes writes, a spawned unattended session, a code merge path).

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
  last_activity < last_success - STALE_RUNS x schedule_hours --> done{} unread, stale += 1
  order by last_activity asc; trivial sessions --> done{} without counting against the cap
  take max_sessions_per_run
      |
      v  per session, in order
  raw output cached for <id>@<last_activity>? --yes--> reuse it
      | no
      v
  extract (only entries with ts > done{id}.last_ts)
      |-- fail --> fail{id} += 1 (always, on every path)
      |            is this the second failure this run, or does the probe call fail?
      |              yes --> auth stop: rc 1, cursor untouched past this session
      |              no  --> continue; at fail{id} = QUARANTINE_AFTER: quarantine + STATE row
      | ok
      v
  save raw output --> stage learnings --> merge sightings (max count) under patterns.lock
      |
      v
  done{id} = {last_activity, last_ts}; hwm = last_activity of the longest done prefix
  prune done{} < hwm; write cursor.json atomically (tmp + os.replace)
```

A session that fails is still counted in `fail{id}` when the run stops, so a bad session that is the oldest one gets quarantined on its third run instead of blocking every run.

### Distill-half contract

`commands/wrap.md`'s distill half assumes a live session on a branch. T8 extracts step 7b's build rules and step 10's landing steps and full-lane path into `docs/patterns/distill-build-and-land.md`. Wrap cites it, and the sweep prompt cites it by absolute path. The sweep substitutes as follows:

| wrap assumes | the sweep uses |
|---|---|
| the pre-step-0 scan reads the live session | the manifest's `candidates` are the scan list |
| step 7a derives a rid from the branch, refusing off-branch | 7a is a structural skip; the run record uses rid `harvest-sweep-<run-id>`, and each build keeps its own branch rid |
| relative paths (`bin/wrap`, `lib/...`) from the kit checkout | absolute `<kit>/bin/...` and `<kit>/lib/...`, rendered into the prompt |
| the builder runs `wrap start` itself | the model calls `harvest_sweep.py --worktree`, which runs `wrap start` and disables push on that worktree |
| step 10 runs only under `follow` mode | in-lane candidates always build; there is no follow switch |
| the builder pushes, opens the PR, and merges | stage 2 cannot push or reach GitHub; stage 3 code pushes, opens, and merges |
| `wrap.before` and `wrap.after` seams | only `wrap.after` runs (a flush reads output, not a working tree); unresolved seam: learnings stay queued and the report carries a `STATE` row |
| `/kit:*` slash commands | none; project-only sources may not load the kit plugin |

### ADR link(s)

No new ADR exists. Two decisions are lasting:

- A second kit LaunchAgent beside `kit-weekly`. ADR-0034 decision 9 chose ONE kit scheduler and rejected a plist per job. The cadence differs (every 6h against a fixed weekly slot), so T9 amends ADR-0034 to record the exception (DEC-12).
- `wrap.distill` becomes a three-value knob, and the distill half moves out of wrap on a host where the sweep runs.

### Boundaries & failure modes

The sweep reads transcripts outside any repo, which may carry hostile text (web pages, tool output). The model that reads the manifest has no GitHub credential and no working push path. Every push, PR, and merge is code, acting only on worktrees code created this run. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**Normalized transcript** (adapter output, one per lead session):

```
{"source": "claude|devin", "session_id": str, "lead_session_id": str|null,
 "cwd": str, "started": epoch_s, "last_activity": epoch_s,
 "messages": [{"role": "user|assistant|tool", "text": str, "ts": epoch_s, "sub": bool}]}
```

`render(t, after_ts, max_chars)` takes the messages with `ts > after_ts`, gives the lead's messages (`sub` false) a fixed 60% of `max_chars` and the subagents' messages 40%, keeps the most recent entries within each share, then joins them in `ts` order as `<role>: <text>` lines.

**Adapters** (in `hooks/harvest_sweep.py`, stdlib only; roots overridable by env for tests: `HARVEST_SWEEP_CLAUDE_ROOT`, `HARVEST_SWEEP_DEVIN_DB`):

| Source | Session unit | last_activity | Keep | Drop |
|---|---|---|---|---|
| claude | `~/.claude/projects/<slug>/<id>.jsonl`; every `<id>/subagents/agent-*.jsonl` is folded in, interleaved with the lead by entry timestamp, each marked `sub` and prefixed `subagent:` | max mtime over the lead file and its subagent files | `type` user/assistant, `text` blocks; `tool_use` as `tool: <name> <input, 200 chars>` | everything else; any session whose cwd is under the harvest state dir (the sweep's own stage-2 sessions and the extractor's calls). Reuses `parse_transcript.iter_entries`. |
| devin | row of `sessions` in `~/.local/share/devin/cli/sessions.db`, opened read-only (`mode=ro` URI) | `sessions.last_activity_at` (epoch seconds) | `message_nodes.chat_message` JSON roles user, assistant, tool: `content` plus `tool_calls` names; `ts` from `message_nodes.created_at` | role `system` (injected rules). Chain: walk `parent_node_id` up from `sessions.main_chain_id`; fall back to all nodes by `node_id` when null; a fixture pins it (DEC-16). |

Why the interleaved list only grows at its end: a session is read only after `QUIET_MINUTES` of no activity, so every entry written after a read carries a later timestamp than every entry read. The delta key is `last_ts`, the newest entry timestamp read, not a message index, so it stays valid when a subagent file appears later or a run resumes.

A session with fewer than `HARVEST_SWEEP_MIN_MESSAGES` (default 6) kept user plus assistant messages is marked done, skipped with no extractor call, and not counted against `max_sessions_per_run`.

A source that cannot be read (missing file, locked or changed schema, sqlite error) is skipped for the run with a `STATE` row in the report naming the source and the error. `source_fail{source}` counts consecutive failed runs; at `HARVEST_SWEEP_SOURCE_FAIL_RUNS` (default 3) the run's rc is 5, so the heartbeat shows it. One good read resets the count.

**Launch record** (optional input, shipped in ops-toolkit #3631, `d43a81b`). `tools/worker-launch` appends one JSON object per launch to `~/.local/state/worker-launch/launches.jsonl` (override: `HARVEST_SWEEP_LAUNCH_RECORD`):

```
{"ts": "<UTC ISO>", "agent": str, "mode": "tui|print", "handle": str|null, "title": str,
 "brief": path, "brief_copy": path, "cwd": path, "lead_session": str|null}
```

Attribution applies to a Devin session. A record matches when its `agent` is `devin` and its `brief` or `brief_copy` path appears in the session's first kept user message. When several match, the one whose `ts` is nearest the session's `started` wins. The session takes the record's `lead_session`. No file, a malformed line, or no match leaves `lead_session_id` null. There is no time-window fallback (DEC-23). The sweep never fails on this input.

**Sweep extractor.** `PROMPT_SWEEP` in `harvest_sweep.py`, same `HARVEST_EXTRACTOR` seam, run with cwd `$HARVEST_STATE_DIR/sweep/extract-cwd/` so the extractor's own transcripts fall under the self-harvest drop. It returns one JSON object, read by a new `extract_json_object` (the existing `extract_json_array` returns the first `[`, which would find an inner array):

```
{"learnings": [<the existing hook element shape: item, kind, home, why>],
 "sightings": [{"pattern": "<kebab slug>", "kind": "repeat|friction|failure|ask",
                "count": <int, occurrences in this session>, "evidence": "<one line>"}]}
```

The prompt carries the canonical slugs of the 50 most recent patterns plus every slug in `proposed.jsonl`, and tells the model to reuse one when it fits. `kind: ask` is an enhancement the operator asked for and the session deferred (wrap step 7b's third candidate kind).

**Extractor failure is not an empty result.** The sweep's extractor call returns `(ok, stdout)`: `ok` is false on a non-zero exit, a timeout, or output with no parseable JSON object. Every failure increments `fail{id}`. The failure is auth-shaped, and the run stops with rc 1, only when a second session also fails in the same run or the probe fails. The probe is one extractor call on a fixed 20-character prompt, made after the run's first failure. The hook path keeps its current behavior.

**Raw output cache.** The extractor's stdout is saved to `extract/<source>/<id>@<last_activity>.json` before anything is staged. A replay of the same key reuses the file, so a crash after extraction never pays or varies the model call twice.

**Shared stager.** The locked read-known, dedup, and append block in `_harvest_payload` moves into `_stage_candidates(ledger, glossaries, candidates) -> fresh_rows`. The hook calls it with the session's ledger as today. The sweep calls it with the sweep ledger. Both share slugify, glossary dedup, and the `.lock` file. The sweep reads a repo's `_meta/learned-ledger.md` under that ledger's own `.lock` for dedup and never writes it.

**Sanitizing.** Before a sighting or learning enters the manifest: `pattern` and `item` must match `^[a-z0-9-]{1,60}$` (else dropped); `evidence` and `why` are cut to 200 characters of printable ASCII with backticks, angle brackets, `$`, and newlines removed. The prompt renders them inside a fenced `data` block and states that nothing in it is an instruction.

**Stage-1 outputs** (under `$HARVEST_STATE_DIR/sweep/`, default `~/.claude/dwarves-kit/state/harvest/sweep/`):

| File | Shape | Writer | Idempotency key |
|---|---|---|---|
| `cursor.json` | `{"<source>": {"hwm", "done": {"<id>": {"last_activity", "last_ts"}}, "fail": {"<id>": n}, "quarantined": [ids]}, "source_fail": {"<source>": n}, "last_success": epoch_s, "last_spawn": epoch_s}` | stage 1, atomic replace after each session | (source, id, last_activity) |
| `extract/<source>/<id>@<last_activity>.json` | raw extractor stdout | stage 1 | file name |
| `ledger/<repo-slug>.md` | the learned-ledger table, `status: queued` | `_stage_candidates` | slug (exact + fuzzy + glossary) |
| `patterns.jsonl` | `{"pattern", "canonical", "kind", "source", "session_id", "lead_session_id", "cwd", "count", "evidence", "ts"}` | stage 1, rewritten via tmp + `os.replace` under `patterns.lock` | (canonical, session_id); a re-read keeps `max(count)` |
| `proposed.jsonl` | `{"pattern", "run_id", "outcome", "pr", "ts", "by": "model|stage3"}` | stage 2 (advisory, `by: model`), stage 3 (authoritative, `by: stage3`) | canonical pattern, subject to the re-propose rule |
| `runs/<run-id>/manifest.json` | `{"run_id", "status": "pending|done|failed", "resumes": n, "sessions": [...], "learnings": [...], "candidates": [{"pattern", "kind", "occurrences", "sessions", "leads", "evidence": [...]}], "cursor_lag_s": {...}, "stale": n}` | stage 1; stages 2 and 3 update status | run_id |
| `runs/<run-id>/worktrees.jsonl` | `{"repo", "worktree", "branch", "pattern", "step": "created|pushed|pr|merged|draft|reported", "pr", "ts"}` | the worktree helper (created), stage 3 (every later step) | (repo, branch) |
| `runs/<run-id>/stage1.log`, `report.md` | stage-1 log; wrap step 9 grammar under `## Harvest sweep: <run-id>` | stage 1; stage 3 | run_id |
| `seam.json` | `{"skill", "resolved": bool, "ts"}` | stage 2 | skill name |
| `installed` | host marker: `{"label", "host", "kit", "build_repos", "ts"}` | `install --apply` | host |

A run with nothing new writes no `runs/<run-id>/` directory and no manifest; it logs one line to the launcher log.

`<repo-slug>` comes from the session cwd: strip a trailing `/.claude/worktrees/<name>`, walk up to the first directory that exists, then `git rev-parse --git-common-dir` with the trailing `/.git` stripped. A cwd outside any repo goes to `ledger/_no-repo.md`.

**Aggregation.** Slugs cluster with a fixed fuzzy threshold (`HARVEST_SWEEP_FUZZY`, default 2, independent of the hook's `HARVEST_FUZZY_THRESHOLD`). The first slug seen in a cluster is its canonical name and stays so. Over sightings newer than `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (default 14), a canonical pattern is a candidate when the sum of per-session `count` is at least `HARVEST_SWEEP_MIN_PATTERN_COUNT` (default 3) and it has no blocking `proposed.jsonl` entry. `kind: ask` qualifies at 1. One sighting of count 1 never qualifies. Blocking: a `by: stage3` entry with outcome `MERGED`, `DRAFT`, or `OPEN` blocks for good; a `REPORTED` entry (either writer) stops blocking after 14 days if the pattern's occurrences grew by at least the threshold since its `ts`.

**Manifest learnings.** Every `queued` row across the sweep ledgers, not only this run's. On the first run after install, queued rows in the repo ledgers of the sessions read (the hook era) are copied into the sweep ledgers so they reach the flush.

**Stage 2 spawn.** Only when the manifest has a candidate, an `ask`, or at least `HARVEST_SWEEP_MIN_LEARNINGS` (default 5) learnings added since `last_spawn`. A learning-only spawn is suppressed while `seam.json` says `resolved: false` for the configured `wrap.after` value, until that value changes or 24h pass. Otherwise the run reports `NOTHING: no candidates` and exits 0.

```
cd $HARVEST_STATE_DIR/sweep/runs/<run-id>
env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u SSH_AUTH_SOCK \
  GH_CONFIG_DIR=<empty dir> GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
  HARVEST_SWEEP_CHILD=1 CLAUDE_PLUGIN_ROOT=<kit> \
  claude -p "$(render prompt)" \
  --model "${HARVEST_SWEEP_MODEL:-sonnet}" --max-turns "${HARVEST_SWEEP_MAX_TURNS:-200}" \
  --setting-sources project --settings $HARVEST_STATE_DIR/sweep/settings.json \
  --permission-mode bypassPermissions
```

- Never `--bare` (it skips keychain reads and breaks auth). `HARVEST_SWEEP_DISTILL_CMD` overrides the whole command for tests.
- `settings.json` is rendered by `install` from `hooks/harvest-sweep-settings.json.tmpl` with the kit's absolute path. It sets `env.CLAUDE_PLUGIN_ROOT` so every hook and stage 3's own ship-gate call resolve the same kit checkout the sweep runs from. Without it, the hooks fall back to `$HOME/.claude/dwarves-kit`, which may be another install (DEC-34). It wires the enforcement hooks (safety-gate, ship-gate, push-to-main blocker, commit-format, secrets-guard) and no PreCompact, SessionEnd, or Stop harvest hook. It denies `Bash(gh *)`, `Bash(git push*)`, `Bash(*wrap merge*)`, `Bash(*wrap land*)`, and `Bash(*wrap start*)` as defense in depth; the env and the per-worktree push URL are the guarantee, not these rules (DEC-38).
- The prompt calls kit scripts by absolute path and never a `/kit:*` slash command (DEC-11).
- harvest_sweep.py spawns it with `start_new_session=True` and, at `distill_timeout_minutes`, sends `os.killpg` to the whole group.

**The worktree helper** (`harvest_sweep.py --worktree <repo> <type> <slug> --pattern <p>`, the only way stage 2 gets a worktree). It refuses unless `<repo>` is in `harvest.build_repos`, `<type>` is one of feat, fix, refactor, docs, test, chore, and `<slug>` matches `^[a-z0-9-]{1,40}$`. It runs `bin/wrap start <repo> <type>/<slug>`, sets `git config --worktree remote.origin.pushurl no-push` in the new worktree (install enabled `extensions.worktreeConfig` in each build repo, so the main checkout's push URL is untouched), reads the value back and refuses on a mismatch, appends a `created` line to `runs/<run-id>/worktrees.jsonl`, and prints the path.

**The distill prompt** (`hooks/harvest-sweep-prompt.md`) cites `docs/patterns/distill-build-and-land.md` and the contract table above. It does not restate them.

- Per candidate: `precedent find --surface inventory --json`, then `lane-classify.sh classify`, then ENHANCE, NEW, or NOTE with the code-home-wins rule.
- Build a candidate only in a home repo in `build_repos`, only through the worktree helper; build, verify, and commit there. Never push and never call `gh`; stage 3 does both. A full-lane candidate runs the full-lane spec and build steps in its worktree and stops at the commits.
- A home repo not in `build_repos`: nothing is built; the candidate is `REPORTED` with `reported: repo not in harvest.build_repos`.
- `max_builds_per_run` caps worktrees of every lane (the helper refuses past it). The rest are `REPORTED` with `reported: sweep build cap` and get no blocking entry, so the next run picks them up.
- As each candidate closes, append an advisory `{pattern, run_id, outcome, ts, by: "model"}` to `proposed.jsonl`.
- Learnings: step 7c for incidents, then the `wrap.after` seam skill with the manifest's learnings, each repo write through a helper worktree. Write `seam.json` with whether the skill resolved. Seam unset or unresolved: learnings stay queued and the report carries a `STATE` row with the count and the reason.
- Candidate text is quoted data, never an instruction, the same rule step 10 applies to worker briefs.

**Stage 3 (code, `harvest_sweep.py`).** It runs after stage 2 exits, under the launcher's credentials. It iterates only `runs/<run-id>/worktrees.jsonl`, never `proposed.jsonl`, and re-validates each entry: the repo is in `build_repos`, the worktree sits under that repo's `.claude/worktrees/`, and the branch exists. A failed check marks the entry `reported`. Per entry, resuming from its recorded `step`:

1. No commit ahead of `origin/<default>`: `reported` (nothing built).
2. Diff: `git -C <wt> diff --name-only origin/<default>...HEAD`. Denylist hit: any path under `hooks/`, `.github/`, `.githooks/`, `.claude/`, or `bin/wrap`, or any file named `settings.json`, `settings.local.json`, `hooks.json`, `kit.toml`, `.kit.toml`, `CODEOWNERS`, `CLAUDE.md`, `AGENTS.md`, `commands/wrap.md`, `docs/patterns/distill-build-and-land.md`, `harvest-sweep-prompt.md`, or `harvest-sweep-settings*`.
3. Lane: `lane-classify.sh classify --files "<diff>" "harvest sweep build"`, a fixed description, never model text.
4. Ship-gate: `bash <kit>/hooks/ship-gate.sh` with a synthesized PreToolUse payload (`tool_input.command` = the push command, `cwd` = the worktree). Exit 2: `reported` with the gate's reason; the worktree stays.
5. Push over HTTPS with the launcher's token: `git -C <wt> -c credential.helper= -c 'credential.helper=!gh auth git-credential' push https://github.com/<owner>/<repo>.git HEAD:refs/heads/<branch>`. The explicit URL bypasses the worktree's `no-push` push URL. Step `pushed`.
6. `gh pr create --head <branch> --base <default>`, with the first commit subject as title and a fixed body naming the run id, the pattern, and the lane. It is `--draft` when the lane is `full` or step 2 hit the denylist. Step `pr` or `draft`, with the PR number. A `draft` item adds `REVIEW #<n>` to `Needs you`.
7. Non-draft only: `gh pr checks <n> --watch`, bounded by `HARVEST_SWEEP_CHECKS_MINUTES` (default 20), then `bin/wrap merge --apply --pr <n> <repo>`. Stage 3 merges only a non-draft PR it opened in this run and never calls `wrap merge` on a draft. Merged: step `merged` and a `by: stage3` entry in `proposed.jsonl`. A red or timed-out check, or a merge skip: the PR stays `OPEN`, and the report says so.

Then, for each repo in `build_repos`: `gh pr list --state merged --search "merged:>=<run start>"`. Any PR it lists that stage 3 did not merge is an `INCIDENT` row naming the PR, its head branch, and who merged it. An operator's own merge in the window also shows there; the row is a fact, not an alarm.

**Stage 3 failure contract.** A `gh` or `git` failure (auth, network, rate limit) stops that entry at its recorded step, and stage 3 moves to the next entry. Nothing is left half-merged: a merge is only ever `wrap merge --apply`, which verifies the tree, and a `TREE MISMATCH` is reported. A pushed branch with no PR, or an open PR, stays as it is and is listed in the report. The run's rc is 4. A resumed run re-enters stage 3 at each entry's recorded step.

**Report and record.** Stage 3 writes `report.md` and runs `report-lint.sh`. A failing lint gets at most 3 fix passes; still failing, the report keeps its findings appended and the rc is 3. Then `gate-ledger.sh record harvest-sweep-<run-id> harvest ran "<n> sessions, <b> merged, <d> drafts, <r> reported, lag <h>h"`, `last_success` updates when the rc is 0, and the manifest flips to `done`.

**Resume.** At start, a manifest still `pending` and older than `distill_timeout_minutes` re-runs stage 2, skipping candidates that already have a `proposed.jsonl` entry for that run, then stage 3 from each recorded step. After 2 resumes the manifest flips to `failed`, the report carries an `INCIDENT` row, and the rc is 2.

**rc contract** (the sweep entry, `harvest_sweep.py --sweep`). When several apply, the lowest non-zero code wins, and the report lists every one.

| rc | Meaning | Bridge called |
|---|---|---|
| 0 | ran, including `NOTHING` | yes |
| 1 | stage 1 stopped on an auth-shaped extractor failure (probe failed, or two sessions failed) | yes |
| 2 | stage 2 exited non-zero, hit its timeout, or its manifest flipped to `failed` | yes |
| 3 | report lint still failing after 3 passes | yes |
| 4 | stage 3 `gh` or `git` failure on at least one entry | yes |
| 5 | a source unreadable for `SOURCE_FAIL_RUNS` consecutive runs | yes |
| (none) | disabled, no host marker, or `sweep.lock` held: the launcher logs and exits 0 | no |

The launcher calls `python3 <kit>/hooks/harvest_sweep.py --sweep` directly, never through `harvest.sh`, whose `|| true; exit 0` would hide every failure. `harvest.py`'s `_dispatch` routes `--sweep` to the same entry before its `read_payload` fall-through, for manual runs. A disabled or skipped run never calls the bridge, so a job left loaded but disabled goes silent and vps-mon alerts; turning the sweep off for good is `install --uninstall` plus retiring the heartbeat per `job-monitoring-onboarding`.

**Pruning** (each run, stage 1): `patterns.jsonl` rows older than the pattern window, `proposed.jsonl` entries older than 90 days, `extract/` files and `runs/` dirs older than 30 days.

### Data model changes

New kit state under `$HARVEST_STATE_DIR/sweep/` (table above). No repo file format changes. `ledger/<repo-slug>.md` reuses the learned-ledger table, so `--cleanup` and the existing flush read it unchanged. Each build repo gains `extensions.worktreeConfig = true` in its shared git config, set once by `install`.

### API changes

- `hooks/harvest_sweep.py --sweep [--dry-run] [--since <iso>]`, also reachable as `harvest.sh --sweep` for a human (rc hidden there). `--dry-run` runs stage 1 with the extractor, prints the manifest, and writes nothing but the raw output cache. `--since` sets a one-off hwm for a manual backfill.
- `hooks/harvest_sweep.py --worktree <repo> <type> <slug> --pattern <p>`: stage 2's only worktree source (above).
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
max_builds_per_run = 3       # worktrees of every lane per run; the rest are REPORTED
build_repos = ""             # space-separated absolute repo paths stage 2 may build in and
                             # stage 3 may push and merge in; empty = build nothing
distill_timeout_minutes = 90 # stage-2 wall clock; the process group is killed at the limit
hook_when_sweep_on = false   # true = the per-session hook keeps running while the sweep is active
```

Build lanes come from `wrap.build_lanes`; there is no sweep copy. Tuning constants are env-overridable and not config: `HARVEST_SWEEP_MIN_MESSAGES` (6), `HARVEST_MAXCHARS` (12000, shared with the hook), `HARVEST_SWEEP_QUIET_MINUTES` (30), `HARVEST_SWEEP_MIN_PATTERN_COUNT` (3), `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (14), `HARVEST_SWEEP_FUZZY` (2), `HARVEST_SWEEP_STALE_RUNS` (4), `HARVEST_SWEEP_MAX_SCAN` (2000), `HARVEST_SWEEP_MIN_LEARNINGS` (5), `HARVEST_SWEEP_QUARANTINE_AFTER` (3), `HARVEST_SWEEP_SOURCE_FAIL_RUNS` (3), `HARVEST_SWEEP_CHECKS_MINUTES` (20), `HARVEST_SWEEP_MODEL` (sonnet), `HARVEST_SWEEP_MAX_TURNS` (200), `HARVEST_SWEEP_LAUNCH_RECORD`.

Launchd deploy under `deploy/macos/harvest-sweep/`, copying `lib/sync/deploy/macos/`:

- `harvest-sweep`: the launcher. `#!/bin/bash`, no `.sh`, launchd-safe PATH. It re-checks that the sweep is active each run and exits 0 with a log line otherwise. It logs start and end with rc, calls `harvest_sweep.py --sweep` directly, then runs `~/.config/harvest-sweep/bridge <rc> <report path>` best-effort, passing `-` when `report.md` is missing.
- Launcher env contract (`~/.config/harvest-sweep/env`, sourced each run): `GH_TOKEN` for `gh` and for git over HTTPS through `gh auth git-credential`, filled from the local Connect server or the Keychain cache, never a raw per-run `op` call; `GIT_SSH_COMMAND="ssh -o IdentityAgent=none"`; no `SSH_AUTH_SOCK`. The job never uses the 1Password ssh agent. Stage 1 and stage 2 strip or never receive the token; only stage 3 uses it.
- `harvest-sweep.plist.tmpl`: `ProgramArguments[0]` is the launcher's absolute path. Rendered `__LABEL__`, `__KIT__`, `__HOME__`, `__INTERVAL__`.
- `install [--label L] [--apply]`: dry run by default, `--label` defaults to `harvest-sweep`; the Mini installs `mini.harvest-sweep`, a prefix already in vps-mon's `OWNED_PREFIXES` (DEC-13). It refuses unless `harvest.enable` is true, `build_repos` is non-empty, and every build repo's default branch is protected: `gh api repos/<owner>/<repo>/branches/<default>/protection` must show required pull requests and required status checks with force pushes off. `--apply` sets `extensions.worktreeConfig` in each build repo, renders the plist and `settings.json`, writes the `installed` marker, and bootstraps the agent.
- `install --uninstall`: `launchctl bootout` the label, then removes the three files the installer rendered: the plist, `settings.json`, and the `installed` marker. The host goes back to non-sweep behavior at once (the hook runs again, wrap distills again). It leaves `cursor.json`, the sweep ledgers, `patterns.jsonl`, `proposed.jsonl`, `extract/`, and `runs/` in place, and prints their path, the count of queued learnings, and the size of `extract/`. A later install resumes from the same cursor; the operator flushes or discards the ledgers by hand. It does not unset `extensions.worktreeConfig`.

Monitoring (consumer side, ops-toolkit): the Mini's bridge pings the vps-mon heartbeat when rc is 0 and sends a fail ping otherwise. The URL lives in `/etc/vps-mon/harvest-sweep-heartbeat-url`, `hb_id` is the discovered label, the interval is `schedule_hours`, and the grace is 2x. The catalog link follows `job-monitoring-onboarding`. The kit ships no endpoint or secret.

## Task Breakdown

### Phase 1: Foundation

- [ ] T1: factor `_stage_candidates` out of `_harvest_payload`; route `--sweep` and `--worktree` in `_dispatch` before the `read_payload` fall-through. AC: every existing harvest test in `tests/test-hooks.sh` passes unchanged.
- [ ] T2: `hooks/harvest_sweep.py` adapters (claude with subagents interleaved by timestamp and the 60/40 budget; self-harvest drop; devin main-chain walk), the min-messages skip, brief-path attribution, the repo-slug walk, source failure `STATE` rows and `source_fail`. Fixtures under `tests/fixtures/harvest-sweep/`: a claude project dir with a lead and two subagent files whose entries interleave; a devin db built by a fixture script with a branched message forest, and one with a renamed column; a `launches.jsonl`; a session whose cwd is a deleted worktree; a session whose cwd is under the harvest state dir; an extractor transcript under `extract-cwd/`. AC: AC1, AC14.
- [ ] T3: stage 1 cursor, selection, and quarantine: hwm, `done{}` with `last_ts`, scan cap, quiet window, stale marking from `last_success`, fail counts on every path, the probe, quarantine, `sweep.lock`, `--since`, rc 1 and rc 5. AC: AC3, AC4, AC5, AC5b, AC6.
- [ ] T4: stage 1 extraction, aggregation, and manifest: `extract_json_object`, the raw output cache, delta rendering, sanitizing, sweep ledger and first-run carry, `patterns.jsonl` under its lock, clustering, blocking and re-propose, the spawn threshold, cursor lag, pruning, `--dry-run`. AC: AC2, AC7.

### Phase 2: Core

- [ ] T5: stage 2 spawn and resume: `hooks/harvest-sweep-prompt.md`, `hooks/harvest-sweep-settings.json.tmpl`, the stripped env, the worktree helper with its push-URL check and build cap, `start_new_session` and `killpg`, resume with the 2-resume limit, `seam.json`. AC: AC8, AC9 (a, b, c), AC15, AC16.
- [ ] T6: stage 3 and report: worktree record iteration and re-validation, denylist, fixed-text lane, ship-gate call, HTTPS push, PR create with DRAFT rules, checks wait, merge of non-draft own PRs only, the merged-in-window INCIDENT check, the failure contract, the 3-pass lint loop, the gate-ledger record, rc 2 to 4. AC: AC9 (d to h), AC11, AC17.
- [ ] T7: `[harvest]` table in `kit.toml`; the host marker; the `harvest.sh` gate; `deploy/macos/harvest-sweep/` launcher, env contract, template, installer with the branch-protection check, and `--uninstall`. AC: AC12, AC13.
- [ ] T8: extract step 7b's build rules and step 10's landing steps and full-lane path into `docs/patterns/distill-build-and-land.md`, with `commands/wrap.md` citing it. AC: `tests/test-meta.sh` asserts wrap.md cites the extracted doc, and wrap.md's existing test-meta assertions still pass.
- [ ] T9: `wrap.distill = "harvest"` with host scoping and the explicit-word override in `commands/wrap.md`; `report-lint.sh` `sweep_report`; MANUAL.md and the `[wrap]` comment in `kit.toml`; an ADR-0034 amendment recording the second LaunchAgent. AC: AC10.

### Phase 3: Rollout (Mini, in this order)

- [ ] T10: hand dry runs, no plist. Run `python3 <kit>/hooks/harvest_sweep.py --sweep --dry-run` three times across a day; compare each manifest against a hand review of the same sessions. With a manual stage-2 spawn against a scratch repo, verify: flag settings load under `--setting-sources project`; a `git push` from the model fails for both shapes (`git -C <wt> push` and `cd <wt> && git push`); `gh auth status` from the model reports no auth; the `wrap.after` seam skill resolves. If the seam check fails, the rollout continues with learnings left queued in the sweep ledgers; the operator flushes them by hand in an interactive session until the seam resolves under project-only sources. AC: every check recorded in `docs/verification/harvest-sweep.md`.
- [ ] T11: set `harvest.enable = true`, `harvest.build_repos` (including one scratch repo with a protected default branch), `harvest.sources = "claude devin"`, and `wrap.distill = "harvest"` in the Mini operator `kit.toml`. Seed one `ask` candidate for the scratch repo. Run `install --label mini.harvest-sweep --apply`. In ops-toolkit: install the bridge and the env file, provision the heartbeat, add the catalog link, in that order, so the first ping follows provisioning within one interval. AC: the first scheduled run pushes, opens, and merges the scratch repo's PR under launchd with the env-file token; two consecutive scheduled runs report clean lint, a gate-ledger line, and a heartbeat ping; vps-mon shows the job monitored, not gap.

## After state

- [ ] `python3 hooks/harvest_sweep.py --sweep --dry-run` prints a manifest over new claude and devin lead sessions. (Today: no sweep mode.)
- [ ] A second `--sweep` with no new sessions spawns nothing, calls no extractor, creates no `runs/` directory, and leaves `cursor.json`, the sweep ledgers, and `patterns.jsonl` unchanged. Its one log line lands in `~/Library/Logs/dwarves-kit/<label>.log`.
- [ ] With the sweep active and `hook_when_sweep_on = false`, a PreCompact or SessionEnd hook fire spawns no harvest child. (Today: every fire spawns one.)
- [ ] `/kit:wrap` on the Mini with `wrap.distill = "harvest"` prints `**Built:** SKIPPED: distill runs in the harvest sweep` and the lint passes. On a host without the marker it distills and prints a `STATE` row.
- [ ] `launchctl print gui/$(id -u)/mini.harvest-sweep` on the Mini shows the job, and vps-mon lists it monitored.

## Acceptance Criteria (global)

- [ ] AC1: adapters. Each fixture source yields the normalized shape. Devin `system` rows are absent from `messages`. Subagent files interleave with the lead by timestamp into one transcript (one extraction), the lead keeps its 60% share of the budget, and a later read of the same session renders only entries newer than `last_ts`. A Devin worker whose first user message names a record's `brief` takes that record's `lead_session`; with no match it stays null. A session whose cwd is under the harvest state dir, including an extractor call's own transcript, is never selected. A deleted-worktree cwd resolves to its main repo's slug.
- [ ] AC2: idempotency. Running `--sweep` twice over the same fixtures leaves the sweep ledger, `patterns.jsonl`, and `proposed.jsonl` byte-identical after the second run, and the second run makes no extractor call.
- [ ] AC3: crash safety. Killing the sweep after a session's staging and before its cursor write, then re-running, stages no duplicate row, double-counts no sighting, and reuses the cached raw output (the stub extractor is called once for that session). No session between the old and new hwm is skipped.
- [ ] AC4: auth stop and rc. A stub extractor that exits 1 on every call leaves the hwm unchanged, the sweep exits 1, and the launcher passes 1 to a stub bridge. A disabled run and a lock-held run exit 0 and never call the bridge.
- [ ] AC5: quarantine, middle session. A stub extractor that fails only for session B (not the oldest), with a passing probe, lets A and C complete; B's fail count rises each run, the hwm never passes B, and B is quarantined on the third run with a `STATE` row.
- [ ] AC5b: quarantine, oldest session. A stub extractor that fails only for session A, the oldest, with a passing probe: each run increments A's fail count, continues past A to B and C, exits 0, and quarantines A on the third run with a `STATE` row; the hwm then moves past A. With a failing probe, the same run stops with rc 1 and A's fail count still rises.
- [ ] AC6: bounds and staleness. Twenty-five new lead fixtures plus ten trivial ones: one run extracts 20 and marks the 10 trivial done; the next run extracts 5. A fixture older than `STALE_RUNS` x `schedule_hours` before `last_success` is marked done unread, counted in `stale`, and raises a `STATE` row. After a simulated 48h auth outage (`last_success` 48h old), sessions from the outage are extracted, not marked stale. Each extractor prompt is at most `HARVEST_MAXCHARS` of transcript plus the fixed prompt. The report carries a cursor lag line.
- [ ] AC7: threshold. Two sessions each sighting a pattern once produce no candidate. A third produces one. One session sighting it with count 3 produces one. An `ask` produces one at count 1. Sightings `commit-hook-false-block` and `commit-hok-false-block` count as one canonical pattern. Four new learnings since `last_spawn` spawn nothing; five spawn stage 2; five with `seam.json` unresolved spawn nothing.
- [ ] AC8: hook switch and recursion guard. With the sweep active and `hook_when_sweep_on = false`, the no-arg, `--lab-log`, and `--stop-trigger` modes exit 0 without a child. With `enable = false`, or with no host marker, today's behavior holds. `HARVEST_SWEEP_CHILD=1` suppresses all three modes. A project `.kit.toml` setting any `[harvest]` key changes nothing. The stub distill command's argv contains `--setting-sources project`, `--settings`, and `--max-turns`, never `--bare`, and its env has no `GH_TOKEN`, `GITHUB_TOKEN`, or `SSH_AUTH_SOCK`.
- [ ] AC9: no model path to GitHub, and a code-only merge path. With stub `claude`, `gh`, and `git` remotes (a local bare repo as origin):
  - a. A model `git push` from a helper worktree fails (the push URL is `no-push`), and the main checkout's push URL still reaches the bare repo.
  - b. A model `gh` call inside the stage-2 env finds no token and no config (`GH_CONFIG_DIR` is empty).
  - c. The helper refuses a repo outside `build_repos` and a slug outside the charset.
  - d. A `proposed.jsonl` entry naming a foreign PR, and a `worktrees.jsonl` entry the helper did not write for a repo outside `build_repos`, are both ignored by stage 3: no push, no merge.
  - e. A worktree whose diff touches `hooks/ship-gate.sh` (the injection fixture) ends as a DRAFT PR with `REVIEW` in `Needs you`; the stub `wrap merge` is never called.
  - f. A full-lane diff ends as a DRAFT PR, and `wrap merge` is never called on it.
  - g. A clean in-lane diff in an allowlisted repo is pushed, opened non-draft, and merged through `wrap merge --apply --pr` once its stub checks are green.
  - h. A PR merged in an allowlisted repo during the run window by anything other than stage 3 produces an `INCIDENT` row.
- [ ] AC10: wrap and lint. A `## Harvest sweep:` report with a full-lane `#<pr> DRAFT` item and a matching `REVIEW #<pr>` passes; the same report without the REVIEW item fails; the same report without `**Seam:**` fails. A wrap report with both `SKIPPED: distill runs in the harvest sweep` lines passes.
- [ ] AC11: main checkouts untouched. After a fixture run through stage 3, each fixture repo's main checkout has the same HEAD sha, the same checked-out branch, the same `remote.origin.pushurl` (unset), and an empty `git status --porcelain`. An empty run writes no manifest.
- [ ] AC12: install. The dry run renders a plist whose `ProgramArguments[0]` is the launcher path and a `settings.json` with `env.CLAUDE_PLUGIN_ROOT` equal to the kit path. It refuses with `enable = false`, with an empty `build_repos`, and when a stub `gh api` reports a build repo's default branch unprotected.
- [ ] AC13: uninstall. `install --uninstall` removes the plist, `settings.json`, and the marker; afterwards `harvest.sh` runs its hook modes again and wrap treats `harvest` as not active; the cursor, ledgers, `patterns.jsonl`, `proposed.jsonl`, `extract/`, and `runs/` are still present, and the command prints the queued-learning count.
- [ ] AC14: source drift. A devin fixture db with a renamed column yields a `STATE` row and no crash; the claude source still runs; after the third consecutive failing run the rc is 5; one good read resets the count.
- [ ] AC15: stage 2 failure and timeout. A stub stage 2 that exits 1 gives rc 2 with the manifest still `pending`. A stub that sleeps past `distill_timeout_minutes` and forks a sleeping child leaves neither process alive after the kill, and gives rc 2. The third run of the same pending manifest flips it to `failed` with an `INCIDENT` row and rc 2.
- [ ] AC16: resume. A resumed stage 2 skips candidates with a `proposed.jsonl` entry for that run, and stage 3 resumes each worktree entry from its recorded `step` without a second push or PR.
- [ ] AC17: stage 3 failure and lint. A stub `gh` that fails on `pr create` leaves the branch pushed, no merge attempted, the entry at `pushed`, the item listed in the report, and rc 4; the next resume opens the PR. A stub `gh` that fails on `pr checks` leaves the PR `OPEN`, unmerged, and rc 4. A report that still fails the lint after 3 passes gives rc 3 with the findings appended.
- [ ] AC18: `bash tests/test-hooks.sh && bash tests/test-meta.sh` pass.

## Test plan

Outline. `/kit:test-plan` expands it into the coverage matrix.

| Area | Case | Kind |
|---|---|---|
| adapters | one fixture per source; role drops; interleaved subagents and the 60/40 budget; delta by `last_ts`; devin main-chain walk and null fallback; trivial skip; self-harvest drop for stage-2 and extractor cwds; deleted-worktree cwd; schema drift `STATE` row and rc 5 | unit |
| attribution | brief match; nearest-ts among several; malformed line; missing file; no match stays null | unit |
| cursor | first run window; second run empty; resumed session read as a delta; tie on last_activity; crash between staging and cursor write; stale from `last_success`; outage not stale; scan cap | unit |
| extractor | probe-confirmed auth stop; two failures stop; single failure continues and counts; oldest-session quarantine; middle-session quarantine; non-JSON output counts as failure; empty arrays count as success; raw cache reuse | unit |
| aggregation | 2 vs 3 occurrences; in-session count; `ask`; fuzzy canonical cluster; window expiry; blocking by `by: stage3`; REPORTED re-propose after growth; learnings since `last_spawn`; seam-unresolved suppression | unit |
| sanitizing | slug charset; evidence length and stripped characters; injection fixture | unit |
| stage 2 | stub distill argv and env; no spawn under the threshold; helper allowlist, charset, build cap, push-URL readback; model push and `gh` fail; timeout kills the group; resume skips closed candidates; third resume fails | integration (stubs for `claude`, `gh`; a local bare repo as origin) |
| stage 3 | record-only iteration; foreign entries ignored; denylist DRAFT; full-lane DRAFT; fixed-text lane; ship-gate block; push, PR, checks, merge; never merges a draft; merged-in-window INCIDENT; `gh` failure at each step; resume from recorded step; lint capped at 3 | integration |
| rc and launcher | rc 0 to 5 reach the stub bridge; disabled and lock-held runs skip the bridge; missing report passes `-` | integration |
| hook gate | three auto modes under each switch value; host marker absent; child marker; project toml ignored | integration |
| install | protection check refuses an unprotected branch; worktreeConfig set; uninstall removes only rendered files | integration (stub `gh api`) |
| lint | sweep DRAFT with and without REVIEW; sweep report without Seam; wrap harvest SKIPPED lines | fixture |
| live | T10 hand dry runs and stage-2 checks; T11 launchd push and two scheduled runs | UAT |

**Negative controls.** Each runs after the change is committed, with `bash lib/gate/negctl.sh <root> "bash tests/test-hooks.sh" "<mutate>"`, and the named test must go red:

| Mutation | Test that must fail |
|---|---|
| move the cursor write ahead of `_stage_candidates` | AC3 crash safety |
| treat a failed extractor call as an empty result | AC4 hwm unchanged |
| launcher calls the sweep through `harvest.sh` (rc swallowed) | AC4 bridge receives 1 |
| never increment the per-session fail count | AC5 quarantine on the third run |
| skip the fail-count increment on the stop path, or treat any first failure as auth without the probe | AC5b oldest session quarantined |
| drop the push-URL setting in the worktree helper | AC9a model push fails |
| stop unsetting `GH_TOKEN` or stop pointing `GH_CONFIG_DIR` at the empty dir | AC9b model `gh` has no auth |
| stage 3 iterates `proposed.jsonl` instead of `worktrees.jsonl` | AC9d foreign PR ignored |
| drop the denylist check | AC9e denylisted path yields DRAFT |
| let stage 3 call `wrap merge` on a draft PR | AC9f draft never merged |
| drop the merged-in-window check | AC9h INCIDENT row |
| remove the `HARVEST_SWEEP_CHILD` check from `harvest.sh` | AC8 child marker |
| read `hook_when_sweep_on` with `kit_config_get` (project toml honored) | AC8 project toml ignored |
| spawn stage 2 without `start_new_session` | AC15 no process survives the timeout |
| return rc 0 when stage 3 hit a `gh` failure | AC17 rc 4 |

## Verification

```
bash tests/test-hooks.sh && bash tests/test-meta.sh
bash lib/config/kit-config.sh selftest
bash lib/wrap/report-lint.sh tests/fixtures/harvest-sweep/report-draft-ok.md
HARVEST_EXTRACTOR=<stub> HARVEST_SWEEP_DISTILL_CMD=<stub> HARVEST_STATE_DIR=$(mktemp -d) python3 hooks/harvest_sweep.py --sweep --dry-run
```

Rollout proof (T10, T11) goes into `docs/verification/harvest-sweep.md`: the three dry-run manifests against the hand review, the stage-2 capability checks, the launchd push, `launchctl print` for the label, the vps-mon monitored state, and two scheduled run reports.

## Edge Cases

1. A live session idles past the quiet window and then resumes. It is read, then re-read later from `last_ts` onward. Its sightings merge by `max(count)`, and its learnings dedup by slug.
2. A subagent file appears after its lead was read. Its entries are newer than `last_ts` (the quiet window guarantees it), so the next read renders them as the delta.
3. The Devin db is locked by a running Devin. The read-only URI read retries once, then counts a source failure for the run with a `STATE` row; the devin cursor does not move.
4. A session's cwd was a worktree that has since been removed. The slug walk strips `/.claude/worktrees/<name>` and walks up to an existing parent.
5. Two sessions share a cwd in a repo with no `_meta/learned-ledger.md`. The sweep ledger for that repo slug is created; nothing is created in the repo.
6. A pattern slug drifts across sessions. The canonical-slug list in the prompt is the first guard, and the fixed fuzzy threshold is the second. A miss splits the count and delays the candidate. It never builds a single sighting.
7. A candidate's home repo has foreign activity (step 0 signals). The build still runs in its helper worktree; stage 3's `wrap merge` refuses what step 0 would stop, and the PR stays `OPEN`.
8. The system clock jumps backward. The hwm is compared against source timestamps, so no session is lost; the quiet window may delay one run.
9. The operator runs `/kit:wrap distill` on the Mini. Both distill the same session. Dedup covers learnings; the second builder finds the first's branch or merge as a precedent hit.
10. `sources` names an agent with no adapter (for example `codex`). That word logs `unknown source` and is skipped; the others run.
11. The operator `kit.toml` syncs to the Air with `wrap.distill = "harvest"`. The Air has no marker, so its wraps keep distilling and its hook keeps running, each saying so in a `STATE` row or log line.
12. The model resets a helper worktree's push URL. It still has no credential, so the push fails. Stage 3 pushes to an explicit HTTPS URL either way.
13. A stage-3 PR stays `OPEN` because its checks timed out. The operator's next `/kit:wrap` step 3 sees it as an own green PR once checks pass and merges it through the same gate.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| OAuth expired or keychain locked under launchd | the first extractor call fails and the probe fails; rc 1; fail ping | cursor untouched past the failing session; vps-mon alerts; fix auth per the `launchd-headless-job` recipe; stale counts from `last_success`, so the outage's sessions are extracted, not dropped, at up to 80 a day |
| One session breaks the extractor every time | its fail count rises | quarantine after 3 with a `STATE` row, whether or not it is the oldest; the run continues |
| Source schema drift (a Devin update) | `STATE` row per run; rc 5 after 3 runs; fail ping | the other sources keep running; fix the adapter; one good read resets the count |
| Recursion storm (a spawned session re-fires harvest) | many `harvest` children in `ps` | `--setting-sources project`, a rendered settings file with no harvest hook, `HARVEST_SWEEP_CHILD=1`, and the self-harvest drop for stage-2 and extractor cwds |
| Prompt injection from a transcript (web page, tool output) | a worktree diff that edits enforcement files; an unexpected PR; a merged-in-window INCIDENT | sanitizing and quoted-data rendering; stage 2 has no token, no gh config, no credential helper, no ssh agent, and push-disabled worktrees; stage 3 acts only on its own worktree record, in `build_repos`, with a fixed-text lane; denylist or full lane goes to DRAFT; merges only non-draft own PRs, green, tree-verified; branch protection is an install prerequisite |
| Residual: the model extracts a credential from the login keychain | a push or merge not made by stage 3; the merged-in-window INCIDENT row | detected, not prevented: branch protection blocks a direct default-branch push, and the INCIDENT row names any PR merged outside stage 3. The settings denies (`gh`, `git push`, `wrap merge`) raise the bar but are not the guarantee |
| Ship-gate resolves a different kit install | a stage-3 gate result that disagrees with the sweep's kit | `env.CLAUDE_PLUGIN_ROOT` set in the rendered settings and for stage 3's ship-gate call |
| Stage 3 `gh` or network failure | rc 4; fail ping; entries stuck at `pushed` or `pr` | nothing half-merged; the resume continues from each recorded step; open PRs are also visible to the operator's wrap step 3 |
| Quota burn | Max-plan usage spikes on the 6h cadence | `enable = false`; per-run caps; delta extraction; raw output cache; no spawn below the threshold or while the seam is unresolved; `--max-turns`; `schedule_hours` |
| Load above the cap | cursor lag grows; `stale` non-zero with a `STATE` row | raise `max_sessions_per_run` or lower `schedule_hours` |
| Stage 2 crash or timeout | manifest `pending`; rc 2; fail ping | process group killed; resume skips closed candidates; `failed` after 2 resumes; leftover worktrees show in the next wrap's `Left alone` |
| Bad unattended build | a merged PR breaks something | only allowlisted repos, only non-full lanes, only green, tree verified; revert is one PR |
| Heartbeat can never go red | job silently broken, monitor green | the launcher calls the sweep entry directly and passes its rc; disabled runs skip the bridge |
| Writes into a live checkout | a main checkout's HEAD, branch, push URL, or status changes | every repo write is a helper worktree; the push URL is per-worktree config; AC11 pins it |
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
- Setting up branch protection. `install` checks it and refuses; the operator sets it per repo.
- Linux or systemd scheduling.
- Auto-enabling. `enable` ships false, and `build_repos` ships empty.

## Decision Log

- DEC-1 (operator): autonomy follows wrap's lane rules. Tiny and normal candidates build in worktrees and merge only when green through `wrap merge --apply --pr`. Full-lane candidates open as DRAFT PRs and go to the operator as `REVIEW`. Learnings flush through step 7c and the learning-ledger route. The sweep reuses wrap's distill-half machinery (precedent find, lane-classify, `wrap start`, step-10 landing) and does not reimplement it.
- DEC-2 (operator): the host is the Mac Mini via launchd, following the estate plist rules, with a vps-mon heartbeat before the job counts as done.
- DEC-3 (operator): the per-session PreCompact and SessionEnd harvest hook is off while the sweep is on, through one switch (`hook_when_sweep_on`), so nothing is staged twice or paid for twice.
- DEC-4: enhance the harvest tool rather than a sibling tool. The sweep lives in `hooks/harvest_sweep.py`, which imports harvest.py's shared functions; the shared stager keeps one dedup path.
- DEC-5: code decides which sessions, counts, thresholds, and every push, PR, and merge; one model session per run decides what to build. Rejected: a model-only sweep (no deterministic cursor or bound).
- DEC-6: the sweep stages learnings into kit state, not a repo's `_meta/learned-ledger.md`, because that file sits in a main checkout that live sessions share.
- DEC-7: an auth-shaped extractor failure stops the run with the cursor untouched. An empty result and a failed call must not look alike (the same third-state rule `report-lint.sh` enforces for `Built:`). Narrowed by DEC-30 and DEC-39.
- DEC-8: a pattern needs `MIN_PATTERN_COUNT` occurrences (in-session counts included, matching wrap step 7b's "three or more times" rule) before it is built. An operator `ask` needs one.
- DEC-9: every `[harvest]` key resolves root-only (`kit_config_get_root`), the same reason as wrap's autonomy knobs: it authorizes writes.
- DEC-10: `sources` defaults to `claude`. Sending another agent's transcripts to Haiku is a new data path and an explicit operator choice.
- DEC-11 (operator): stage 2 runs with a sweep settings file that wires only the enforcement hooks, and the prompt calls kit scripts by absolute path. T10 verifies the stage-2 capability checks.
- DEC-12 (operator): a separate LaunchAgent, not a `jobs.txt` line, because the cadence differs from kit-weekly. T9 amends ADR-0034 decision 9. Rejected: per-job intervals in kit-weekly.
- DEC-13 (operator): the installer takes `--label` (default `harvest-sweep`); the Mini installs `mini.harvest-sweep`.
- DEC-14 (operator): the sweep drafts no LAB_LOG entry.
- DEC-15 (operator): an explicit `distill` word in `/kit:wrap` wins over `wrap.distill = "harvest"` for that run.
- DEC-16 (operator): the devin adapter walks `parent_node_id` up from `sessions.main_chain_id` and falls back to all nodes by `node_id`; a fixture pins it.
- DEC-17 (operator): `codex` stays out of the default `sources` until an interactive rollout is verified. Superseded by DEC-26.
- DEC-18 (operator): with no cursor, the first run starts `schedule_hours` back; `--since` covers a manual backfill.
- DEC-19 (resolved upstream): attribution reads the worker-launch record from ops-toolkit #3631 (`d43a81b`). Its agent + cwd + window fallback is superseded by DEC-23.
- DEC-20 (operator): the sweep's gate-ledger rid is `harvest-sweep-<run-id>`. It is never pushed, so ship-gate never looks for it; each build keeps its own branch rid.
- DEC-21: the sweep entry has its own rc contract, and the launcher calls it directly, never through `harvest.sh`. Disabled, unmarked, and lock-held runs exit 0 without calling the bridge. Extended by DEC-45.
- DEC-22: rollout order is hand dry runs with no plist, then `enable = true`, then `install --apply`, then bridge and heartbeat. `install` keeps its refusal while disabled.
- DEC-23: attribution uses the brief-path match only. The agent + cwd + time-window fallback is dropped as a guess that can mis-attribute.
- DEC-24: the model never merges; a code step gates and merges. Superseded by DEC-38 wherever they conflict: stage 2 now has no GitHub or push capability at all, and stage 3 pushes and opens the PRs as well as merging them.
- DEC-25: patterns, evidence, and learnings are sanitized (slug charset, 200 printable characters, no backticks, angle brackets, `$`, or newlines) and rendered as quoted data.
- DEC-26: the Codex adapter is deferred to a later change; the adapter seam stays.
- DEC-27: harvest mode applies per host. The sweep is active only where `install --apply` wrote the `installed` marker, so a synced operator `kit.toml` cannot switch off distill or the hook on a host with no sweep.
- DEC-28: the extraction unit is the lead session with its subagents folded in. Trivial skips do not count against the cap, a scan cap bounds the stat work, stale sessions are marked done unread, and every report shows cursor lag. This replaces the earlier claim that any backlog drains over several runs. Stale is redefined by DEC-41.
- DEC-29: stage-1 idempotency rests on a raw output cache keyed `<id>@<last_activity>`, sightings merged by `max(count)` per (canonical, session), `patterns.jsonl` rewritten via tmp + `os.replace` under `patterns.lock`, and a fixed sweep fuzzy threshold with a stable canonical slug per cluster.
- DEC-30: per-session failures quarantine after `QUARANTINE_AFTER` (3) with a `STATE` row. The hwm advances only through a contiguous prefix of done sessions. Its auth rule is replaced by DEC-39.
- DEC-31: stage 2 resumes per candidate. A resume skips candidates with a `proposed.jsonl` entry for the run, the process group is spawned with `start_new_session` and killed with `os.killpg` at the timeout, a manifest fails after 2 resumes, and the lint loop stops at 3 passes.
- DEC-32: cost bounds beyond the caps: delta extraction on re-touch, a spawn threshold, `--max-turns`, pruning by age, and a re-propose rule for `REPORTED` entries only. The learnings threshold is refined by DEC-42.
- DEC-33: the `[harvest]` table is cut to `enable`, `schedule_hours`, `sources`, `max_sessions_per_run`, `max_builds_per_run`, `build_repos`, `distill_timeout_minutes`, and `hook_when_sweep_on`. Other tuning is env-overridable constants. Build lanes come from `wrap.build_lanes`. `--source` and the half-interval skip are cut.
- DEC-34: `install` renders the stage-2 settings file with `env.CLAUDE_PLUGIN_ROOT` set to the kit path. Reason: `hooks/ship-gate.sh` resolves its libs from `CLAUDE_PLUGIN_ROOT` and falls back to `$HOME/.claude/dwarves-kit` (lines 80, 85, 193, 270), and exits 0 when `gate-ledger.sh` is missing there (line 271). Setting it pins the hooks and stage 3's ship-gate call to the kit checkout the sweep runs from. The earlier reason (line 61, fail-open on an empty root) was wrong: line 61 concerns the git root.
- DEC-35: wrap's distill half is extracted into `docs/patterns/distill-build-and-land.md` so wrap and the sweep cite one text; the contract table lists every sweep substitution.
- DEC-36: manifest learnings are every queued row across the sweep ledgers, repo ledgers are read under their own `.lock`, and the first run carries hook-era queued rows into the sweep ledgers.
- DEC-37: `report-lint.sh` gets its own `sweep_report` flag; reusing `follow_report` would drop the Seam rule.
- DEC-38 (operator): the stage-2 model session has no GitHub or push capability. Its env unsets `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, and `SSH_AUTH_SOCK`, points `GH_CONFIG_DIR` at an empty dir, and clears the git credential helper. It builds and commits only in worktrees the code helper created with `wrap start`, each with a per-worktree push URL of `no-push` that the helper reads back. Its `proposed.jsonl` entries are advisory. Stage 3 code holds the token and iterates only the run's own worktree record. It computes the real diff, applies the denylist and a fixed-text `lane-classify --files`, runs ship-gate, and pushes. It opens the PR itself (DRAFT for a full lane or a denylist hit), waits for checks, and merges only a non-draft PR it opened this run, through `wrap merge --apply --pr`. A PR merged in a build repo during the run window by anything else is an `INCIDENT`. Branch protection on each build repo's default branch is an install prerequisite. The settings denies stay as defense in depth, not as the guarantee.
- DEC-39 (operator): every extractor failure increments `fail{id}`, including on the stop path. A failure counts as auth-shaped only when a second session also fails in the same run or a fixed probe call fails. A bad oldest session is therefore quarantined on its third run instead of stopping every run.
- DEC-40: the push URL is per-worktree config (`extensions.worktreeConfig`, enabled once per build repo by `install`), because `git remote set-url --push` in a worktree writes the shared config and would disable push for the main checkout and every other session.
- DEC-41: stale is measured from `last_success`, not from now, so an auth outage does not turn its own backlog stale. Any stale count raises a `STATE` row.
- DEC-42: the learnings spawn threshold counts only learnings added since `last_spawn`, and learning-only spawns pause while `seam.json` says the configured seam did not resolve (until the value changes or 24h pass). If T10's seam check fails, learnings stay queued in the sweep ledgers and the operator flushes them by hand.
- DEC-43: subagent messages interleave with the lead by entry timestamp; the lead keeps a fixed 60% of the character budget; the delta key is `last_ts`, which stays valid on resume and when a subagent file appears later.
- DEC-44: the extractor runs with its cwd under the harvest state dir, so the self-harvest drop covers its own transcripts.
- DEC-45: rc 4 is a stage-3 `gh` or `git` failure, and rc 5 is a source unreadable for `SOURCE_FAIL_RUNS` consecutive runs; the lowest non-zero code wins when several apply. An unreadable source is a `STATE` row every run.
- DEC-46: the launcher env contract is `GH_TOKEN` from Connect or the Keychain cache, git over HTTPS through `gh auth git-credential`, `IdentityAgent=none`, and never the 1Password ssh agent. T11 proves a real push under launchd.
- DEC-47: `install --uninstall` removes only what the installer rendered (plist, settings, marker) and leaves every piece of sweep state in place, printing what remains, so a re-install resumes and nothing queued is lost.
- DEC-48: stage 3 calls `hooks/ship-gate.sh` with a synthesized push payload before each push, because a push from code never passes through the PreToolUse hook. A block leaves the item `REPORTED` with the gate's reason.
- DEC-49: the path denylist is `hooks/`, `.github/`, `.githooks/`, `.claude/`, `bin/wrap`, and files named `settings.json`, `settings.local.json`, `hooks.json`, `kit.toml`, `.kit.toml`, `CODEOWNERS`, `CLAUDE.md`, `AGENTS.md`, `commands/wrap.md`, `docs/patterns/distill-build-and-land.md`, `harvest-sweep-prompt.md`, and `harvest-sweep-settings*`. A hit forces DRAFT.

## Open questions

(none; design questions were resolved at approval, in the design critique, and in validation round 1, see DEC-11 to DEC-49)
