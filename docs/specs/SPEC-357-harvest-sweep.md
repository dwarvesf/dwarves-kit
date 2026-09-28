# Spec: harvest sweep, a scheduled multi-agent distill job

Generated: 2026-09-29
Status: APPROVED (operator, kit:spec step 4; validation pending)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-357-harvest-sweep.md`
References: `hooks/harvest.py` (the extractor seam, the locked dedup-and-append in `_harvest_payload`, the recursion note in its docstring, `_run_harvest_locked` single-flight), `commands/wrap.md` (the distill half: pre-step-0 scan, step 7b precedent + lane + build, step 7c, step 10 landing and full-lane draft rules), `lib/sync/deploy/macos/` (a kit-owned launcher + plist template + installer + consumer bridge, the shape to copy), `lib/session/intel/bin/session-intel` (`repeat_detect`, a cross-session count over transcripts), `lib/session/parse_transcript.py` (the shared Claude JSONL line parser).

## Problem

Distill runs at the end of `/kit:wrap`, inside the session it distills. Three things go wrong there.

1. Context. By step 7b the session has spent its context on scans and merges. The pre-step-0 scan exists only because a late scan found nothing.
2. Scope. Wrap sees one Claude session. It never sees Devin or Codex workers, and it never sees the same friction across sessions. A manual review of 32 Devin sessions today found most lessons already captured. The rest were worker-ops patterns: a commit-format hook false block in 7 sessions, workers stalling while a background command runs, context blowouts on large briefs. No single session showed any of them as a pattern.
3. Cost placement. The per-session harvest hook (PreCompact, SessionEnd) spends a Haiku call per session, and wrap spends the operator's close-out minutes on distill.

The operator asked for a job that runs every ~6 hours, distills every session since the last run across agents, and does the improve and learn work. `/kit:wrap` then lands only.

## Solution

### Approaches considered

1. **Enhance `hooks/harvest.py` with a `--sweep` verb, plus a launchd launcher (chosen).** Stage 1 is deterministic Python: adapters, cursor, one Haiku extraction per session, pattern counting. Stage 2 spawns one headless Claude session that runs wrap's distill-half machinery on the stage-1 manifest. Tradeoff: harvest.py grows. The adapters go in a co-located module so the hook file stays readable.
2. **A new sibling tool (`lib/sweep/`).** Rejected. It would duplicate the extractor seam, the ledger lock, slug dedup, and the recursion guard, which is the fragment step 7b exists to prevent.
3. **One spawned session per run with no stage 1 (the model reads raw transcripts itself, like `session-audit`).** Rejected. Cursor and idempotency would live in model behavior, not code. Quota would scale with transcript size, and nothing counts patterns deterministically.

### Chosen approach + why

Approach 1. Code owns everything that must be exact (which sessions, how many, what was seen before, when a pattern crossed its threshold). The model owns only judgment (what is a learning, what to build) and reuses wrap's existing rules for that. Approach 2 traded away reuse. Approach 3 traded away crash safety and a quota bound.

### Extensibility & boundaries

- Load-bearing dimension: the number of agents. A new agent is one adapter function in `hooks/harvest_sources.py` plus one word in `harvest.sources`. Nothing else changes.
- Second dimension: session volume. `max_sessions_per_run` and `max_chars` bound stage 1. The cursor carries the rest to the next run, so a backlog drains over several runs instead of one large one.
- Units: adapter (source to normalized transcript), cursor (which sessions are new), extractor (transcript to learnings + pattern sightings), stager (dedup + append, shared with the hook), aggregator (sightings to candidates), distill session (candidates to builds and flushes), launcher (schedule, lock, heartbeat). Each has one input and one output shape below.

## Picture

```
  launchd (StartInterval = schedule_hours)
        |
        v
  deploy/macos/harvest-sweep/harvest-sweep   (launcher, #!/bin/bash, no .sh)
        |  reads [harvest] enable (root-only); off => log + exit 0
        v
  hooks/harvest.sh --sweep  -->  harvest.py sweep            [single-flight lock]
        |
        |  STAGE 1 (deterministic, Haiku per session)
        |    cursor.json --> adapters: claude | devin | codex --> normalized transcripts
        |    (optional) ~/.local/state/worker-launch/launches.jsonl --> lead attribution
        |    per session: extractor --> learnings  --> _stage_candidates (shared w/ hook)
        |                           --> sightings  --> patterns.jsonl
        |    aggregate sightings (occurrences >= min_pattern_count) --> manifest.json
        |    cursor advances per session, only after its writes landed
        |
        |  nothing new, or empty manifest --> no spawn
        v
  STAGE 2: claude -p --setting-sources project --settings <sweep-settings.json>
        |    cwd = kit state run dir (never a checkout), env HARVEST_SWEEP_CHILD=1
        |    runs wrap distill half on the manifest:
        |      precedent find --> lane-classify --> wrap start (worktree)
        |        tiny/normal in build_lanes --> build, verify, PR, wrap merge --apply --pr
        |        full                       --> spec + validate + build, DRAFT PR, REVIEW
        |      learnings --> wrap.after seam (flush) and step 7c notes, via worktrees
        v
  report.md (step 9 grammar) --> report-lint.sh --> gate-ledger record
        |
        v
  bridge ~/.config/harvest-sweep/bridge <rc> <report>  --> vps-mon heartbeat (Mini)

  /kit:wrap with wrap.distill = "harvest": landing half only;
  Built/Seam = SKIPPED: distill runs in the harvest sweep
  harvest.sh hook modes: sweep enabled and hook_when_sweep_on = false => exit 0
```

## Design

Design-bearing: yes (new scheduled component, new persisted state, a config table that authorizes writes, a spawned unattended session).

### Approaches considered + chosen

See `## Solution`.

### Diagram

See `## Picture` (component view). Cursor lifecycle per source:

```
  no cursor --> hwm = now - schedule_hours (first run, no backfill)
      |
      v
  select: last_activity >= hwm AND last_activity <= now - quiet_minutes
          AND (id, last_activity) not in done{}
          order by last_activity asc, take max_sessions_per_run
      |
      v  per session, in order
  extract ok? --no--> stop the run, cursor untouched for this and later sessions
      | yes
      v
  stage learnings + append sightings (both idempotent)
      |
      v
  done{id: last_activity} += session; hwm = its last_activity; prune done{} < hwm
  write cursor.json atomically (tmp + os.replace)
```

### ADR link(s)

No new ADR exists. Two decisions are lasting and need one at ship:

- A second kit LaunchAgent beside `kit-weekly`. ADR-0034 decision 9 chose ONE kit scheduler and rejected a plist per job. This spec deviates because the cadence differs (every 6h against a fixed weekly slot). T6 amends ADR-0034 to record the exception (DEC-12).
- `wrap.distill` becomes a three-value knob and the distill half moves out of wrap when set to `harvest`.

### Boundaries & failure modes

The sweep reads transcripts outside any repo and writes into repos only through worktrees it creates. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**Normalized transcript** (adapter output, one per session):

```
{"source": "claude|devin|codex", "session_id": str, "lead_session_id": str|null,
 "cwd": str, "started": epoch_s, "last_activity": epoch_s,
 "messages": [{"role": "user|assistant|tool", "text": str}]}
```

`render(t, max_chars)` joins messages as `<role>: <text>` lines and keeps the most recent `max_chars`, the same tail rule `transcript_text` uses today.

**Adapters** (`hooks/harvest_sources.py`, stdlib only; roots overridable by env for tests: `HARVEST_SWEEP_CLAUDE_ROOT`, `HARVEST_SWEEP_DEVIN_DB`, `HARVEST_SWEEP_CODEX_ROOT`):

| Source | Session unit | last_activity | Keep | Drop |
|---|---|---|---|---|
| claude | `~/.claude/projects/<slug>/<id>.jsonl`; each `<id>/subagents/agent-*.jsonl` is its own session with `lead_session_id = <id>` | file mtime | `type` user/assistant, `text` blocks; `tool_use` as `tool: <name> <input, 200 chars>` | everything else. Reuses `parse_transcript.iter_entries`. |
| devin | row of `sessions` in `~/.local/share/devin/cli/sessions.db`, opened read-only (`mode=ro` URI) | `sessions.last_activity_at` (epoch seconds) | `message_nodes.chat_message` JSON roles user, assistant, tool: `content` plus `tool_calls` names | role `system` (injected rules). Chain: walk `parent_node_id` up from `sessions.main_chain_id`; fall back to all nodes by `node_id` when null; a fixture pins the choice (DEC-16). |
| codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, id from the `session_meta` line | file mtime | `response_item` with `payload.type == "message"`, roles user and assistant, `input_text`/`output_text` blocks | role `developer`; user blocks that open with `<` (tag-wrapped injected context) or `# AGENTS.md instructions`; `reasoning`, `event_msg`, `turn_context`, `world_state`, token records. Verified against one local `codex exec` rollout (cli 0.156.1) only, so `codex` stays out of the default `sources` until T7 checks an interactive rollout (DEC-17). |

A session with fewer than `min_messages` kept messages (user plus assistant, tool excluded) is marked done and skipped with no extractor call.

**Launch record** (optional input, shipped in ops-toolkit #3631, `d43a81b`). `tools/worker-launch` appends one JSON object per launch to `~/.local/state/worker-launch/launches.jsonl` (the `harvest.launch_record` default):

```
{"ts": "<UTC ISO>", "agent": str, "mode": "tui|print", "handle": str|null, "title": str,
 "brief": path, "brief_copy": path, "cwd": path, "lead_session": str|null}
```

Attribution applies to a worker session with no `lead_session_id` of its own (claude subagents already carry one). A record matches when its `agent` equals the session's source and its `brief` or `brief_copy` path appears in the session's first kept user message; the session then takes the record's `lead_session`. When several records match, the one whose `ts` is nearest the session's `started` wins. When no record matches this way, the fallback is a record with the same `agent` and `cwd` whose `ts` falls within 120s of `started`. No file, a malformed line, or no match leaves `lead_session_id` null. The sweep never fails on this input.

**Sweep extractor prompt** (`PROMPT_SWEEP` in harvest.py, same `HARVEST_EXTRACTOR` seam). It returns one JSON object:

```
{"learnings": [<the existing hook element shape: item, kind, home, why>],
 "sightings": [{"pattern": "<kebab slug>", "kind": "repeat|friction|failure|ask",
                "count": <int, occurrences in this session>, "evidence": "<one line>"}]}
```

The prompt carries the 50 most recent known pattern slugs and tells the model to reuse one when it fits, so the same friction keeps one name across sessions. `kind: ask` is an enhancement the operator asked for and the session deferred (wrap step 7b's third candidate kind).

**Extractor failure is not an empty result.** `run_extractor` gains a sweep-only return of `(ok, stdout)`: `ok` is false on a non-zero exit, a timeout, or output with no parseable JSON. The hook path keeps its current behavior.

**Shared stager.** The locked read-known, dedup, and append block in `_harvest_payload` moves into `_stage_candidates(ledger, glossaries, candidates) -> fresh_rows`. The hook calls it with the session's ledger as today. The sweep calls it with the sweep ledger (below). Both use the same slugify, fuzzy threshold, glossary dedup, and `.lock` file, so the two modes cannot double-stage the same slug into one ledger.

**Stage-1 outputs** (under `$HARVEST_STATE_DIR/sweep/`, default `~/.claude/dwarves-kit/state/harvest/sweep/`):

| File | Shape | Writer | Idempotency key |
|---|---|---|---|
| `cursor.json` | `{"<source>": {"hwm": epoch_s, "done": {"<id>": last_activity}}}` | stage 1, atomic replace after each session | (source, id, last_activity) |
| `ledger/<repo-slug>.md` | the learned-ledger table, `status: queued` | `_stage_candidates` | slug (exact + fuzzy + glossary) |
| `patterns.jsonl` | `{"pattern", "kind", "source", "session_id", "lead_session_id", "cwd", "count", "evidence", "ts"}` | stage 1 | (pattern, session_id): a re-read session replaces its own line, never adds one |
| `proposed.jsonl` | `{"pattern", "run_id", "outcome"}` | stage 2 | pattern: never proposed twice |
| `runs/<run-id>/manifest.json` | `{"run_id", "status": "pending|done", "sessions": [...], "learnings": [...], "candidates": [{"pattern", "kind", "occurrences", "sessions", "leads", "evidence": [...]}]}` | stage 1; stage 2 flips status | run_id |
| `runs/<run-id>/report.md` | wrap step 9 grammar under `## Harvest sweep: <run-id>` | stage 2 | run_id |

`<repo-slug>` comes from the session cwd's main checkout (`git rev-parse --git-common-dir`, trailing `/.git` stripped, slugged). A cwd outside any repo goes to `ledger/_no-repo.md`. The sweep reads a repo's `_meta/learned-ledger.md` and glossaries for dedup and never writes them.

**Aggregation.** Over sightings newer than `pattern_window_days`, a pattern is a candidate when the sum of `count` across sessions is at least `min_pattern_count`, and it is absent from `proposed.jsonl`. `kind: ask` qualifies at 1. Fuzzy slug merging reuses `HARVEST_FUZZY_THRESHOLD`. One sighting of count 1 never qualifies.

**Stage 2 spawn.** When the manifest has zero candidates and zero learnings, no session spawns and the run reports `NOTHING: no candidates`. Otherwise:

```
cd $HARVEST_STATE_DIR/sweep/runs/<run-id>
HARVEST_SWEEP_CHILD=1 claude -p "$(render hooks/harvest-sweep-prompt.md)" \
  --model <harvest.model> --setting-sources project \
  --settings <kit>/hooks/harvest-sweep-settings.json --permission-mode bypassPermissions
```

Never `--bare` (it skips keychain reads and breaks auth). `HARVEST_SWEEP_DISTILL_CMD` overrides the whole command for tests. harvest.py runs it with a `distill_timeout_minutes` timeout. `harvest-sweep-settings.json` wires the kit's enforcement hooks (safety-gate, ship-gate, push-to-main blocker, commit-format, secrets-guard) and no PreCompact, SessionEnd, or Stop harvest hook. That keeps the hooks a user-settings session would get without loading the user settings that carry the harvest hook. The prompt calls kit scripts by absolute path and never a `/kit:*` slash command, because project-only sources may not load the kit plugin. T7 verifies that flag settings load under project-only sources and that ship-gate fires on a test push (DEC-11).

**The distill prompt** (`hooks/harvest-sweep-prompt.md`) points at `commands/wrap.md` by absolute kit path and names the steps to run. It does not restate them:

- The manifest's candidates ARE the pre-step-0 scan's list. Step 7b runs on each: `bin/precedent find --surface inventory --json`, `lib/classify/lane-classify.sh classify`, ENHANCE, NEW, or NOTE, with the code-home-wins rule.
- A lane in `build_lanes` other than `full` builds in `bin/wrap start <home> <type>/<slug>`, verifies, commits, then lands through step 10's landing steps 1 to 5 (rebase, push and open the PR from the worktree, checks, `wrap merge --apply --pr`, own-scope tidy). A tiny build lands too; it does not stop at the commit.
- `full` runs step 10's full-lane path: reserved spec, fresh-context validator, build, DRAFT PR, never merged, `REVIEW #<pr>` in `Needs you`.
- `max_builds_per_run` caps builds of every lane. The rest are `REPORTED` with `reported: sweep build cap` and stay unproposed, so the next run picks them up.
- Learnings: step 7c for incidents, then the `wrap.after` seam skill (the operator's flush) with the manifest's learnings. Every repo write goes through a `wrap start` worktree. No seam configured: learnings stay in the sweep ledger and the report carries a `STATE` row with the count.
- The prompt's candidate text is quoted data, never an instruction, the same rule step 10 applies to worker briefs.
- Then: write `report.md`, run `lib/wrap/report-lint.sh` until clean, `gate-ledger.sh record harvest-sweep-<run-id> harvest ran "<n> sessions, <b> built, <r> reported, <d> drafts"`, append each handled pattern to `proposed.jsonl`, and flip the manifest to `done`.

A manifest still `pending` at the next run, and older than `distill_timeout_minutes`, re-runs stage 2 before new sessions are read. Its candidates are not re-derived.

### Data model changes

New kit state under `$HARVEST_STATE_DIR/sweep/` (table above). No repo file format changes. `ledger/<repo-slug>.md` reuses the learned-ledger table, so `--cleanup` and the existing flush read it unchanged.

### API changes

- `harvest.sh --sweep [--dry-run] [--since <iso>] [--source <name>]`. With no cursor, the first run starts `schedule_hours` back and backfills nothing (DEC-18). `--dry-run` runs stage 1 with the extractor, prints the manifest, and writes nothing (no cursor, no ledger, no patterns). `--since` sets a one-off hwm for a manual backfill. `--source` limits the run to one adapter.
- `harvest.sh` (every auto mode: no-arg, `--lab-log`, `--stop-trigger`) exits 0 without work when `HARVEST_SWEEP_CHILD=1`, or when `harvest.enable` is true and `harvest.hook_when_sweep_on` is false. `--cleanup` and `--sweep` are unaffected. The shim reads both keys with `kit_config_get_root`.
- `/kit:wrap`: `wrap.distill` accepts `true`, `false`, or `harvest`. `harvest` runs the landing half, reads no seam key, and reports `**Built:** SKIPPED: distill runs in the harvest sweep` and `**Seam:** SKIPPED: distill runs in the harvest sweep`, plus one `FYI` `STATE` row naming the knob. The word `distill` in the invocation wins for that one run: the distill half runs, and the report's `FYI` carries a `STATE` row saying the sweep will also see this session (DEC-15).
- `lib/wrap/report-lint.sh`: a report whose first `## ` line opens `## Harvest sweep:` gets the follow-through report's full-lane rule (a `lane=full` item may close `verified: ..., #<pr> DRAFT` when a `REVIEW #<pr>` item names the same PR). It still owes `**Seam:**`. `SKIPPED: distill runs in the harvest sweep` passes on both lines. It passes today; a fixture pins it.

### UI changes

None.

### Infrastructure changes

`kit.toml` gains a `[harvest]` table. Every key resolves with `kit_config_get_root` (operator or kit-root `kit.toml`, never a project `.kit.toml`), because the sweep writes to repos.

```toml
[harvest]
enable = false               # the switch. false = launcher logs and exits 0; the hook runs as today
schedule_hours = 6           # launchd StartInterval, rendered at install; launcher also skips a
                             # run started less than schedule_hours/2 after the last one
sources = "claude"           # space-separated: claude devin codex
min_messages = 6             # kept user+assistant messages below which a session is trivial
min_messages_devin = ""      # optional per-source override (min_messages_<source>); empty = min_messages
max_sessions_per_run = 20    # stage-1 bound; the cursor carries the rest
max_chars = 12000            # transcript tail per extractor call
quiet_minutes = 30           # a session idle less than this is live and waits for the next run
min_pattern_count = 3        # occurrences before a sighting becomes a candidate
pattern_window_days = 14     # sightings older than this stop counting
build_lanes = ""             # empty = inherit wrap.build_lanes; full always goes to a DRAFT PR
max_builds_per_run = 3       # builds of every lane per run; the rest are REPORTED
model = "sonnet"             # stage-2 session model; stage 1 stays on the HARVEST_EXTRACTOR default
distill_timeout_minutes = 90 # stage-2 wall clock
launch_record = "~/.local/state/worker-launch/launches.jsonl"  # optional; missing file = no attribution
hook_when_sweep_on = false   # true = the per-session hook keeps running while the sweep is on
```

Launchd deploy under `deploy/macos/harvest-sweep/`, copying `lib/sync/deploy/macos/`:

- `harvest-sweep`: the launcher. `#!/bin/bash`, no `.sh`, launchd-safe PATH, optional `~/.config/harvest-sweep/env`, re-reads `harvest.enable` each run, logs start and end with rc, runs `hooks/harvest.sh --sweep`, then runs `~/.config/harvest-sweep/bridge <rc> <report-path>` best-effort.
- `harvest-sweep.plist.tmpl`: `ProgramArguments[0]` is the launcher's absolute path. Rendered `__LABEL__`, `__KIT__`, `__HOME__`, `__INTERVAL__`.
- `install [--label L] [--apply]`: dry run by default, `--label` defaults to `harvest-sweep`. The Mini installs `mini.harvest-sweep`, a prefix already in vps-mon's `OWNED_PREFIXES` (DEC-13). It refuses when `harvest.enable` is not true, the same gate board-sync's installer applies.

Monitoring (consumer side, ops-toolkit): the Mini's bridge pings the vps-mon heartbeat on rc 0. The heartbeat URL lives in `/etc/vps-mon/harvest-sweep-heartbeat-url`, `hb_id` is the discovered label, the interval is `schedule_hours` and the grace is 2x. The catalog link follows `job-monitoring-onboarding`. The kit ships no endpoint or secret.

## Task Breakdown

### Phase 1: Foundation

- [ ] T1: factor `_stage_candidates` out of `_harvest_payload`; add the `(ok, stdout)` extractor variant for sweep use. AC: every existing harvest test in `tests/test-hooks.sh` passes unchanged.
- [ ] T2: `hooks/harvest_sources.py` with the claude, devin, and codex adapters, the min-messages skip, and launch-record attribution (brief match first, agent + cwd + 120s window as fallback); fixtures under `tests/fixtures/harvest-sweep/` (a claude project dir with one subagent file, a devin db built by a fixture script with a branched message forest, the codex rollout shape, a `launches.jsonl`). AC: each adapter yields the normalized shape, drops the listed roles and blocks, and attributes the subagent to its lead; the devin fixture pins the main-chain walk.
- [ ] T3: `harvest.py sweep` stage 1: cursor, selection, extraction, sweep ledger, `patterns.jsonl`, aggregation, manifest, `--dry-run`, `--since`, `--source`, single-flight lock. AC: the cursor tests in `## Test plan` pass.

### Phase 2: Core

- [ ] T4: stage 2: `hooks/harvest-sweep-prompt.md`, `hooks/harvest-sweep-settings.json`, the spawn with `HARVEST_SWEEP_CHILD=1`, the timeout, the pending-manifest resume, the skip when nothing is new. AC: a stub distill command sees `--setting-sources project` and `--settings`, never `--bare`, and is not invoked on an empty manifest.
- [ ] T5: `[harvest]` table in `kit.toml`; the `harvest.sh` gate; `deploy/macos/harvest-sweep/` launcher, template, and installer. AC: gate tests pass; `install` dry run renders a plist whose `ProgramArguments[0]` is the launcher path.
- [ ] T6: `commands/wrap.md` `distill = "harvest"` (and the explicit `distill` word winning for one run); `lib/wrap/report-lint.sh` sweep heading; MANUAL.md and the `[wrap]` comment in `kit.toml`; an ADR-0034 amendment recording the second LaunchAgent. AC: lint fixtures pass, test-meta asserts the wrap string.

### Phase 3: Rollout

- [ ] T7: Mini, consumer side in ops-toolkit: bridge script, heartbeat provision, catalog link, `install --label mini.harvest-sweep --apply` with `enable = false`. Verify that a `--settings` file loads under `--setting-sources project` and that ship-gate refuses a test push from a spawned session. Check one interactive Codex rollout against the adapter before adding `codex` to `sources`. Then three manual `--sweep --dry-run` runs; compare manifests against a hand review of the same sessions. AC: vps-mon shows the job monitored, not gap.
- [ ] T8: set `enable = true` and `wrap.distill = "harvest"` in the Mini operator `kit.toml` after the dry runs agree. AC: two consecutive scheduled runs report clean lint, a gate-ledger line, and a heartbeat ping.

## After state

- [ ] `hooks/harvest.sh --sweep --dry-run` prints a manifest over new claude, devin, and codex sessions. (Today: no sweep verb.)
- [ ] A second `--sweep` with no new sessions spawns nothing, calls no extractor, and changes no file under `state/harvest/sweep/` except the launcher log.
- [ ] With `harvest.enable = true` and `hook_when_sweep_on = false`, a PreCompact or SessionEnd hook fire spawns no harvest child. (Today: every fire spawns one.)
- [ ] `/kit:wrap` with `wrap.distill = "harvest"` prints `**Built:** SKIPPED: distill runs in the harvest sweep` and the lint passes.
- [ ] `launchctl print gui/$(id -u)/mini.harvest-sweep` on the Mini shows the job, and vps-mon lists it monitored.

## Acceptance Criteria (global)

- [ ] AC1: adapters. Each fixture source yields the normalized shape. Devin `system` rows, Codex `developer` rows and injected user blocks are absent from `messages`. A claude subagent session carries its lead's id. A devin worker whose first user message names a record's `brief` takes that record's `lead_session`; with no brief match, the agent + cwd + 120s fallback applies; with neither, it stays null.
- [ ] AC2: idempotency. Running `--sweep` twice over the same fixtures leaves the sweep ledger, `patterns.jsonl`, and `proposed.jsonl` byte-identical after the second run.
- [ ] AC3: crash safety. Killing the sweep after a session's staging and before its cursor write, then re-running, stages no duplicate row and double-counts no sighting. No session between the old and new hwm is skipped.
- [ ] AC4: extractor failure. A stub extractor that exits 1 leaves `cursor.json` unchanged and the run exits non-zero, so the bridge gets a non-zero rc.
- [ ] AC5: threshold. Two sessions each sighting a pattern once produce no candidate. A third produces one. One session sighting it with count 3 produces one. An `ask` produces one at count 1.
- [ ] AC6: bounds. With 25 new fixture sessions and `max_sessions_per_run = 20`, one run extracts 20 and the next extracts 5. Each extractor prompt is at most `max_chars` of transcript plus the fixed prompt.
- [ ] AC7: recursion and quota guard. The stub distill command's argv contains `--setting-sources project` and never `--bare`. `HARVEST_SWEEP_CHILD=1 harvest.sh` in any auto mode spawns nothing.
- [ ] AC8: hook switch. `enable = true, hook_when_sweep_on = false` makes the no-arg, `--lab-log`, and `--stop-trigger` modes exit 0 without a child. `enable = false` leaves today's behavior. A project `.kit.toml` setting either key changes nothing.
- [ ] AC9: wrap and lint. A `## Harvest sweep:` report with a full-lane `#<pr> DRAFT` item and a matching `REVIEW #<pr>` passes; the same report without the REVIEW item fails. A wrap report with both `SKIPPED: distill runs in the harvest sweep` lines passes.
- [ ] AC10: the sweep never writes a repo's main checkout. After a fixture run, `git status --porcelain` in each fixture repo's main checkout is empty.
- [ ] AC11: `bash tests/test-hooks.sh && bash tests/test-meta.sh` pass.

## Test plan

Outline. `/kit:test-plan` expands it into the coverage matrix.

| Area | Case | Kind |
|---|---|---|
| adapters | one fixture per source; role and injected-block drops; subagent lead; devin main-chain walk and null fallback; trivial-session skip; unreadable db or file skips the source with a log line | unit |
| attribution | brief match; fallback window match; nearest-ts tie; malformed line; missing file | unit |
| cursor | first run window; second run empty; resumed session (newer last_activity) re-read and replacing its own sightings; tie on last_activity; crash between staging and cursor write | unit |
| extractor | failure stops the run with cursor untouched; non-JSON output counts as failure; empty arrays count as success | unit |
| aggregation | 2 vs 3 occurrences; in-session count; `ask`; window expiry; already proposed | unit |
| stage 2 | stub distill argv; no spawn on empty manifest; pending manifest resumes first; timeout marks the run failed | integration (stub) |
| hook gate | the three auto modes under each switch value; child marker; project toml ignored | integration |
| lint | sweep DRAFT with and without REVIEW; wrap harvest SKIPPED lines | fixture |
| launcher | disabled run exits 0 and logs; bridge gets the rc; a second run inside schedule_hours/2 skips | integration |
| live | three Mini `--dry-run` manifests against a hand review | UAT (T7) |

**Negative control.** After T3 is committed, run `bash lib/gate/negctl.sh <root> "bash tests/test-hooks.sh" "<mutate>"` twice. The first mutation moves the cursor write ahead of `_stage_candidates`; AC3's test must go red. The second makes the sweep treat a failed extractor as an empty result; AC4's test must go red.

## Verification

```
bash tests/test-hooks.sh && bash tests/test-meta.sh
bash lib/config/kit-config.sh selftest
bash lib/wrap/report-lint.sh tests/fixtures/harvest-sweep/report-draft-ok.md
HARVEST_EXTRACTOR=<stub> HARVEST_SWEEP_DISTILL_CMD=<stub> HARVEST_STATE_DIR=$(mktemp -d) bash hooks/harvest.sh --sweep --dry-run
```

Rollout proof (T7, T8): the three dry-run manifests, `launchctl print` for the label, the vps-mon monitored state, and two scheduled run reports. They go into `docs/verification/harvest-sweep.md`.

## Edge Cases

1. A live session idles past `quiet_minutes` and then resumes. It is read, then re-read later with a newer `last_activity`. Its sightings are replaced by (pattern, session_id), and its learnings dedup by slug.
2. Claude writes a transcript mid-read. The parser skips a malformed trailing line; the session's mtime moves past the value recorded in `done{}`, so the next run re-reads it.
3. The Devin db is locked by a running Devin. The read-only URI read retries once, then skips the source for this run with a log line; the cursor for devin does not move.
4. A Codex rollout has no `session_meta` line. The file name's trailing uuid is the id.
5. Two sessions share a cwd in a repo with no `_meta/learned-ledger.md`. The sweep ledger for that repo slug is created; nothing is created in the repo.
6. A pattern slug drifts across sessions (`commit-hook-false-block` vs `commit-format-false-block`). The known-slug list in the prompt is the first guard, and the fuzzy threshold is the second. A miss splits the count and delays the candidate. It never builds a single sighting.
7. A candidate's home repo has foreign activity (step 0 signals). The build still runs in its own worktree. A merge that step 0 would stop stays `OPEN`, exactly as wrap step 10 does.
8. The system clock jumps backward. The hwm is compared against source timestamps, not the wall clock, so no session is lost; `quiet_minutes` may delay one run.
9. The operator runs `/kit:wrap distill` while the sweep is on. Both distill the same session. Dedup covers learnings. Wrap's builds and the sweep's builds meet at precedent: the second finds the first's branch or merge as a hit.
10. `sources` names an agent with no adapter. That word logs `unknown source` and is skipped; the others run.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| OAuth expired or keychain locked under launchd | extractor `ok` false on the first session; rc non-zero; no heartbeat ping | cursor untouched; vps-mon alerts on the missed ping; fix auth per the `launchd-headless-job` recipe; the next run catches up within `max_sessions_per_run` |
| Recursion storm (a spawned session re-fires harvest) | many `harvest` children in `ps`; state dir payload files pile up | three guards: `--setting-sources project`, the sweep settings file wires no harvest hook, and `HARVEST_SWEEP_CHILD=1` short-circuits `harvest.sh` |
| Quota burn | Max-plan usage spikes on the 6h cadence | `enable = false`; `max_sessions_per_run`, `max_chars`, `max_builds_per_run`; no spawn when nothing is new; `schedule_hours` |
| Stage 2 crash or timeout | manifest stays `pending`; no gate-ledger line; rc non-zero | the next run resumes the pending manifest first; worktrees left behind show in the next wrap's `Left alone`, and `wrap apply` removes none without a merge proof |
| Bad unattended build | a PR merged by the sweep breaks something | only lanes in `build_lanes` merge, and only green through `wrap merge --apply --pr` with the tree verify; full lane is always a DRAFT; revert is one PR |
| Writes into a live checkout | foreign dirty files in a main checkout | the sweep's only repo writes are `wrap start` worktrees; AC10 pins it |
| Transcript data to a new provider | Devin or Codex transcripts reach Anthropic Haiku | `sources` defaults to `claude`; adding devin or codex is an operator decision in the root-only config |
| Secret in a transcript reaches a prompt or ledger | secret-guard hook in stage 2; a credential-shaped string in the sweep ledger | same exposure class as today's hook; the extractor is told to emit slugs and one-line reasons only; secrets-guard runs in the stage-2 settings |
| Pattern never reaches the threshold because of slug drift | a hand review finds a repeated issue with no candidate | T7 compares dry-run manifests against a hand review before enable; tune `HARVEST_FUZZY_THRESHOLD` or `min_pattern_count` |

## Out of Scope

- Changing wrap's landing half. Steps 0 to 6, 8, and 9 stay as they are.
- Replacing `session-audit` (weekly deep audit, Claude only, staging output) or `session-intel repeat` (deterministic bash 3-grams). They stay on kit-weekly. The sweep may reuse `repeat_detect` later; this spec does not.
- `bin/reflect`, which proposes from gate and run ledgers, not transcripts.
- Adapters beyond claude, devin, and codex (Gemini, opencode, omp). Each is a later one-function change.
- Changing the launch record. ops-toolkit #3631 owns its format; the sweep only reads it.
- LAB_LOG drafts from the sweep. The hook's `--lab-log` draft stops with the hook (DEC-3), and wrap step 6's activity line covers the session record (DEC-14).
- Any board row. The sweep follows wrap: a candidate not built is reported, never filed.
- Linux or systemd scheduling. The kit's scheduled jobs are macOS LaunchAgents today.
- Auto-enabling. `enable` ships false.

## Decision Log

- DEC-1 (operator): autonomy follows wrap's lane rules. Tiny and normal candidates build in worktrees and merge only when green through `wrap merge --apply --pr`. Full-lane candidates open as DRAFT PRs and go to the operator as `REVIEW`. Learnings flush through step 7c and the learning-ledger route. The sweep reuses wrap's distill-half machinery (precedent find, lane-classify, `wrap start`, step-10 landing) and does not reimplement it.
- DEC-2 (operator): the host is the Mac Mini via launchd, following the estate plist rules, with a vps-mon heartbeat before the job counts as done.
- DEC-3 (operator): the per-session PreCompact and SessionEnd harvest hook is off while the sweep is on, through one switch (`hook_when_sweep_on`), so nothing is staged twice or paid for twice.
- DEC-4: enhance `hooks/harvest.py` (verb `--sweep`, adapters in a co-located module) rather than a sibling tool. The shared stager keeps one dedup path.
- DEC-5: two stages. Code decides which sessions, counts, and thresholds; one model session per run decides what to build. Rejected: a model-only sweep (no deterministic cursor or bound).
- DEC-6: the sweep stages learnings into kit state, not a repo's `_meta/learned-ledger.md`, because that file sits in a main checkout that live sessions share.
- DEC-7: extractor failure stops the run with the cursor untouched. An empty result and a failed call must not look alike (the same third-state rule `report-lint.sh` enforces for `Built:`).
- DEC-8: a pattern needs `min_pattern_count` occurrences (in-session counts included, matching wrap step 7b's "three or more times" rule) before it is built. An operator `ask` needs one.
- DEC-9: every `[harvest]` key resolves root-only (`kit_config_get_root`), the same reason as wrap's autonomy knobs: it authorizes writes.
- DEC-10: `sources` defaults to `claude`. Sending another agent's transcripts to Haiku is a new data path and an explicit operator choice.
- DEC-11 (operator): stage 2 runs with a sweep settings file that wires only the enforcement hooks, and the prompt calls kit scripts by absolute path. T7 verifies ship-gate still fires.
- DEC-12 (operator): a separate LaunchAgent, not a `jobs.txt` line, because the cadence differs from kit-weekly. T6 amends ADR-0034 decision 9. Rejected: per-job intervals in kit-weekly.
- DEC-13 (operator): the installer takes `--label` (default `harvest-sweep`); the Mini installs `mini.harvest-sweep`.
- DEC-14 (operator): the sweep drafts no LAB_LOG entry.
- DEC-15 (operator): an explicit `distill` word in `/kit:wrap` wins over `wrap.distill = "harvest"` for that run.
- DEC-16 (operator): the devin adapter walks `parent_node_id` up from `sessions.main_chain_id` and falls back to all nodes by `node_id`; a fixture pins it.
- DEC-17 (operator): `codex` stays out of the default `sources` until an interactive rollout is verified.
- DEC-18 (operator): with no cursor, the first run starts `schedule_hours` back; `--since` covers a manual backfill.
- DEC-19 (resolved upstream): attribution reads the worker-launch record from ops-toolkit #3631 (`d43a81b`). A brief-path match comes first; agent + cwd + a 120s start window is only the fallback.
- DEC-20 (operator): the sweep's gate-ledger rid is `harvest-sweep-<run-id>`. It is never pushed, so ship-gate never looks for it; each build keeps its own branch rid.

## Open questions

(none; the ten design questions were resolved at approval, see DEC-11 to DEC-20)
