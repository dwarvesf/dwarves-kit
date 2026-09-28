# Spec: harvest sweep, phase 1 (scheduled multi-agent distill, report only)

Generated: 2026-09-29
Status: APPROVED (operator re-approved and phased after validation round 2; validation pending)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-357-harvest-sweep.md`
Phase 2: `docs/specs/SPEC-358-harvest-sweep-build.md` (build and merge from the sweep; DRAFT; entry condition: this phase runs clean on the Mini for a week)
References: `hooks/harvest.py` (the extractor seam, the locked dedup-and-append in `_harvest_payload`, the recursion note in its docstring, `_run_harvest_locked` single-flight, `--cleanup`), `commands/wrap.md` (the distill half: pre-step-0 scan, step 7b precedent + lane, step 9 report grammar), `lib/sync/deploy/macos/` (a kit-owned launcher + plist template + installer + consumer bridge, the shape to copy), `lib/session/parse_transcript.py` (the shared Claude JSONL line parser), `lib/classify/lane-classify.sh` and `bin/precedent` (both deterministic, no model call).

## Problem

Distill runs at the end of `/kit:wrap`, inside the session it distills. Three things go wrong there.

1. Context. By step 7b the session has spent its context on scans and merges. The pre-step-0 scan exists only because a late scan found nothing.
2. Scope. Wrap sees one Claude session. It never sees Devin workers, and it never sees the same friction across sessions. A manual review of 32 Devin sessions today found most lessons already captured. The rest were worker-ops patterns: a commit-format hook false block in 7 sessions, workers stalling while a background command runs, context blowouts on large briefs. No single session showed any of them as a pattern.
3. Cost placement. The per-session harvest hook (PreCompact, SessionEnd) spends a Haiku call per session, and wrap spends the operator's close-out minutes on distill.

The operator asked for a job that runs every ~6 hours, distills every session since the last run across agents, and does the improve and learn work. `/kit:wrap` then lands only.

**Phasing (DEC-50).** This spec is phase 1: the sweep reads, extracts, counts, stages learnings, and REPORTS candidates with their precedent result and lane. It builds nothing. Phase 1 spawns no model session beyond the per-session Haiku extractor, creates no worktree, pushes nothing, opens no PR, and merges nothing. Building and merging from the sweep is SPEC-358, which starts only after phase 1 has run clean on the Mini for a week.

## Solution

### Approaches considered

1. **Enhance the harvest tool with a sweep mode, plus a launchd launcher (chosen).** Deterministic Python: adapters, cursor, one Haiku extraction per lead session, pattern counting, precedent and lane per candidate, a report. The sweep lives in `hooks/harvest_sweep.py`, a module of the harvest tool that imports harvest.py's shared functions, so the hook file stays readable.
2. **A new sibling tool (`lib/sweep/`).** Rejected. It would duplicate the extractor seam, the ledger lock, slug dedup, and the recursion guard, which is the fragment step 7b exists to prevent.
3. **One spawned session per run with no deterministic stage (the model reads raw transcripts itself, like `session-audit`).** Rejected. Cursor and idempotency would live in model behavior, not code. Quota would scale with transcript size, and nothing counts patterns deterministically.

### Chosen approach + why

Approach 1. Code owns everything that must be exact: which sessions, how many, what was seen before, when a pattern crossed its threshold, and where each candidate would land. The model owns only extraction (what is a learning, what is a sighting). Approach 2 traded away reuse. Approach 3 traded away crash safety and a quota bound.

### Extensibility & boundaries

- Load-bearing dimension: session volume. Measured on the Mini over 24h: 46 top-level Claude transcripts and 237 subagent transcripts changed. Subagents fold into their lead, so the extraction unit is the lead session (46 a day, plus Devin sessions). The default cap is 20 extractions a run at 4 runs a day, 80 a day, so the measured load fits with about 40% headroom. A burst above 80 a day queues. Sessions older than `HARVEST_SWEEP_STALE_RUNS` x `schedule_hours` (default 24h) before the source's last successful run are marked done unread; any stale count raises a `STATE` row, and every report carries the cursor lag.
- Quota (DEC-55). At the caps a run makes at most 21 Haiku calls (20 extractions plus 1 probe), so 84 a day and about 2,520 a month. Each call sends at most `HARVEST_MAXCHARS` (12,000) characters of transcript plus about 1,500 characters of fixed prompt and known slugs: roughly 3,400 input tokens at 4 characters a token, so at most about 8.6M input tokens a month. Output is a small JSON object. `bin/precedent` and `lane-classify.sh` are local and cost no tokens. A run with nothing new makes no call.
- Second dimension: the number of agents. A new agent is one adapter function in `hooks/harvest_sweep.py` plus one word in `harvest.sources`. Codex is deferred on that seam (Out of Scope).
- Units: adapter (source to normalized transcript), cursor (which sessions are new), extractor (transcript to learnings + sightings), sanitizer, stager (dedup + append, shared with the hook), aggregator (sightings to candidates), annotator (candidate to precedent result + lane), reporter (run to report + rc), launcher (schedule, rc, heartbeat). Each has one input and one output shape below.

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
        |  cursor.json --> adapters: claude (subagents interleaved by ts) | devin
        |                  launches.jsonl --> lead attribution (brief-path match)
        |  per lead session: cached raw output, or Haiku extractor (cwd under the state dir)
        |      --> sanitize --> learnings --> _stage_candidates --> ledger/<repo-slug>.md
        |                   --> sightings --> patterns.jsonl
        |  aggregate (occurrences >= MIN_PATTERN_COUNT) --> candidates
        |  per candidate: bin/precedent find + lane-classify.sh  (local, no model)
        |      --> REPORTED, recorded in proposed.jsonl
        v
  runs/<id>/report.md (wrap step 9 grammar) --> report-lint.sh --> gate-ledger record
        |
        v
  bridge ~/.config/harvest-sweep/bridge <rc> <report path or "-">  --> vps-mon heartbeat

  learnings stay queued in the sweep ledgers --> flushed by the existing manual path
      (learning-ledger skill, or /kit:wrap distill with its wrap.after seam), which marks
      each routed row flushed:<home>; harvest.sh --cleanup archives flushed rows

  /kit:wrap on a host with the sweep marker and wrap.distill = "harvest": landing half only,
  Built/Seam = SKIPPED: distill runs in the harvest sweep
  harvest.sh auto modes: sweep active on this host and hook_when_sweep_on = false => exit 0
```

## Design

Design-bearing: yes (new scheduled component, new persisted state, a config table, a knob that moves distill out of wrap).

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
          (a quarantined id whose last_activity moved past its quarantine value is lifted)
  last_activity < stale_cutoff --> done{} unread, stale += 1
      stale_cutoff = max(last_success[source] - STALE_RUNS x schedule_hours, now - 30d)
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
  save raw output --> sanitize --> stage learnings --> merge sightings (max count)
      |
      v
  done{id} = {last_activity, last_ts}; hwm = last_activity of the longest done prefix
  prune done{} < hwm; write cursor.json atomically (tmp + os.replace)
```

A failing session is counted in `fail{id}` even when the run stops, so a bad session that is the oldest one gets quarantined on its third run instead of blocking every run.

### Distill-half contract (phase 1)

The sweep does part of wrap's distill half. It reads `commands/wrap.md` for nothing at run time; this table records which step it stands in for.

| wrap distill-half step | phase 1 sweep |
|---|---|
| pre-step-0 scan of the live session | the manifest's `candidates`, counted across sessions |
| step 7a DEBT marker (rid from the branch) | not done; the run record uses rid `harvest-sweep-<run-id>` |
| step 7b precedent find + lane-classify | done by code per candidate, with the pattern's slug and evidence as the query |
| step 7b build | not done; every candidate is `REPORTED` (phase 2, SPEC-358) |
| step 7c incident notes | not done; they stay with `/kit:wrap distill` |
| `wrap.before` and `wrap.after` seams | not run; the report's `**Seam:**` line says so |
| learnings to durable homes | staged in the sweep ledgers; flushed by the existing manual path (DEC-52) |

An operator who wants candidates built keeps `wrap.distill = true`, or acts on the sweep report, for example with `/kit:wrap follow` in a session that picks a reported item up.

### ADR link(s)

No new ADR exists. Two decisions are lasting:

- A second kit LaunchAgent beside `kit-weekly`. ADR-0034 decision 9 chose ONE kit scheduler and rejected a plist per job. The cadence differs (every 6h against a fixed weekly slot), so a task amends ADR-0034 to record the exception (DEC-12).
- `wrap.distill` becomes a three-value knob, and the distill half moves out of wrap on a host where the sweep runs.

### Boundaries & failure modes

The sweep reads transcripts outside any repo, which may carry hostile text. Phase 1 writes only kit state under the harvest state dir, the gate ledger, and the launcher log. It never writes a repo and never reaches GitHub. See `## Failure modes`.

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
| claude | `~/.claude/projects/<slug>/<id>.jsonl`; every `<id>/subagents/agent-*.jsonl` is folded in, interleaved with the lead by entry timestamp, each marked `sub` and prefixed `subagent:` | max mtime over the lead file and its subagent files | `type` user/assistant, `text` blocks; `tool_use` as `tool: <name> <input, 200 chars>` | everything else; any session whose cwd is under the harvest state dir (the extractor's own calls). Reuses `parse_transcript.iter_entries`. |
| devin | row of `sessions` in `~/.local/share/devin/cli/sessions.db`, opened read-only (`mode=ro` URI) | `sessions.last_activity_at` (epoch seconds) | `message_nodes.chat_message` JSON roles user, assistant, tool: `content` plus `tool_calls` names; `ts` from `message_nodes.created_at` | role `system` (injected rules). Chain: walk `parent_node_id` up from `sessions.main_chain_id`; fall back to all nodes by `node_id` when null; a fixture pins it (DEC-16). |

Why the interleaved list only grows at its end: a session is read only after `QUIET_MINUTES` of no activity, so every entry written after a read carries a later timestamp than every entry read. The delta key is `last_ts`, the newest entry timestamp read, not a message index, so it stays valid when a subagent file appears later.

A session with fewer than `HARVEST_SWEEP_MIN_MESSAGES` (default 6) kept user plus assistant messages is marked done, skipped with no extractor call, and not counted against `max_sessions_per_run`.

A source that cannot be read (missing file, locked or changed schema, sqlite error) is skipped for the run with a `STATE` row in the report naming the source and the error. `source_fail{source}` counts consecutive failed runs; at `HARVEST_SWEEP_SOURCE_FAIL_RUNS` (default 3) the run's rc is 5, so the heartbeat shows it. One good read resets the count.

**Launch record** (optional input, shipped in ops-toolkit #3631, `d43a81b`). `tools/worker-launch` appends one JSON object per launch to `~/.local/state/worker-launch/launches.jsonl` (override: `HARVEST_SWEEP_LAUNCH_RECORD`):

```
{"ts": "<UTC ISO>", "agent": str, "mode": "tui|print", "handle": str|null, "title": str,
 "brief": path, "brief_copy": path, "cwd": path, "lead_session": str|null}
```

Attribution applies to a Devin session. A record matches when its `agent` is `devin` and its `brief` or `brief_copy` path appears in the session's first kept user message. When several match, the one whose `ts` is nearest the session's `started` wins. The session takes the record's `lead_session`. No file, a malformed line, or no match leaves `lead_session_id` null. There is no time-window fallback (DEC-23). The sweep never fails on this input.

**Sweep extractor.** `PROMPT_SWEEP` in `harvest_sweep.py`, same `HARVEST_EXTRACTOR` seam (default `claude -p --model haiku --setting-sources project`), run with cwd `$HARVEST_STATE_DIR/sweep/extract-cwd/` and `HARVEST_SWEEP_CHILD=1` in its env, so its own transcripts fall under the self-harvest drop and it cannot re-fire the hook. It returns one JSON object, read by a new `extract_json_object` (the existing `extract_json_array` returns the first `[`, which would find an inner array):

```
{"learnings": [<the existing hook element shape: item, kind, home, why>],
 "sightings": [{"pattern": "<kebab slug>", "kind": "repeat|friction|failure|ask",
                "count": <int, occurrences in this session>, "evidence": "<one line>"}]}
```

The prompt carries the canonical slugs of the 50 most recent patterns plus every slug in `proposed.jsonl`, and tells the model to reuse one when it fits. `kind: ask` is an enhancement the operator asked for and the session deferred (wrap step 7b's third candidate kind).

**Extractor failure is not an empty result.** The sweep's extractor call returns `(ok, stdout)`: `ok` is false on a non-zero exit, a timeout, or output with no parseable JSON object. Every failure increments `fail{id}`. The failure is auth-shaped, and the run stops with rc 1, only when a second session also fails in the same run or the probe fails. The probe is one extractor call on a fixed 20-character prompt, made after the run's first failure. The hook path keeps its current behavior.

**Quarantine.** At `fail{id} = HARVEST_SWEEP_QUARANTINE_AFTER` (default 3) the session goes into `quarantined` with its `last_activity` at that moment, is marked done, and the report carries a `STATE` row. When a later scan sees that session's `last_activity` move past the recorded value, the quarantine lifts, `fail{id}` resets, and the session is selected again (DEC-54). Quarantine entries older than 30 days are pruned.

**Raw output cache.** The extractor's stdout is saved to `extract/<source>/<id>@<last_activity>.json` before anything is staged. A replay of the same key reuses the file, so a crash after extraction never pays or varies the model call twice.

**Sanitizing.** Before a sighting or learning is stored: `pattern` and `item` must match `^[a-z0-9-]{1,60}$` (else dropped); `evidence` and `why` are cut to 200 characters of printable ASCII with backticks, angle brackets, `$`, and newlines removed.

**Shared stager.** The locked read-known, dedup, and append block in `_harvest_payload` moves into `_stage_candidates(ledger, glossaries, candidates) -> fresh_rows`. The hook calls it with the session's ledger as today. The sweep calls it with the sweep ledger. Both share slugify, glossary dedup, and the `.lock` file. `existing_slugs` reads rows of every status, so a learning already `flushed:<home>` is never staged again. The sweep reads a repo's `_meta/learned-ledger.md` under that ledger's own `.lock` for dedup and never writes it.

**Stored state** (under `$HARVEST_STATE_DIR/sweep/`, default `~/.claude/dwarves-kit/state/harvest/sweep/`):

| File | Shape | Writer | Idempotency key |
|---|---|---|---|
| `cursor.json` | `{"<source>": {"hwm", "last_success", "done": {"<id>": {"last_activity", "last_ts"}}, "fail": {"<id>": n}, "quarantined": {"<id>": {"last_activity", "ts"}}}, "source_fail": {"<source>": n}}` | atomic replace after each session | (source, id, last_activity) |
| `extract/<source>/<id>@<last_activity>.json` | raw extractor stdout | extraction | file name |
| `ledger/<repo-slug>.md` | the learned-ledger table, `status: queued`, later `flushed:<home>` | `_stage_candidates`; the flush path marks rows flushed | slug (exact + fuzzy + glossary) |
| `patterns.jsonl` | `{"pattern", "canonical", "kind", "source", "session_id", "lead_session_id", "cwd", "count", "evidence", "ts"}` | rewritten via tmp + `os.replace` under `patterns.lock` | (canonical, session_id); a re-read keeps `max(count)` |
| `proposed.jsonl` | `{"pattern", "run_id", "outcome": "REPORTED", "precedent", "lane", "ts"}` | the annotator, once per candidate | canonical pattern, subject to the re-propose rule |
| `runs/<run-id>/manifest.json` | `{"run_id", "sessions": [...], "learnings_staged": n, "learnings_queued": n, "candidates": [{"pattern", "kind", "occurrences", "sessions", "leads", "evidence", "precedent", "lane"}], "cursor_lag_s": {...}, "stale": n}` | the run | run_id |
| `runs/<run-id>/stage1.log`, `report.md` | run log; wrap step 9 grammar under `## Harvest sweep: <run-id>` | the run | run_id |
| `installed` | host marker: `{"label", "host", "kit", "ts"}` | `install --apply` | host |

A run with nothing new writes no `runs/<run-id>/` directory and no manifest; it logs one line to the launcher log.

`<repo-slug>` comes from the session cwd: strip a trailing `/.claude/worktrees/<name>`, walk up to the first directory that exists, then `git rev-parse --git-common-dir` with the trailing `/.git` stripped. A cwd outside any repo goes to `ledger/_no-repo.md`. On the first run after install, queued rows in the repo ledgers of the sessions read (the hook era) are copied into the sweep ledgers so the flush path sees them (DEC-36).

**Aggregation.** Slugs cluster with a fixed fuzzy threshold (`HARVEST_SWEEP_FUZZY`, default 2, independent of the hook's `HARVEST_FUZZY_THRESHOLD`). The first slug seen in a cluster is its canonical name and stays so. Over sightings newer than `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (default 14), a canonical pattern is a candidate when the sum of per-session `count` is at least `HARVEST_SWEEP_MIN_PATTERN_COUNT` (default 3) and it has no blocking `proposed.jsonl` entry. `kind: ask` qualifies at 1. One sighting of count 1 never qualifies. Re-propose rule: a `REPORTED` entry stops blocking after 14 days if the pattern's occurrences grew by at least the threshold since its `ts`.

**Annotator (DEC-51).** For each candidate, code runs `bin/precedent find --surface inventory --json "<slug words>"` and `lib/classify/lane-classify.sh classify "<slug words>: <first evidence line>"`. It records the top hit (`ENHANCE <home>`) or `NEW (precedent: nothing matched)`, and the lane. The candidate is `REPORTED` with `reported: phase 1 reports only`. Nothing is built.

**Report (DEC-56).** Code renders `runs/<run-id>/report.md` in wrap's step 9 grammar and runs `lib/wrap/report-lint.sh` once:

- `## Harvest sweep: <run-id>`; `Needs you: NOTHING` unless a source hit rc 5 (then `UNBLOCK <source>: <error>`).
- `What happened`: one bullet with sessions read per source, trivial and stale counts, learnings staged, candidates found.
- `Shipped` and `Left alone`: `- NOTHING` (phase 1 writes no repo).
- `**Built:**`: one `- REPORTED <slug> ENHANCE <home>: <hit> (lane=<lane>, reported: phase 1 reports only)` or `- REPORTED <slug> NEW (precedent: nothing matched): <slug> (lane=<lane>, reported: phase 1 reports only)` bullet per candidate, or `NOTHING: no candidates`.
- `**Seam:** SKIPPED: the sweep runs no seams in phase 1`.
- `FYI`: `STATE` rows for cursor lag, stale count, quarantines and lifts, source failures, and the queued-learnings count with the flush path; `INCIDENT` rows for a failed probe.
- An overlay section after `FYI`, `**Learnings staged:**`, one bullet per row staged this run (`<slug> (<kind>, <home>) -> ledger/<repo-slug>.md`).

A lint failure is a renderer bug: the findings are appended to the report and the rc is 3. Then `gate-ledger.sh record harvest-sweep-<run-id> harvest ran "<n> sessions, <l> learnings, <c> candidates reported, lag <h>h"`.

**Flush path (DEC-52).** Learnings stay `queued` in `ledger/<repo-slug>.md` until the operator flushes them with the existing manual path: the learning-ledger skill, or `/kit:wrap distill` (its `wrap.after` seam runs the operator's flush). That path reads the sweep ledger dir, routes each row to its home, and marks the row `flushed:<home>` in the sweep ledger, the same status it writes in a repo ledger today. The row stays until `HARVEST_LEDGER=<sweep ledger> harvest.sh --cleanup` archives it. The sweep never marks a row flushed itself. `commands/wrap.md` names the sweep ledger dir as a flush input when `wrap.distill = "harvest"` and the invocation carries `distill`.

**last_success under persistent failure (DEC-53).** `last_success[source]` updates only when that source's read and all its selected extractions complete in a run without an auth stop. While a source keeps failing, its `last_success` stays pinned, so the stale cutoff does not move, no session from the outage is marked stale, and the heartbeat stays red (rc 1 or 5). The cutoff never reaches further back than 30 days, the default Claude transcript retention; an outage longer than that loses those sessions, and the first successful run reports them as stale. After recovery the backlog drains at up to 80 lead sessions a day.

**rc contract** (the sweep entry, `harvest_sweep.py --sweep`). When several apply, the lowest non-zero code wins, and the report lists every one. Codes 2 and 4 are reserved for phase 2 (SPEC-358).

| rc | Meaning | Bridge called |
|---|---|---|
| 0 | ran, including `NOTHING` | yes |
| 1 | an auth-shaped extractor failure stopped the run (probe failed, or two sessions failed) | yes |
| 3 | the rendered report failed `report-lint.sh` | yes |
| 5 | a source unreadable for `SOURCE_FAIL_RUNS` consecutive runs | yes |
| (none) | disabled, no host marker, or `sweep.lock` held: the launcher logs and exits 0 | no |

The launcher calls `python3 <kit>/hooks/harvest_sweep.py --sweep` directly, never through `harvest.sh`, whose `|| true; exit 0` would hide every failure. `harvest.py`'s `_dispatch` routes `--sweep` to the same entry before its `read_payload` fall-through, for manual runs. A disabled or skipped run never calls the bridge, so a job left loaded but disabled goes silent and vps-mon alerts; turning the sweep off for good is `install --uninstall` plus retiring the heartbeat per `job-monitoring-onboarding`.

**Pruning** (each run): `patterns.jsonl` rows older than the pattern window, `proposed.jsonl` entries older than 90 days, quarantine entries older than 30 days, `extract/` files and `runs/` dirs older than 30 days.

### Data model changes

New kit state under `$HARVEST_STATE_DIR/sweep/` (table above). No repo file format changes. `ledger/<repo-slug>.md` reuses the learned-ledger table, so `--cleanup` and the existing flush read it unchanged.

### API changes

- `hooks/harvest_sweep.py --sweep [--dry-run] [--since <iso>]`, also reachable as `harvest.sh --sweep` for a human (rc hidden there). `--dry-run` reads and extracts, prints the manifest, and writes nothing but the raw output cache. `--since` sets a one-off hwm for a manual backfill.
- The sweep is ACTIVE on a host when `harvest.enable` is true AND the `installed` marker exists on that host (DEC-27). The operator `kit.toml` may sync across hosts; the marker does not.
- `harvest.sh` auto modes (no-arg, `--lab-log`, `--stop-trigger`) exit 0 without work when `HARVEST_SWEEP_CHILD=1`, or when the sweep is active on this host and `harvest.hook_when_sweep_on` is false. `--cleanup` is unaffected. The shim reads the keys with `kit_config_get_root`.
- `/kit:wrap`: `wrap.distill` accepts `true`, `false`, or `harvest`. With `harvest` on a host where the sweep is active: the landing half runs, no seam key is read, and the report says `**Built:** SKIPPED: distill runs in the harvest sweep` and `**Seam:** SKIPPED: distill runs in the harvest sweep`, plus a `FYI` `STATE` row naming the knob and saying that in phase 1 the sweep reports candidates and builds none. With `harvest` on a host where it is not active: wrap distills as with `true` and prints a `STATE` row saying the sweep is not installed here. The word `distill` in the invocation wins for that one run; the distill half then also takes the sweep ledger dir as a flush input, and the `FYI` says the sweep will also see the session (DEC-15, DEC-52).
- `lib/wrap/report-lint.sh`: a first `## ` line opening `## Harvest sweep:` sets a new `sweep_report` flag, separate from `follow_report`. In a sweep report every `**Built:**` item must open with `REPORTED` (a `BUILT` or `NOTE` item fails), and `**Seam:**` is still required (DEC-57). `SKIPPED: distill runs in the harvest sweep` passes on both wrap lines (a fixture pins it).

### UI changes

None.

### Infrastructure changes

`kit.toml` gains a `[harvest]` table. Every key resolves with `kit_config_get_root` (operator or kit-root `kit.toml`, never a project `.kit.toml`).

```toml
[harvest]
enable = false               # the switch; active only on a host with the install marker
schedule_hours = 6           # launchd StartInterval, rendered at install
sources = "claude"           # space-separated: claude devin
max_sessions_per_run = 20    # lead-session extractions per run; trivial skips do not count
hook_when_sweep_on = false   # true = the per-session hook keeps running while the sweep is active
```

Tuning constants are env-overridable and not config: `HARVEST_SWEEP_MIN_MESSAGES` (6), `HARVEST_MAXCHARS` (12000, shared with the hook), `HARVEST_SWEEP_QUIET_MINUTES` (30), `HARVEST_SWEEP_MIN_PATTERN_COUNT` (3), `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (14), `HARVEST_SWEEP_FUZZY` (2), `HARVEST_SWEEP_STALE_RUNS` (4), `HARVEST_SWEEP_MAX_SCAN` (2000), `HARVEST_SWEEP_QUARANTINE_AFTER` (3), `HARVEST_SWEEP_SOURCE_FAIL_RUNS` (3), `HARVEST_SWEEP_LAUNCH_RECORD`.

Launchd deploy under `deploy/macos/harvest-sweep/`, copying `lib/sync/deploy/macos/`:

- `harvest-sweep`: the launcher. `#!/bin/bash`, no `.sh`, launchd-safe PATH, optional `~/.config/harvest-sweep/env` for per-machine PATH or Claude auth settings. Phase 1 needs no GitHub or git credential. It re-checks that the sweep is active each run and exits 0 with a log line otherwise. It logs start and end with rc, calls `harvest_sweep.py --sweep` directly, then runs `~/.config/harvest-sweep/bridge <rc> <report path>` best-effort, passing `-` when `report.md` is missing.
- `harvest-sweep.plist.tmpl`: `ProgramArguments[0]` is the launcher's absolute path. Rendered `__LABEL__`, `__KIT__`, `__HOME__`, `__INTERVAL__`.
- `install [--label L] [--apply]`: dry run by default, `--label` defaults to `harvest-sweep`; the Mini installs `mini.harvest-sweep`, a prefix already in vps-mon's `OWNED_PREFIXES` (DEC-13). It refuses unless `harvest.enable` is true. `--apply` renders the plist, writes the `installed` marker, and bootstraps the agent.
- `install --uninstall`: `launchctl bootout` the label, then removes the two files the installer wrote: the plist and the `installed` marker. The host goes back to non-sweep behavior at once (the hook runs again, wrap distills again). It leaves `cursor.json`, the sweep ledgers, `patterns.jsonl`, `proposed.jsonl`, `extract/`, and `runs/` in place, and prints their path, the count of queued learnings, and the size of `extract/`. A later install resumes from the same cursor; the operator flushes the ledgers through the flush path (DEC-47).

Monitoring (consumer side, ops-toolkit): the Mini's bridge pings the vps-mon heartbeat when rc is 0 and sends a fail ping otherwise. The URL lives in `/etc/vps-mon/harvest-sweep-heartbeat-url`, `hb_id` is the discovered label, the interval is `schedule_hours`, and the grace is 2x. The catalog link follows `job-monitoring-onboarding`. The kit ships no endpoint or secret.

## Task Breakdown

Each task touches at most five files and carries one mechanism. Tests go in the harvest section of `tests/test-hooks.sh`; fixtures go under `tests/fixtures/harvest-sweep/`.

### Phase 1a: shared pieces and sources

- [ ] T1: shared stager. Factor `_stage_candidates` out of `_harvest_payload` in `hooks/harvest.py`. Files: `hooks/harvest.py`, `tests/test-hooks.sh`. AC: every existing harvest test passes unchanged.
- [ ] T2: claude adapter. Lead plus subagents interleaved by timestamp, the 60/40 render budget, `last_ts` delta, self-harvest drop, min-messages skip. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a lead fixture, two subagent fixtures. AC: the claude parts of AC1.
- [ ] T3: devin adapter. Read-only open, main-chain walk with fallback, `system` drop, source failure `STATE` row and `source_fail`. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, `tests/fixtures/harvest-sweep/make-devin-db.sh`. AC: the devin parts of AC1; AC14.
- [ ] T4: launch-record attribution. Brief-path match, nearest `ts`, null on no match. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a `launches.jsonl` fixture. AC: the attribution part of AC1.

### Phase 1b: cursor and extraction

- [ ] T5: cursor and selection. hwm, `done{}`, quiet window, scan cap, `max_sessions_per_run`, trivial skips outside the cap, per-source `last_success`, the stale cutoff, `--since`, atomic writes. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC6.
- [ ] T6: extractor call. `(ok, stdout)`, `extract_json_object`, extractor cwd and child env, the raw output cache. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a stub extractor fixture. AC: AC2, AC3.
- [ ] T7: failure handling. Fail counts on every path, the probe, the auth stop, quarantine, lift on new activity, quarantine pruning. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC4, AC5, AC5b.
- [ ] T8: sanitizing. Slug charset, evidence and reason cuts. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, an injection-text fixture. AC: AC9.

### Phase 1c: learnings, patterns, report

- [ ] T9: sweep ledgers. Repo-slug walk, `_stage_candidates` into `ledger/<repo-slug>.md`, repo-ledger reads under its lock, the first-run hook-era carry. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a deleted-worktree cwd fixture. AC: the slug part of AC1; AC11.
- [ ] T10: pattern aggregation. `patterns.jsonl` under its lock with `max(count)`, fuzzy clusters with canonical slugs, window, threshold, `ask`, pruning. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC7.
- [ ] T11: annotator. Precedent and lane per candidate, `proposed.jsonl` with the re-propose rule. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC15.
- [ ] T12: lint flag. `sweep_report` in `lib/wrap/report-lint.sh` with its fixtures. Files: `lib/wrap/report-lint.sh`, `tests/test-hooks.sh`, three report fixtures. AC: AC10.
- [ ] T13: report and rc. Render the report, lint once, the gate-ledger record, the rc contract, `runs/` and `extract/` pruning. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC12.
- [ ] T14: entry. `--sweep`, `--dry-run`, `sweep.lock`, and the `_dispatch` route in `harvest.py`. Files: `hooks/harvest_sweep.py`, `hooks/harvest.py`, `tests/test-hooks.sh`. AC: the lock part of AC4; the After state dry run.

### Phase 1d: config, hook, deploy, wrap

- [ ] T15: config and hook gate. The `[harvest]` table, the host-marker check, and the `harvest.sh` gate with `HARVEST_SWEEP_CHILD`. Files: `kit.toml`, `hooks/harvest.sh`, `tests/test-hooks.sh`. AC: AC8.
- [ ] T16: launcher and plist template. Files: `deploy/macos/harvest-sweep/harvest-sweep`, `deploy/macos/harvest-sweep/harvest-sweep.plist.tmpl`, `tests/test-hooks.sh`. AC: the launcher part of AC4 (rc to the stub bridge, skips without a bridge call, `-` for a missing report).
- [ ] T17: installer. `--label`, `--apply`, `--uninstall`, the marker. Files: `deploy/macos/harvest-sweep/install`, `deploy/macos/harvest-sweep/README.md`, `tests/test-hooks.sh`. AC: AC13.
- [ ] T18: wrap knob. `wrap.distill = "harvest"` with host scoping, the explicit-word override, and the sweep ledger dir as a flush input. Files: `commands/wrap.md`, `kit.toml` (the `[wrap]` comment), `MANUAL.md`, `tests/test-meta.sh`. AC: the wrap part of AC10; test-meta asserts the three states in wrap.md.
- [ ] T19: ADR-0034 amendment recording the second LaunchAgent. Files: the ADR-0034 file. AC: the amendment names the label, the cadence, and why kit-weekly does not carry it.

### Phase 1e: rollout (Mini, in this order)

- [ ] T20: hand dry runs, no plist. Run `python3 <kit>/hooks/harvest_sweep.py --sweep --dry-run` three times across a day with `sources = "claude devin"`; compare each manifest against a hand review of the same sessions. AC: the comparison recorded in `docs/verification/harvest-sweep.md`.
- [ ] T21: enable and install. Set `harvest.enable = true`, `harvest.sources = "claude devin"`, and `wrap.distill = "harvest"` in the Mini operator `kit.toml`; run `install --label mini.harvest-sweep --apply`; in ops-toolkit install the bridge, provision the heartbeat, and add the catalog link, in that order. AC: two consecutive scheduled runs report clean lint, a gate-ledger line, and a heartbeat ping; vps-mon shows the job monitored, not gap. The week of clean runs that follows is SPEC-358's entry condition.

## After state

- [ ] `python3 hooks/harvest_sweep.py --sweep --dry-run` prints a manifest over new claude and devin lead sessions. (Today: no sweep mode.)
- [ ] A second `--sweep` with no new sessions calls no extractor, creates no `runs/` directory, and leaves `cursor.json`, the sweep ledgers, and `patterns.jsonl` unchanged. Its one log line lands in `~/Library/Logs/dwarves-kit/<label>.log`.
- [ ] With the sweep active and `hook_when_sweep_on = false`, a PreCompact or SessionEnd hook fire spawns no harvest child. (Today: every fire spawns one.)
- [ ] `/kit:wrap` on the Mini with `wrap.distill = "harvest"` prints `**Built:** SKIPPED: distill runs in the harvest sweep` and the lint passes. On a host without the marker it distills and prints a `STATE` row.
- [ ] A sweep report lists staged learnings and REPORTED candidates, each with a precedent result and a lane, and no repo on the Mini changed because of the sweep.
- [ ] `launchctl print gui/$(id -u)/mini.harvest-sweep` on the Mini shows the job, and vps-mon lists it monitored.

## Acceptance Criteria (global)

- [ ] AC1: adapters. Each fixture source yields the normalized shape. Devin `system` rows are absent from `messages`. Subagent files interleave with the lead by timestamp into one transcript (one extraction), the lead keeps its 60% share of the budget, and a later read of the same session renders only entries newer than `last_ts`. A Devin worker whose first user message names a record's `brief` takes that record's `lead_session`; with no match it stays null. A session whose cwd is under the harvest state dir, including an extractor call's own transcript, is never selected. A deleted-worktree cwd resolves to its main repo's slug.
- [ ] AC2: idempotency. Running `--sweep` twice over the same fixtures leaves the sweep ledger, `patterns.jsonl`, and `proposed.jsonl` byte-identical after the second run, and the second run makes no extractor call.
- [ ] AC3: crash safety. Killing the sweep after a session's staging and before its cursor write, then re-running, stages no duplicate row, double-counts no sighting, and reuses the cached raw output (the stub extractor is called once for that session). No session between the old and new hwm is skipped.
- [ ] AC4: auth stop, rc, and skips. A stub extractor that exits 1 on every call leaves the hwm unchanged, the sweep exits 1, and the launcher passes 1 to a stub bridge. A disabled run, an unmarked host, and a lock-held run exit 0 and never call the bridge.
- [ ] AC5: quarantine, middle session. A stub extractor that fails only for session B (not the oldest), with a passing probe, lets A and C complete; B's fail count rises each run, the hwm never passes B, and B is quarantined on the third run with a `STATE` row. When B's fixture later gains a newer entry, the quarantine lifts and B is extracted.
- [ ] AC5b: quarantine, oldest session. A stub extractor that fails only for session A, the oldest, with a passing probe: each run increments A's fail count, continues past A to B and C, exits 0, and quarantines A on the third run with a `STATE` row; the hwm then moves past A. With a failing probe, the same run stops with rc 1 and A's fail count still rises.
- [ ] AC6: bounds and staleness. Twenty-five new lead fixtures plus ten trivial ones: one run extracts 20 and marks the 10 trivial done; the next run extracts 5. A fixture older than `STALE_RUNS` x `schedule_hours` before `last_success` is marked done unread, counted in `stale`, and raises a `STATE` row. After a simulated 48h auth outage (`last_success` 48h old), sessions from the outage are extracted, not marked stale. With `last_success` 40 days old, a 35-day-old session is stale (the 30-day floor). Each extractor prompt is at most `HARVEST_MAXCHARS` of transcript plus the fixed prompt. The report carries a cursor lag line.
- [ ] AC7: threshold. Two sessions each sighting a pattern once produce no candidate. A third produces one. One session sighting it with count 3 produces one. An `ask` produces one at count 1. Sightings `commit-hook-false-block` and `commit-hok-false-block` count as one canonical pattern.
- [ ] AC8: hook switch and recursion guard. With the sweep active and `hook_when_sweep_on = false`, the no-arg, `--lab-log`, and `--stop-trigger` modes exit 0 without a child. With `enable = false`, or with no host marker, today's behavior holds. `HARVEST_SWEEP_CHILD=1` suppresses all three modes. A project `.kit.toml` setting any `[harvest]` key changes nothing. The stub extractor's argv contains `--setting-sources project` and never `--bare`.
- [ ] AC9: sanitizing. A fixture transcript whose tool output carries shell metacharacters, angle-bracket tags, and an instruction to edit `hooks/ship-gate.sh` reaches `patterns.jsonl`, the ledger, and the report only as a charset-valid slug and an evidence line of at most 200 printable characters without backticks, angle brackets, `$`, or newlines.
- [ ] AC10: wrap and lint. A `## Harvest sweep:` report whose `**Built:**` items are all `REPORTED` passes; the same report with one `BUILT` item fails; the same report without `**Seam:**` fails. A wrap report with both `SKIPPED: distill runs in the harvest sweep` lines passes.
- [ ] AC11: no repo writes. After a fixture run, each fixture repo's main checkout has the same HEAD sha, the same checked-out branch, the same `.git/config`, the same worktree list, and an empty `git status --porcelain`; its `_meta/learned-ledger.md` is byte-identical. An empty run writes no manifest.
- [ ] AC12: report and rc. A fixture run's report passes `report-lint.sh`, lists each staged learning under `**Learnings staged:**`, and writes one gate-ledger line under `harvest-sweep-<run-id>`. A renderer mutated to drop the `**Seam:**` line gives rc 3 with the findings appended. A devin source failing three runs in a row gives rc 5 and a `Needs you` `UNBLOCK` item.
- [ ] AC13: install and uninstall. The dry run renders a plist whose `ProgramArguments[0]` is the launcher path and refuses with `enable = false`. `install --uninstall` removes the plist and the marker; afterwards `harvest.sh` runs its hook modes again and wrap treats `harvest` as not active; the cursor, ledgers, `patterns.jsonl`, `proposed.jsonl`, `extract/`, and `runs/` are still present, and the command prints the queued-learning count.
- [ ] AC14: source drift. A devin fixture db with a renamed column yields a `STATE` row and no crash; the claude source still runs; after the third consecutive failing run the rc is 5; one good read resets the count.
- [ ] AC15: annotation. Each candidate in a fixture run carries a precedent result (a stub `bin/precedent` hit gives `ENHANCE <home>`, an empty result gives `NEW (precedent: nothing matched)`) and a lane, and is recorded `REPORTED` in `proposed.jsonl`. The same candidate is not reported again the next run; it is reported again after 14 days only when its occurrences grew by the threshold.
- [ ] AC16: `bash tests/test-hooks.sh && bash tests/test-meta.sh` pass.

## Test plan

Outline. `/kit:test-plan` expands it into the coverage matrix.

| Area | Case | Kind |
|---|---|---|
| adapters | one fixture per source; role drops; interleaved subagents and the 60/40 budget; delta by `last_ts`; devin main-chain walk and null fallback; trivial skip; self-harvest drop for the extractor cwd; deleted-worktree cwd; schema drift `STATE` row and rc 5 | unit |
| attribution | brief match; nearest-ts among several; malformed line; missing file; no match stays null | unit |
| cursor | first run window; second run empty; resumed session read as a delta; tie on last_activity; crash between staging and cursor write; stale from `last_success`; outage not stale; 30-day floor; scan cap | unit |
| extractor | probe-confirmed auth stop; two failures stop; single failure continues and counts; oldest-session quarantine; middle-session quarantine; lift on new activity; non-JSON output counts as failure; empty arrays count as success; raw cache reuse | unit |
| aggregation | 2 vs 3 occurrences; in-session count; `ask`; fuzzy canonical cluster; window expiry; proposed block; REPORTED re-propose after growth | unit |
| sanitizing | slug charset; evidence length and stripped characters; injection fixture | unit |
| annotation | stub precedent hit and miss; lane recorded; `REPORTED` only | unit |
| report and rc | lint-clean report; learnings overlay; gate-ledger line; rc 1, 3, 5; renderer mutation gives rc 3 | integration |
| launcher | rc reaches the stub bridge; disabled, unmarked, and lock-held runs skip the bridge; missing report passes `-` | integration |
| hook gate | three auto modes under each switch value; host marker absent; child marker; project toml ignored | integration |
| install | dry run render; refusal when disabled; uninstall removes only what it wrote | integration |
| lint | sweep all-REPORTED passes; sweep with BUILT fails; sweep without Seam fails; wrap harvest SKIPPED lines | fixture |
| no repo writes | HEAD, branch, config, worktrees, status, repo ledger unchanged | integration |
| live | T20 hand dry runs; T21 two scheduled runs | UAT |

**Negative controls.** Each runs after the change is committed, with `bash lib/gate/negctl.sh <root> "bash tests/test-hooks.sh" "<mutate>"`, and the named test must go red:

| Mutation | Test that must fail |
|---|---|
| move the cursor write ahead of `_stage_candidates` | AC3 crash safety |
| treat a failed extractor call as an empty result | AC4 hwm unchanged |
| launcher calls the sweep through `harvest.sh` (rc swallowed) | AC4 bridge receives 1 |
| never increment the per-session fail count | AC5 quarantine on the third run |
| skip the fail-count increment on the stop path, or treat any first failure as auth without the probe | AC5b oldest session quarantined |
| drop the quarantine lift | AC5 B extracted after new activity |
| measure stale from now instead of `last_success` | AC6 outage sessions extracted |
| drop the evidence character filter | AC9 no angle brackets or backticks |
| remove the `HARVEST_SWEEP_CHILD` check from `harvest.sh` | AC8 child marker |
| read `hook_when_sweep_on` with `kit_config_get` (project toml honored) | AC8 project toml ignored |
| let `sweep_report` accept a `BUILT` item | AC10 sweep with BUILT fails |

## Verification

```
bash tests/test-hooks.sh && bash tests/test-meta.sh
bash lib/config/kit-config.sh selftest
bash lib/wrap/report-lint.sh tests/fixtures/harvest-sweep/report-reported-ok.md
HARVEST_EXTRACTOR=<stub> HARVEST_STATE_DIR=$(mktemp -d) python3 hooks/harvest_sweep.py --sweep --dry-run
```

Rollout proof (T20, T21) goes into `docs/verification/harvest-sweep.md`: the three dry-run manifests against the hand review, `launchctl print` for the label, the vps-mon monitored state, and two scheduled run reports.

## Edge Cases

1. A live session idles past the quiet window and then resumes. It is read, then re-read later from `last_ts` onward. Its sightings merge by `max(count)`, and its learnings dedup by slug.
2. A subagent file appears after its lead was read. Its entries are newer than `last_ts` (the quiet window guarantees it), so the next read renders them as the delta.
3. The Devin db is locked by a running Devin. The read-only URI read retries once, then counts a source failure for the run with a `STATE` row; the devin cursor does not move.
4. A session's cwd was a worktree that has since been removed. The slug walk strips `/.claude/worktrees/<name>` and walks up to an existing parent.
5. Two sessions share a cwd in a repo with no `_meta/learned-ledger.md`. The sweep ledger for that repo slug is created; nothing is created in the repo.
6. A pattern slug drifts across sessions. The canonical-slug list in the prompt is the first guard, and the fixed fuzzy threshold is the second. A miss splits the count and delays the candidate. It never reports a single sighting.
7. The system clock jumps backward. The hwm is compared against source timestamps, so no session is lost; the quiet window may delay one run.
8. The operator runs `/kit:wrap distill` on the Mini. Both distill the same session. Learnings dedup by slug; wrap may build a candidate the sweep only reported, and the sweep's next precedent result then names wrap's build.
9. `sources` names an agent with no adapter (for example `codex`). That word logs `unknown source` and is skipped; the others run.
10. The operator `kit.toml` syncs to the Air with `wrap.distill = "harvest"`. The Air has no marker, so its wraps keep distilling and its hook keeps running, each saying so in a `STATE` row or log line.
11. A learning is flushed from the sweep ledger and later extracted again from a new session. `existing_slugs` reads the `flushed:<home>` row, so it is not staged twice.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| OAuth expired or keychain locked under launchd | the first extractor call fails and the probe fails; rc 1; fail ping | cursor untouched past the failing session; vps-mon alerts; fix auth per the `launchd-headless-job` recipe; `last_success` stays pinned, so the outage's sessions are extracted, not dropped, at up to 80 a day (30-day floor) |
| One session breaks the extractor every time | its fail count rises | quarantine after 3 with a `STATE` row, whether or not it is the oldest; lifts on new activity; the run continues |
| Source schema drift (a Devin update) | `STATE` row per run; rc 5 after 3 runs; fail ping | the other sources keep running; fix the adapter; one good read resets the count |
| Recursion storm (the extractor re-fires harvest) | many `harvest` children in `ps` | `--setting-sources project`, `HARVEST_SWEEP_CHILD=1` in the extractor env, and the self-harvest drop for the extractor cwd |
| Hostile transcript text | odd slugs or evidence in the report | sanitizing; phase 1 has no actor that follows the text: nothing is built, pushed, or merged |
| Quota burn | Max-plan usage spikes on the 6h cadence | `enable = false`; `max_sessions_per_run`; delta extraction; raw output cache; no call when nothing is new; the quota line above bounds it |
| Load above the cap | cursor lag grows; `stale` non-zero with a `STATE` row | raise `max_sessions_per_run` or lower `schedule_hours` |
| Learnings pile up unflushed | the queued-learnings `STATE` row grows run over run | the operator runs the flush path; the sweep never flushes on its own in phase 1 |
| Heartbeat can never go red | job silently broken, monitor green | the launcher calls the sweep entry directly and passes its rc; disabled runs skip the bridge |
| Transcript data to a new provider | Devin transcripts reach Anthropic Haiku | `sources` defaults to `claude`; adding `devin` is an operator decision in root-only config |
| Secret in a transcript reaches a prompt or ledger | a credential-shaped string in a sweep ledger | same exposure class as today's hook; sanitizing keeps only slugs and short reasons |

## Out of Scope

- Building, pushing, opening PRs, or merging from the sweep. That is SPEC-358 (phase 2).
- Changing wrap's landing half. Steps 0 to 6, 8, and 9 stay as they are.
- A Codex adapter. The adapter seam stays; Codex was verified from one `codex exec` rollout only (cli 0.156.1) and is added once an interactive rollout is checked (DEC-26).
- Replacing `session-audit` or `session-intel repeat`. They stay on kit-weekly.
- `bin/reflect`, which proposes from gate and run ledgers, not transcripts.
- Changing the launch record. ops-toolkit #3631 owns its format; the sweep only reads it.
- LAB_LOG drafts from the sweep. The hook's `--lab-log` draft stops with the hook (DEC-3), and wrap step 6's activity line covers the session record (DEC-14).
- An automatic flush. Learnings wait for the existing manual flush path (DEC-52).
- Any board row. The sweep follows wrap: a candidate is reported, never filed.
- Linux or systemd scheduling.
- Auto-enabling. `enable` ships false.

## Decision Log

Entries marked "moved to phase 2" keep their history here; their effect lives in SPEC-358 and nothing in this spec implements them.

- DEC-1 (operator): autonomy follows wrap's lane rules. Tiny and normal candidates build in worktrees and merge only when green through `wrap merge --apply --pr`. Full-lane candidates open as DRAFT PRs and go to the operator as `REVIEW`. Learnings flush through step 7c and the learning-ledger route. Moved to phase 2 by DEC-50; phase 1 reports candidates and builds none.
- DEC-2 (operator): the host is the Mac Mini via launchd, following the estate plist rules, with a vps-mon heartbeat before the job counts as done.
- DEC-3 (operator): the per-session PreCompact and SessionEnd harvest hook is off while the sweep is on, through one switch (`hook_when_sweep_on`), so nothing is staged twice or paid for twice.
- DEC-4: enhance the harvest tool rather than a sibling tool. The sweep lives in `hooks/harvest_sweep.py`, which imports harvest.py's shared functions; the shared stager keeps one dedup path.
- DEC-5: code decides which sessions, counts, and thresholds. The model part that decides what to build moved to phase 2. Rejected: a model-only sweep (no deterministic cursor or bound).
- DEC-6: the sweep stages learnings into kit state, not a repo's `_meta/learned-ledger.md`, because that file sits in a main checkout that live sessions share.
- DEC-7: an auth-shaped extractor failure stops the run with the cursor untouched. An empty result and a failed call must not look alike. Narrowed by DEC-30 and DEC-39.
- DEC-8: a pattern needs `MIN_PATTERN_COUNT` occurrences (in-session counts included, matching wrap step 7b's "three or more times" rule) before it is a candidate. An operator `ask` needs one.
- DEC-9: every `[harvest]` key resolves root-only (`kit_config_get_root`), the same reason as wrap's autonomy knobs.
- DEC-10: `sources` defaults to `claude`. Sending another agent's transcripts to Haiku is a new data path and an explicit operator choice.
- DEC-11 (operator): the stage-2 settings file wiring only the enforcement hooks. Moved to phase 2.
- DEC-12 (operator): a separate LaunchAgent, not a `jobs.txt` line, because the cadence differs from kit-weekly. T19 amends ADR-0034 decision 9. Rejected: per-job intervals in kit-weekly.
- DEC-13 (operator): the installer takes `--label` (default `harvest-sweep`); the Mini installs `mini.harvest-sweep`.
- DEC-14 (operator): the sweep drafts no LAB_LOG entry.
- DEC-15 (operator): an explicit `distill` word in `/kit:wrap` wins over `wrap.distill = "harvest"` for that run.
- DEC-16 (operator): the devin adapter walks `parent_node_id` up from `sessions.main_chain_id` and falls back to all nodes by `node_id`; a fixture pins it.
- DEC-17 (operator): `codex` stays out of the default `sources` until an interactive rollout is verified. Superseded by DEC-26.
- DEC-18 (operator): with no cursor, the first run starts `schedule_hours` back; `--since` covers a manual backfill.
- DEC-19 (resolved upstream): attribution reads the worker-launch record from ops-toolkit #3631 (`d43a81b`). Its agent + cwd + window fallback is superseded by DEC-23.
- DEC-20 (operator): the sweep's gate-ledger rid is `harvest-sweep-<run-id>`. It is never pushed, so ship-gate never looks for it.
- DEC-21: the sweep entry has its own rc contract, and the launcher calls it directly, never through `harvest.sh`. Disabled, unmarked, and lock-held runs exit 0 without calling the bridge. Codes 2 and 4 are reserved for phase 2.
- DEC-22: rollout order is hand dry runs with no plist, then `enable = true`, then `install --apply`, then bridge and heartbeat. `install` keeps its refusal while disabled.
- DEC-23: attribution uses the brief-path match only. The agent + cwd + time-window fallback is dropped as a guess that can mis-attribute.
- DEC-24: the model never merges; a code step gates and merges. Superseded by DEC-38; both moved to phase 2.
- DEC-25: patterns, evidence, and learnings are sanitized (slug charset, 200 printable characters, no backticks, angle brackets, `$`, or newlines).
- DEC-26: the Codex adapter is deferred to a later change; the adapter seam stays.
- DEC-27: harvest mode applies per host. The sweep is active only where `install --apply` wrote the `installed` marker, so a synced operator `kit.toml` cannot switch off distill or the hook on a host with no sweep.
- DEC-28: the extraction unit is the lead session with its subagents folded in. Trivial skips do not count against the cap, a scan cap bounds the stat work, stale sessions are marked done unread, and every report shows cursor lag. Stale is defined by DEC-41 and DEC-53.
- DEC-29: idempotency rests on a raw output cache keyed `<id>@<last_activity>`, sightings merged by `max(count)` per (canonical, session), `patterns.jsonl` rewritten via tmp + `os.replace` under `patterns.lock`, and a fixed sweep fuzzy threshold with a stable canonical slug per cluster.
- DEC-30: per-session failures quarantine after `QUARANTINE_AFTER` (3) with a `STATE` row. The hwm advances only through a contiguous prefix of done sessions. Its auth rule is replaced by DEC-39; lifting and pruning are DEC-54.
- DEC-31: stage-2 resume, process-group kill, and the lint fix loop. Moved to phase 2.
- DEC-32: cost bounds: delta extraction on re-touch, pruning by age, and a re-propose rule for `REPORTED` entries stay here. The stage-2 spawn threshold and `--max-turns` moved to phase 2.
- DEC-33: the `[harvest]` table is small; other tuning is env-overridable constants; `--source` and the half-interval skip are cut. In phase 1 the table is `enable`, `schedule_hours`, `sources`, `max_sessions_per_run`, and `hook_when_sweep_on`; `max_builds_per_run`, `build_repos`, and `distill_timeout_minutes` moved to phase 2.
- DEC-34: the rendered stage-2 settings file with `env.CLAUDE_PLUGIN_ROOT`, and its ship-gate rationale. Moved to phase 2.
- DEC-35: extracting wrap's distill half into `docs/patterns/distill-build-and-land.md`. Moved to phase 2; phase 1 builds nothing, so wrap.md keeps its text and this spec carries a phase 1 contract table instead.
- DEC-36: the report counts every queued row across the sweep ledgers, repo ledgers are read under their own `.lock`, and the first run carries hook-era queued rows into the sweep ledgers.
- DEC-37: `report-lint.sh` gets its own `sweep_report` flag; reusing `follow_report` would drop the Seam rule. Its phase 1 meaning is DEC-57; the full-lane DRAFT rule moved to phase 2.
- DEC-38 (operator): the stage-2 model has no GitHub or push capability, and stage 3 code does every push, PR, and merge. Moved to phase 2.
- DEC-39 (operator): every extractor failure increments `fail{id}`, including on the stop path. A failure counts as auth-shaped only when a second session also fails in the same run or a fixed probe call fails. A bad oldest session is therefore quarantined on its third run instead of stopping every run.
- DEC-40: per-worktree push URL through `extensions.worktreeConfig`. Moved to phase 2.
- DEC-41: stale is measured from `last_success`, not from now, so an auth outage does not turn its own backlog stale. Any stale count raises a `STATE` row.
- DEC-42: the learnings spawn threshold and the seam-unresolved pause. Moved to phase 2.
- DEC-43: subagent messages interleave with the lead by entry timestamp; the lead keeps a fixed 60% of the character budget; the delta key is `last_ts`.
- DEC-44: the extractor runs with its cwd under the harvest state dir, so the self-harvest drop covers its own transcripts.
- DEC-45: rc 5 is a source unreadable for `SOURCE_FAIL_RUNS` consecutive runs, and an unreadable source is a `STATE` row every run. rc 4 (stage-3 failure) moved to phase 2.
- DEC-46: the launcher git and GitHub credential contract. Moved to phase 2; the phase 1 launcher needs no GitHub credential.
- DEC-47: `install --uninstall` removes only what the installer wrote (plist and marker in phase 1) and leaves every piece of sweep state in place, printing what remains, so a re-install resumes and nothing queued is lost.
- DEC-48: ship-gate synthesis for code pushes. Moved to phase 2.
- DEC-49: the path denylist. Moved to phase 2.
- DEC-50 (operator): the sweep ships in two phases. Phase 1 (this spec) reads, extracts, counts, stages, and reports; it spawns no model session beyond the per-session Haiku extractor, creates no worktree, pushes nothing, opens no PR, and merges nothing. Phase 2 (SPEC-358) adds building and merging, and starts only after phase 1 runs clean on the Mini for a week.
- DEC-51: in phase 1, code annotates each candidate with the `bin/precedent` result and the `lane-classify.sh` lane (both local, no model), and reports it with `reported: phase 1 reports only`.
- DEC-52: learnings stay queued in the sweep ledgers until the existing manual flush path runs (the learning-ledger skill, or `/kit:wrap distill` with its `wrap.after` seam). That path marks each routed row `flushed:<home>` in the sweep ledger; `harvest.sh --cleanup` with `HARVEST_LEDGER` pointed at the sweep ledger archives flushed rows. The sweep never marks a row flushed.
- DEC-53: `last_success` is per source and updates only on a run where that source's read and extractions completed without an auth stop. Under a persistent failure it stays pinned, the heartbeat stays red, and the stale cutoff never reaches back more than 30 days.
- DEC-54: a quarantine lifts when the session's `last_activity` moves past its value at quarantine time; quarantine entries older than 30 days are pruned.
- DEC-55: the quota ceiling at the default caps is 21 Haiku calls a run, 84 a day, about 2,520 a month, and about 8.6M input tokens a month.
- DEC-56: code renders the report and lints it once. A lint failure is a renderer bug, reported as rc 3 with the findings appended; there is no model fix loop in phase 1.
- DEC-57: in phase 1, `sweep_report` requires every `**Built:**` item to open with `REPORTED` and keeps the `**Seam:**` requirement.

## Open questions

(none; design questions were resolved at approval, in the design critique, and in validation rounds 1 and 2, see DEC-11 to DEC-57; phase 2's open items live in SPEC-358)
