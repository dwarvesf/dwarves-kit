# Spec: harvest sweep, phase 1 (scheduled multi-agent distill, report only)

Generated: 2026-09-29
Status: APPROVED (operator approved the last folds with no further validation round; ready to build)
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

- Load-bearing dimension: session volume. Measured on the Mini over 24h: 46 top-level Claude transcripts and 237 subagent transcripts changed. Subagents fold into their lead, so the extraction unit is the lead session (46 a day, plus Devin sessions). The default cap is 20 extractions a run at 4 runs a day, 80 a day, so the measured load fits with about 40% headroom. A burst above 80 a day queues and drains oldest first. No session is ever dropped unread (DEC-71). Every report carries each source's cursor lag, and lag above 24h on two consecutive runs raises a `DECIDE` item and rc 6 (DEC-72).
- Quota (DEC-55, DEC-68). At the caps a run makes at most 21 Haiku calls (20 extractions plus 1 probe), so 84 a day and about 2,520 a month. Each call sends at most `HARVEST_MAXCHARS` (12,000) characters of transcript, about 1,200 characters of fixed prompt, and at most 100 known slugs (the 50 most recent pattern slugs plus the last 50 proposed, at most 62 characters each, 6,200 characters): at most 19,400 characters, about 4,900 input tokens at 4 characters a token, so at most about 12.3M input tokens a month. Output is a small JSON object. `bin/precedent` and `lane-classify.sh` are local and cost no tokens. A run with nothing new makes no call.
- Second dimension: the number of agents. A new agent is one adapter function in `hooks/harvest_sweep.py` plus one word in `harvest.sources`. Codex is deferred on that seam (Out of Scope).
- Units: adapter (source to normalized transcript), cursor (which sessions are new), extractor (transcript to learnings + sightings), sanitizer, stager (dedup + append, shared with the hook), aggregator (sightings to candidates), annotator (candidate to precedent result + lane), reporter (run to report + rc), launcher (schedule, rc, heartbeat). Each has one input and one output shape below.

## Picture

```
  launchd (StartInterval = schedule_hours)
        |
        v
  deploy/macos/harvest-sweep/install --label L --apply  (T17)
        |  renders the plist, writes the host marker state/harvest/sweep/installed
        v
  deploy/macos/harvest-sweep/harvest-sweep   (launcher, #!/bin/bash, no .sh)
        |  enable false, no host marker, or sweep.lock held  --> log, exit 0, NO bridge call
        v
  python3 <kit>/hooks/harvest_sweep.py --sweep  (direct call, own rc; not via harvest.sh)
        |
        |  cursor.json --> adapters: claude (subagents interleaved by ts) | devin
        |                  launches.jsonl --> lead attribution (brief-path match)
        |  per lead session: cached raw output, or Haiku extractor (cwd under the state dir)
        |      --> sanitize + redact --> learnings --> _stage_candidates --> ledger/<repo-slug>.md
        |                                          why + evidence + source --> <repo-slug>.rows.jsonl
        |                   --> sightings --> patterns.jsonl
        |  aggregate (occurrences >= MIN_PATTERN_COUNT) --> candidates
        |  per source lag: eligible unread count + oldest age (nothing is ever dropped unread)
        |  per candidate: bin/precedent find + lane-classify.sh  (local, no model)
        |      --> REPORTED, recorded in proposed.jsonl
        v
  runs/<id>/report.md (wrap step 9 grammar) --> report-lint.sh --> gate-ledger record
        |  lag over 24h on two runs running --> rc 6 + DECIDE
        |
        v
  bridge ~/.config/harvest-sweep/bridge <rc> <report path or "-">  --> vps-mon heartbeat

  learnings stay queued in the sweep ledgers
      learning-ledger skill --> harvest.py --flush-list        (JSON rows + sidecar context)
                            --> routes each row to its home from why + evidence
                            --> harvest.py --mark-flushed <row-id> <ref>   (under the lock)
      next sweep run --> archives flushed rows to <ledger>.archive.md (still read for dedup)

  /kit:wrap on a host with the sweep marker and wrap.distill = "harvest": landing half only,
  Built/Seam = SKIPPED: distill runs in the harvest sweep
  harvest_sweep.py --status (T14) --> wrap FYI STATE row: newest report, candidates, queued (T18)
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
  filtered at selection (cwd under the state dir, Devin hidden = 1) --> done{}, like trivial
  order by last_activity asc; trivial sessions --> done{} without counting against the cap
  take max_sessions_per_run; the rest stay eligible, oldest first next run (never dropped)
  lag = count and oldest age of eligible sessions not taken
      |
      v  per session, in order
  raw output cached for <id>@<last_activity>? --yes, parseable--> reuse it
                                              --yes, unparseable--> remove it, extract again
      | no
      v
  extract with --tools "" (only entries with ts > seen{id}.last_ts)
      |-- limit-shaped (usage or rate limit) --> hold: stop extracting, no fail count,
      |                                          STATE row, rc 0, cursor untouched from here
      |-- other fail --> fail{id} += 1 (always, on every path)
      |            is this the second failure this run, or does the probe call fail?
      |              yes --> auth stop: rc 1, cursor untouched past this session
      |              no  --> continue; at fail{id} = QUARANTINE_AFTER: quarantine + STATE row
      | ok
      v
  save raw output --> sanitize + redact --> stage learnings --> add sightings for this extract key
      |
      v
  done{id} = last_activity; seen{id} = {last_ts, ts}; hwm = last_activity of the longest done prefix
  prune done{} < hwm; prune seen{} by age (30 days); write cursor.json atomically (tmp + os.replace)
```

A failing session is counted in `fail{id}` even when the run stops, so a bad session that is the oldest one gets quarantined on its third run instead of blocking every run.

### Distill-half contract (phase 1)

The sweep does part of wrap's distill half. It reads `commands/wrap.md` for nothing at run time; this table records which step it stands in for.

| wrap distill-half step | phase 1 sweep |
|---|---|
| pre-step-0 scan of the live session | the manifest's `candidates`, counted across sessions |
| step 7a DEBT marker (rid from the branch) | not done; the run record uses rid `harvest-sweep-<run-id>` |
| step 7b precedent find + lane-classify | done by code per candidate, with the pattern's slug and evidence as the query, and wrap 7b's rule that a code home beats a prose home (DEC-59) |
| step 7b build | not done; every candidate is `REPORTED` (phase 2, SPEC-358) |
| step 7c incident notes | not done; they stay with `/kit:wrap distill` |
| `wrap.before` and `wrap.after` seams | not run; the report's `**Seam:**` line says so |
| learnings to durable homes | staged in the sweep ledgers; drained by the learning-ledger skill through `--flush-list` and `--mark-flushed` (DEC-52, DEC-58) |

An operator who wants candidates built keeps `wrap.distill = true`, or acts on the sweep report, for example with `/kit:wrap follow` in a session that picks a reported item up.

### ADR link(s)

No new ADR exists. Two decisions are lasting:

- A second kit LaunchAgent beside `kit-weekly`. ADR-0034 decision 9 chose ONE kit scheduler and rejected a plist per job, and decision 6 fenced the scheduler instance consumer-side. The cadence differs (every 6h against a fixed weekly slot), so T19 amends decisions 6 and 9: the kit owns the template, launcher, and installer; the instance and the heartbeat bridge stay consumer-side, the `board-sync-cron` precedent (DEC-12, DEC-67).
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
| devin | row of `sessions` in `~/.local/share/devin/cli/sessions.db`, opened read-only (`mode=ro` URI); `cwd` from `sessions.working_directory` | `sessions.last_activity_at` (epoch seconds) | `message_nodes.chat_message` JSON roles user, assistant, tool: `content` plus `tool_calls` names; `ts` from `message_nodes.created_at` | role `system` (injected rules); sessions with `hidden = 1` (the column's meaning is undocumented, every row on the Mini is 0, so a hidden session is skipped rather than guessed at). Chain: walk `parent_node_id` up from `sessions.main_chain_id`; fall back to all nodes by `node_id` when null; a fixture pins it (DEC-16). |

Why the interleaved list only grows at its end: a session is read only after `QUIET_MINUTES` of no activity, so every entry written after a read carries a later timestamp than every entry read. The delta key is `seen{id}.last_ts`, the newest entry timestamp read, not a message index, so it stays valid when a subagent file appears later. `seen{}` is a separate per-id map pruned by age (30 days), not by the hwm, so pruning `done{}` never loses a delta key (DEC-60).

A session with fewer than `HARVEST_SWEEP_MIN_MESSAGES` (default 6) kept user plus assistant messages is marked done, skipped with no extractor call, and not counted against `max_sessions_per_run`.

A source that cannot be read (missing file, locked or changed schema, sqlite error) is skipped for the run. A source whose every selected session this run was trivial, with at least `HARVEST_SWEEP_DRIFT_MIN_SCANNED` (default 10) scanned, counts as a failed read too: that is what a format change that empties every transcript looks like (DEC-61). Either way the source is recorded with a `STATE` row in the report naming the source and the error. `source_fail{source}` counts consecutive failed runs; at `HARVEST_SWEEP_SOURCE_FAIL_RUNS` (default 3) the run's rc is 5, so the heartbeat shows it. One good read resets the count.

**Launch record** (optional input, shipped in ops-toolkit #3631, `d43a81b`). `tools/worker-launch` appends one JSON object per launch to `~/.local/state/worker-launch/launches.jsonl` (override: `HARVEST_SWEEP_LAUNCH_RECORD`):

```
{"ts": "<UTC ISO>", "agent": str, "mode": "tui|print", "handle": str|null, "title": str,
 "brief": path, "brief_copy": path, "cwd": path, "lead_session": str|null}
```

Attribution applies to a Devin session. A record matches when its `agent` is `devin` and its `brief` or `brief_copy` path appears in the session's first kept user message. When several match, the one whose `ts` is nearest the session's `started` wins. The session takes the record's `lead_session`. No file, a malformed line, or no match leaves `lead_session_id` null. There is no time-window fallback (DEC-23). The sweep never fails on this input.

**Sweep extractor.** `PROMPT_SWEEP` in `harvest_sweep.py`, same `HARVEST_EXTRACTOR` seam, with its own default `claude -p --model haiku --setting-sources project --tools "" --strict-mcp-config --no-session-persistence`. `--strict-mcp-config` loads no MCP server, and `--no-session-persistence` keeps the call from writing a transcript at all (both flags checked in `claude --help` on the Mini, DEC-76). `--tools ""` disables every built-in tool (checked against `claude --help`, whose `--tools` entry says an empty string disables all tools), so a hostile transcript cannot make the extractor act (DEC-63). It runs with cwd `$HARVEST_STATE_DIR/sweep/extract-cwd/` and `HARVEST_SWEEP_CHILD=1` in its env, so its own transcripts fall under the self-harvest drop and it cannot re-fire the hook. It returns one JSON object, read by a new `extract_json_object` (the existing `extract_json_array` returns the first `[`, which would find an inner array):

```
{"learnings": [<the hook element shape: item, kind, home, why> plus "evidence": "<one line from the session>"],
 "sightings": [{"pattern": "<kebab slug>", "kind": "repeat|friction|failure|ask",
                "count": <int, occurrences in this session>, "evidence": "<one line>"}]}
```

The prompt carries at most 100 known slugs: the canonical slugs of the 50 most recent patterns plus the 50 most recent `proposed.jsonl` slugs, and tells the model to reuse one when it fits (DEC-68). `kind: ask` is an enhancement the operator asked for and the session deferred (wrap step 7b's third candidate kind).

**Extractor failure is not an empty result.** The sweep's extractor call returns `(ok, stdout, stderr)`: `ok` is false on a non-zero exit, a timeout, or output with no parseable JSON object. A failure whose stderr or stdout is limit-shaped (it matches `usage limit`, `rate limit`, `5-hour`, or `limit reached`, case-insensitive) is a hold, not a failure: extraction stops for the run, no `fail{id}` rises, the cursor stays where it is, the report carries a `STATE` row, and the rc is 0, so no fail ping (DEC-80). A limit that persists shows up through the lag rule instead. Every other failure increments `fail{id}`. It is auth-shaped, and the run stops with rc 1, only when a second session also fails in the same run or the probe fails. The probe is one extractor call on a fixed 20-character prompt, made after the run's first non-limit failure. The hook path keeps its current behavior.

**Quarantine.** At `fail{id} = HARVEST_SWEEP_QUARANTINE_AFTER` (default 3) the session goes into `quarantined` with its `last_activity` at that moment, is marked done, and the report carries a `STATE` row. When a later scan sees that session's `last_activity` move past the recorded value, the quarantine lifts, `fail{id}` resets, and the session is selected again (DEC-54). Quarantine entries older than 30 days are pruned.

**Raw output cache.** The extractor's stdout is saved to `extract/<source>/<id>@<last_activity>.json` before anything is staged. A replay of the same key reuses the file, so a crash after extraction never pays or varies the model call twice. `extract/` and its subdirectories are created mode 0700 and each file 0600, because the cache holds unredacted model output (DEC-78). Each cache file is written to a temp file in the same directory and moved into place with `os.replace`, so a crash never leaves a half-written file. A cache file that does not parse is removed and the session is extracted again; that is not a failure and raises no fail count (DEC-82).

**Sanitizing.** Before a sighting or learning is stored: `pattern` and `item` must match `^[a-z0-9-]{1,60}$` (else dropped). `evidence` and `why` first pass a credential-shape redaction that replaces each match with `[redacted]`: runs of 32 or more hex characters, tokens starting `sk-`, `sk_live_`, `rk_live_`, `ghp_`, `gho_`, `github_pat_`, `glpat-`, `AIza`, `AKIA`, `ops_`, or `xox` followed by a letter and a dash, JWT-shaped strings (`eyJ` then two more base64url segments joined by dots), and PEM `BEGIN ... PRIVATE KEY` headers (DEC-63, DEC-89). Then they are cut to 200 characters of printable ASCII with backticks, angle brackets, `$`, and newlines removed. `stage1.log` carries counts, ids, and error classes only, never transcript or extractor text, and is written mode 0600 (DEC-89).

**Shared stager (DEC-85, DEC-86).** The locked read-known, dedup, and append block in `_harvest_payload` moves into `_stage_candidates(ledger, glossaries, candidates, extra_known=()) -> fresh_rows`. `extra_known` is a list of extra files whose rows count as known slugs. The hook calls it with the session's ledger and no extras, as today. The sweep calls it per repo slug with that slug's sweep ledger, the repo's `learning/*/GLOSSARY.md` files as `glossaries`, and as `extra_known`: the sweep ledger's `.archive.md`, the repo's `_meta/learned-ledger.md`, and that file's `.archive.md`. Both callers share slugify, glossary dedup, and the sweep ledger's `.lock`. `existing_slugs` reads rows of every status, so a learning already flushed or archived is never staged again (DEC-70). A repo file is read only if it already exists, and its `.lock` is opened only if it already exists, read-only and without `O_CREAT`; with no lock file the read goes ahead unlocked. The sweep never creates or writes a file in a repo.

**Row context sidecar (DEC-83).** The ledger table keeps only `date | item | kind | home | status`, so each sweep ledger has a sidecar, `ledger/<repo-slug>.rows.jsonl`, one JSON object per row id: `{"row_id": "<repo-slug>:<item>", "why", "evidence", "source": "<source>/<session_id>", "lead_session_id"}`, with `why` and `evidence` already redacted and cut. The sweep writes the sidecar entry under the ledger's `.lock` right after `_stage_candidates` returns the fresh rows. The write is idempotent by row id and also runs for a row that exists without a sidecar entry, so a crash between the two writes is repaired by the replay of the cached raw output.

**Stored state** (under `$HARVEST_STATE_DIR/sweep/`, default `~/.claude/dwarves-kit/state/harvest/sweep/`):

| File | Shape | Writer | Idempotency key |
|---|---|---|---|
| `cursor.json` | `{"<source>": {"hwm", "done": {"<id>": last_activity}, "seen": {"<id>": {"last_ts", "ts"}}, "fail": {"<id>": n}, "quarantined": {"<id>": {"last_activity", "ts"}}}, "source_fail": {"<source>": n}, "lag_runs": n}` | atomic replace after each session | (source, id, last_activity) |
| `extract/<source>/<id>@<last_activity>.json` | raw extractor stdout | extraction | file name |
| `ledger/<repo-slug>.md` (+ `.archive.md`, + `.rows.jsonl`) | the learned-ledger table, `status: queued`, later `flushed:<ref>`; flushed rows move to the archive sibling; the sidecar holds each row's `why`, `evidence`, `source`, and `lead_session_id` | `_stage_candidates` and the sidecar write; `--mark-flushed`; the next run's archive step | slug (exact + fuzzy + glossary + archive); sidecar by row id |
| `patterns.jsonl` | `{"pattern", "canonical", "kind", "source", "session_id", "extract_key", "lead_session_id", "cwd", "count", "evidence", "ts"}` | rewritten via tmp + `os.replace` under `patterns.lock` | (canonical, session_id, extract_key); a replay of the same key replaces its row; occurrences SUM across keys (DEC-60) |
| `proposed.jsonl` | `{"pattern", "run_id", "outcome": "REPORTED", "precedent", "lane", "ts"}` | the annotator, once per candidate | canonical pattern, subject to the re-propose rule |
| `runs/<run-id>/manifest.json` | `{"run_id", "sessions": [...], "learnings_staged": n, "learnings_queued": n, "candidates": [{"pattern", "kind", "occurrences", "sessions", "leads", "evidence", "precedent", "lane"}], "lag": {"<source>": {"eligible": n, "oldest_age_s": n}}}` | the run | run_id |
| `runs/<run-id>/stage1.log` (0600), `report.md` | run log with counts, ids, and error classes only; wrap step 9 grammar under `## Harvest sweep: <run-id>` | the run | run_id |
| `installed` | host marker: `{"label", "host", "kit", "ts"}` | `install --apply` | host |

A run with nothing new writes no `runs/<run-id>/` directory and no manifest; it logs one line to the launcher log.

`<repo-slug>` comes from the session cwd: strip a trailing `/.claude/worktrees/<name>`, walk up to the first directory that exists, then `git rev-parse --path-format=absolute --git-common-dir` with the trailing `/.git` stripped. The slug is `<owner>__<name>` from the origin URL when one exists (both GitHub URL forms), else `<basename>-<first 12 hex of sha256(absolute path)>`, so two repos with the same basename never share `ledger/<repo-slug>.md` or a row id (DEC-79). A cwd outside any repo goes to `ledger/_no-repo.md`. Rows the hook staged in repo ledgers before the sweep was enabled stay there; the learning-ledger skill's existing flush drains them (DEC-64).

**Aggregation (DEC-87, DEC-88).** Slugs cluster with a fixed fuzzy threshold (`HARVEST_SWEEP_FUZZY`, default 2, independent of the hook's `HARVEST_FUZZY_THRESHOLD`). Fuzzy matching applies only when both slugs are at least 12 characters long and their lengths differ by 2 or less; shorter slugs match exactly. The first slug seen in a cluster is its canonical name and stays so. Occurrences count lead groups, not raw sessions: a lead group is the `lead_session_id` when known (a claude lead with its folded subagents, a Devin worker attributed to its lead) and the session's own id otherwise. A group's count is the largest per-session total (the sum over that session's extract keys) among its sessions, and a pattern's occurrences are the sum of its group counts over sightings newer than `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (default 14). A canonical pattern is a candidate when its occurrences reach `HARVEST_SWEEP_MIN_PATTERN_COUNT` (default 3) and it has no blocking `proposed.jsonl` entry. `kind: ask` qualifies at 1. One sighting of count 1 never qualifies. The manifest and the report also show the raw session count beside the group count. Re-propose rule: a `REPORTED` entry stops blocking after 14 days if the pattern's occurrences grew by at least the threshold since its `ts`.

**Annotator (DEC-51, DEC-59, DEC-77).** For each candidate, code runs, as argv lists through `subprocess.run` and never through a shell, `bin/precedent find --surface inventory --json "<slug words>"` and `lib/classify/lane-classify.sh classify "<slug words>: <first evidence line>"`. It picks the home with wrap step 7b's rule: when the hit list holds a code home and a prose home (a memory note, a research file, a handoff: the kinds `report-lint.sh`'s `PROSE_TARGET_RE` matches), the top code hit wins. It records that hit (`ENHANCE <home>`) or `NEW (precedent: nothing matched)`, and the lane. When a candidate's hits are all prose, its home is the top prose hit and the report adds one `- PROSE-ONLY: <slugs>: only prose homes matched; phase 1 reports and builds nothing` bullet, the lint's escape for an all-prose `**Built:**`. The candidate is `REPORTED` with `reported: phase 1 reports only`. Nothing is built.

**Report (DEC-56).** Code renders `runs/<run-id>/report.md` in wrap's step 9 grammar and runs `lib/wrap/report-lint.sh` once:

- `## Harvest sweep: <run-id>`; `Needs you: NOTHING` unless a source hit rc 5 (then `UNBLOCK <source>: <error>`) or the lag rule fired (then `DECIDE raise harvest.max_sessions_per_run or lower schedule_hours: <source> lag above 24h two runs running`).
- `What happened`: one bullet with sessions read per source, trivial counts, learnings staged, candidates found.
- `Shipped` and `Left alone`: `- NOTHING` (phase 1 writes no repo).
- `**Built:**`: one `- REPORTED <slug> ENHANCE <home>: <hit> (lane=<lane>, reported: phase 1 reports only)` or `- REPORTED <slug> NEW (precedent: nothing matched): <slug> (lane=<lane>, reported: phase 1 reports only)` bullet per candidate, plus the `PROSE-ONLY:` bullet when the annotator emitted one, or `NOTHING: no candidates`.
- `**Seam:** SKIPPED: the sweep runs no seams in phase 1`.
- `FYI`: `STATE` rows for each source's lag (eligible unread count and oldest age), quarantines and lifts, limit holds, source failures, and the queued-learnings count with the flush path; `INCIDENT` rows for a failed probe.
- An overlay section after `FYI`, `**Learnings staged:**`, one bullet per row staged this run (`<slug> (<kind>, <home>) -> ledger/<repo-slug>.md`).

A lint failure is a renderer bug: the findings are appended to the report and the rc is 3. Then `gate-ledger.sh record harvest-sweep-<run-id> harvest ran "<n> sessions, <l> learnings, <c> candidates reported, lag <h>h"`.

**Flush path (DEC-52, DEC-58).** Today nothing drains a sweep ledger: the learning-ledger skill reads and writes only `ops-toolkit/_meta/learned-ledger.md`, and `commands/wrap.md` has no learned-ledger handling. Two kit verbs close that:

- `python3 <kit>/hooks/harvest.py --flush-list` prints every `queued` row across `$HARVEST_STATE_DIR/sweep/ledger/` as one JSON array, `[{"row_id": "<repo-slug>:<item>", "ledger": <path>, "date", "item", "kind", "home", "why", "evidence", "source", "lead_session_id"}]`, joining each row with its sidecar entry and taking each ledger's `.lock` while it reads. A row with no sidecar entry is listed with `why` and `evidence` null.
- `python3 <kit>/hooks/harvest.py --mark-flushed <row-id> <ref>` flips that row's status to `flushed:<ref>` under the ledger's `.lock` (atomic tmp + `os.replace`). `<ref>` follows the skill's grammar (commit SHA, til slug, or file path). An unknown row id or a row not `queued` exits 1 and changes nothing.

The learning-ledger skill calls both (companion task T23 in the dotfiles repo): list, route each row to its home from its `why` and `evidence` (never from the slug alone; a row with null context stays queued), and mark it flushed. `/kit:wrap distill` reaches the same verbs through its `wrap.after` seam when that seam names the skill. Each sweep run then moves `flushed:` rows into the ledger's `.archive.md` sibling. It calls `cmd_cleanup(ledger)`, which now takes the ledger path as an argument (the `HARVEST_LEDGER` env stays as the CLI default) and holds that ledger's `.lock` for the whole read, archive append, and rewrite, so a concurrent `--mark-flushed` either lands before the archive or after it, never inside it (DEC-73). Dedup still reads the archive. The sweep never marks a row flushed itself.

**Lag, not staleness (DEC-71, DEC-72).** No session is ever marked done without being read. Each run records, per source, the eligible unread sessions it did not take (past the quiet window, not done, not quarantined): their count and the age of the oldest. The report carries that as a `STATE` row. `lag_runs` counts consecutive runs where any source's oldest eligible session is older than `HARVEST_SWEEP_LAG_HOURS` (default 24). At 2 the report adds a `Needs you` `DECIDE` item and the rc is 6; a run under the threshold resets it. After an outage the backlog drains oldest first at up to 80 lead sessions a day. Claude deletes transcripts after its own retention period (30 days by default), so a lag that reaches that age loses sessions to Claude's cleanup, not to the sweep; the lag alarm fires weeks earlier.

**rc contract** (the sweep entry, `harvest_sweep.py --sweep`). When several apply, the lowest non-zero code wins, and the report lists every one. Codes 2 and 4 are reserved for phase 2 (SPEC-358).

| rc | Meaning | Bridge called |
|---|---|---|
| 0 | ran, including `NOTHING` and a limit hold | yes |
| 1 | an auth-shaped extractor failure stopped the run (probe failed, or two sessions failed) | yes |
| 3 | the rendered report failed `report-lint.sh` | yes |
| 5 | a source unreadable (or drifted, DEC-61) for `SOURCE_FAIL_RUNS` consecutive runs | yes |
| 6 | a source's lag above `LAG_HOURS` on two consecutive runs | yes |
| (none) | disabled, no host marker, or `sweep.lock` held: the launcher logs and exits 0 | no |

The launcher calls `python3 <kit>/hooks/harvest_sweep.py --sweep` directly, never through `harvest.sh`, whose `|| true; exit 0` would hide every failure. `harvest.py`'s `_dispatch` routes `--sweep` to the same entry before its `read_payload` fall-through, for manual runs. A disabled or skipped run never calls the bridge, so a job left loaded but disabled goes silent and vps-mon alerts; turning the sweep off for good is `install --uninstall` plus retiring the heartbeat per `job-monitoring-onboarding`.

**Pruning** (each run): `patterns.jsonl` rows older than the pattern window, `proposed.jsonl` entries older than 90 days, quarantine entries and `seen{}` entries older than 30 days, `extract/` files and `runs/` dirs older than 30 days. Pruning never touches an unread session. One task, T13b, owns every pruning rule (DEC-90).

### Data model changes

New kit state under `$HARVEST_STATE_DIR/sweep/` (table above). No repo file format changes. `ledger/<repo-slug>.md` reuses the learned-ledger table, so `--cleanup` and the existing flush read it unchanged.

### API changes

- `hooks/harvest.py --flush-list` and `hooks/harvest.py --mark-flushed <row-id> <ref>` (above).
- `hooks/harvest_sweep.py --status` prints one line for the newest run: `<report path> candidates=<n> queued=<m>`, or `none` when no run exists.
- `hooks/harvest_sweep.py --sweep [--dry-run] [--since <iso>]`, also reachable as `harvest.sh --sweep` for a human (rc hidden there). `--dry-run` reads and extracts, prints the manifest, and writes nothing but the raw output cache. `--since` sets a one-off hwm for a manual backfill.
- The sweep is ACTIVE on a host when `harvest.enable` is true AND the `installed` marker exists on that host (DEC-27). The operator `kit.toml` may sync across hosts; the marker does not.
- `harvest.sh` auto modes (no-arg, `--lab-log`, `--stop-trigger`) exit 0 without work when `HARVEST_SWEEP_CHILD=1`, or when the sweep is active on this host and `harvest.hook_when_sweep_on` is false. `--cleanup` is unaffected. The shim reads the keys with `kit_config_get_root`.
- `/kit:wrap`: `wrap.distill` accepts `true`, `false`, or `harvest`. With `harvest` on a host where the sweep is active: the landing half runs, no seam key is read, and the report says `**Built:** SKIPPED: distill runs in the harvest sweep` and `**Seam:** SKIPPED: distill runs in the harvest sweep`, plus a `FYI` `STATE` row naming the knob and saying that in phase 1 the sweep reports candidates and builds none, and a second `STATE` row with the `--status` line: the newest sweep report's path, its candidate count, and the queued-learnings count, so the report gets seen (DEC-81). With `harvest` on a host where it is not active: wrap distills as with `true` and prints a `STATE` row saying the sweep is not installed here. The word `distill` in the invocation wins for that one run, and the `FYI` says the sweep will also see the session (DEC-15). Its `wrap.after` flush reaches the sweep ledgers through the learning-ledger skill's use of `--flush-list` (DEC-58).
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

Tuning constants are env-overridable and not config: `HARVEST_SWEEP_MIN_MESSAGES` (6), `HARVEST_MAXCHARS` (12000, shared with the hook), `HARVEST_SWEEP_QUIET_MINUTES` (30), `HARVEST_SWEEP_MIN_PATTERN_COUNT` (3), `HARVEST_SWEEP_PATTERN_WINDOW_DAYS` (14), `HARVEST_SWEEP_FUZZY` (2), `HARVEST_SWEEP_LAG_HOURS` (24), `HARVEST_SWEEP_MAX_SCAN` (2000), `HARVEST_SWEEP_QUARANTINE_AFTER` (3), `HARVEST_SWEEP_SOURCE_FAIL_RUNS` (3), `HARVEST_SWEEP_DRIFT_MIN_SCANNED` (10), `HARVEST_SWEEP_LAUNCH_RECORD`.

Launchd deploy under `deploy/macos/harvest-sweep/`, copying `lib/sync/deploy/macos/`:

- `harvest-sweep`: the launcher. `#!/bin/bash`, no `.sh`, launchd-safe PATH, optional `~/.config/harvest-sweep/env` for per-machine PATH or Claude auth settings. Phase 1 needs no GitHub or git credential. It re-checks that the sweep is active each run and exits 0 with a log line otherwise. It logs a start line and an `end rc=<n>` line to `~/Library/Logs/dwarves-kit/<label>.log`, calls `harvest_sweep.py --sweep` directly, then runs `~/.config/harvest-sweep/bridge <rc> <report path>` best-effort, passing `-` when `report.md` is missing.
- `harvest-sweep.plist.tmpl`: `ProgramArguments[0]` is the launcher's absolute path. Rendered `__LABEL__`, `__KIT__`, `__HOME__`, `__INTERVAL__`.
- `install [--label L] [--apply]`: dry run by default, `--label` defaults to `harvest-sweep`; the Mini installs `mini.harvest-sweep`, a prefix already in vps-mon's `OWNED_PREFIXES` (DEC-13). It refuses unless `harvest.enable` is true. `--apply` renders the plist, writes the `installed` marker, and bootstraps the agent.
- `install --uninstall`: `launchctl bootout` the label, then removes the two files the installer wrote: the plist and the `installed` marker. The host goes back to non-sweep behavior at once (the hook runs again, wrap distills again). It leaves `cursor.json`, the sweep ledgers, `patterns.jsonl`, `proposed.jsonl`, `extract/`, and `runs/` in place, and prints their path, the count of queued learnings, the size of `extract/`, and a purge command for `extract/` (`rm -rf '<state>/sweep/extract'`) that it does not run. A later install resumes from the same cursor; the operator flushes the ledgers through the flush path (DEC-47, DEC-69).

Monitoring (consumer side, ops-toolkit): the bridge's source lives at `ops-toolkit/tools/harvest-sweep-deploy/bridge` (the deploy-follows-source convention for a third-party tool, `tools/<x>-deploy/`), with its rebuild runbook beside it, and is installed to `~/.config/harvest-sweep/bridge`; T21 writes it (DEC-66). It pings the vps-mon heartbeat when rc is 0 and sends a fail ping otherwise. The URL lives in `/etc/vps-mon/harvest-sweep-heartbeat-url`, `hb_id` is the discovered label, the interval is `schedule_hours`, and the grace is 2x. The catalog link follows `job-monitoring-onboarding`. The kit ships no endpoint or secret.

## Task Breakdown

Each task touches at most five files and carries one mechanism. Tests go in the harvest section of `tests/test-hooks.sh`; fixtures go under `tests/fixtures/harvest-sweep/`.

**Order (DEC-65, DEC-90).** T2 to T14, T13b, and T22 all edit `hooks/harvest_sweep.py`, and T1, T9, T14, and T22 all edit `hooks/harvest.py`, so those tasks run serially and are never fanned out to parallel workers. Dependencies: T1 before T9 and T22; T5a before T5b and T7a; T7a before T7b; T9 before T22; T5a, T7b, T10, and T11 before T13b; T10, T11, T12, and T13b before T13; T5a to T13b before T14; T14 before T16; T15 and T16 before T17; T1 to T19 and T22 before T20; T20 before T20b; T20b and T22 before T23; T23 and T24 merged before T21.

### Phase 1a: shared pieces and sources

- [x] T1 (DONE, commit eed75870, verified): shared stager. Factor `_stage_candidates` out of `_harvest_payload` in `hooks/harvest.py`. Files: `hooks/harvest.py`, `tests/test-hooks.sh`. AC: every existing harvest test passes unchanged.
- [x] T2 (DONE, commit 3d6309de, verified): claude adapter. Lead plus subagents interleaved by timestamp, the 60/40 render budget, the `seen{}` delta key, self-harvest drop, min-messages skip. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a lead fixture, two subagent fixtures. AC: the claude parts of AC1.
- [x] T3 (DONE, commit 36e49bc7, verified): devin adapter. Read-only open, `working_directory` as cwd, `hidden` skip, main-chain walk with fallback, `system` drop, source failure `STATE` row and `source_fail`. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, `tests/fixtures/harvest-sweep/make-devin-db.sh`. AC: the devin parts of AC1 and AC26; AC14.
- [x] T4 (DONE, commit ab86a903, verified): launch-record attribution. Brief-path match, nearest `ts`, null on no match. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a `launches.jsonl` fixture. AC: the attribution part of AC1.

### Phase 1b: cursor and extraction

- [ ] T5a: selection. hwm, `done{}`, `seen{}`, quiet window, scan cap, `max_sessions_per_run`, trivial and filtered sessions marked done outside the cap, oldest-first order, atomic writes. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC6, AC25, the `seen{}` part of AC20.
- [ ] T5b: lag and drift. Per-source lag, `lag_runs`, the all-trivial drift rule, `--since`. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC20, AC21.
- [ ] T6: extractor call. `(ok, stdout, stderr)`, `extract_json_object`, the default flags (`--tools ""`, `--strict-mcp-config`, `--no-session-persistence`), extractor cwd and child env, the raw output cache with atomic writes, its modes, and the unparseable-file rule, the 100-slug prompt cap. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a stub extractor fixture. AC: the argv part of AC22; AC24; AC30.
- [ ] T7a: failure classes. The limit hold, the probe, the auth stop, and fail counts on every other path. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC4, AC27, the rc 1 part of AC5b.
- [ ] T7b: quarantine. Quarantine at the threshold and its lift on new activity. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC5, AC5b.
- [ ] T8: sanitizing. Credential-shape redaction (the full prefix list), slug charset, evidence and reason cuts, the `stage1.log` content rule and mode. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, an injection-text fixture, a credential-shape fixture. AC: AC9, the redaction part of AC22.

### Phase 1c: learnings, patterns, report

- [ ] T9: sweep ledgers. Repo-slug walk and naming, `_stage_candidates` with `extra_known` into `ledger/<repo-slug>.md`, the row-context sidecar, repo files read only when present and locks opened without `O_CREAT`. Files: `hooks/harvest.py` (the `extra_known` parameter), `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a deleted-worktree cwd fixture, a same-basename repo pair fixture. AC: the slug part of AC1; AC11; the slug part of AC26; AC29.
- [ ] T10: pattern aggregation. `patterns.jsonl` under its lock keyed by (canonical, session, extract key), lead-group counting, fuzzy clusters with the length and 12-character rules, canonical slugs, window, threshold, `ask`. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC7.
- [ ] T11: annotator. Precedent and lane per candidate through argv lists, the code-home-wins rule, the `PROSE-ONLY:` bullet, `proposed.jsonl` with the re-propose rule. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`, a stub `bin/precedent` fixture, a shell-metacharacter evidence fixture. AC: AC15, AC18, AC23.
- [ ] T12: lint flag. `sweep_report` in `lib/wrap/report-lint.sh` with its fixtures. Files: `lib/wrap/report-lint.sh`, `tests/test-hooks.sh`, three report fixtures. AC: AC10.
- [ ] T13: report and rc. Render the report, lint once, the gate-ledger record, the rc contract (including rc 6). Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC12.
- [ ] T13b: pruning. Every age rule in one place: `patterns.jsonl` by window, `proposed.jsonl` at 90 days, quarantine and `seen{}` entries at 30 days, `extract/` and `runs/` at 30 days; never an unread session. Files: `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC31.
- [ ] T14: entry. `--sweep`, `--dry-run` (which also takes `sweep.lock`), `--status`, `sweep.lock`, and the `_dispatch` route in `harvest.py`. Files: `hooks/harvest_sweep.py`, `hooks/harvest.py`, `tests/test-hooks.sh`. AC: AC2, AC3, the lock part of AC4, the `--status` part of AC28; the After state dry run.
- [ ] T22: flush lifecycle. `harvest.py --flush-list` joined with the sidecar, `--mark-flushed <row-id> <ref>`, `cmd_cleanup(ledger)` with the ledger argument and the lock held throughout, and the sweep run's per-run archive call. Files: `hooks/harvest.py`, `hooks/harvest_sweep.py`, `tests/test-hooks.sh`. AC: AC17.

### Phase 1d: config, hook, deploy, wrap

- [ ] T15: config and hook gate. The `[harvest]` table, the host-marker check, and the `harvest.sh` gate with `HARVEST_SWEEP_CHILD`. Files: `kit.toml`, `hooks/harvest.sh`, `tests/test-hooks.sh`. AC: AC8.
- [ ] T16: launcher and plist template. Files: `deploy/macos/harvest-sweep/harvest-sweep`, `deploy/macos/harvest-sweep/harvest-sweep.plist.tmpl`, `tests/test-hooks.sh`. AC: the launcher part of AC4 (rc to the stub bridge, skips without a bridge call, `-` for a missing report); AC19.
- [ ] T17: installer. `--label`, `--apply`, `--uninstall`, the marker. Files: `deploy/macos/harvest-sweep/install`, `deploy/macos/harvest-sweep/README.md`, `tests/test-hooks.sh`. AC: AC13.
- [ ] T18: wrap knob. `wrap.distill = "harvest"` with host scoping, the explicit-word override, and the `--status` `FYI` row. Files: `commands/wrap.md`, `kit.toml` (the `[wrap]` comment), `MANUAL.md`, `tests/test-meta.sh`. AC: the wrap part of AC10; the wrap part of AC28; test-meta asserts the three states in wrap.md.
- [ ] T19: ADR-0034 amendment to decisions 6 and 9. Files: `docs/decisions/0034-harness-loop-taxonomy.md`. AC: the amendment names the label, the cadence, and why kit-weekly does not carry it, and records that the kit owns the template, launcher, and installer while the instance and the heartbeat bridge stay consumer-side (the `board-sync-cron` precedent).
- [ ] T23 (companion, dotfiles repo, its own PR): the learning-ledger skill drains the sweep ledgers. File: `dotfiles/home/dot_claude/skills/learning-ledger/SKILL.md`. Insertion point: the top of `## Flush + route (at session close or on request)`, a new first step: run `python3 ~/.claude/dwarves-kit/hooks/harvest.py --flush-list`, route each listed row from its `why` and `evidence` (never from the slug alone; a row with null context stays queued), then run `--mark-flushed <row-id> <ref>` for it instead of editing a file. Amend the rule at about line 141, "Rows from other sessions stay queued", so rows returned by `--flush-list` are eligible whatever session staged them. Also add the sweep ledger dir to `## The three layers` and `## References`. AC: one real `/kit:wrap distill` on the Mini lists, routes, and marks a real sweep row from T20b, recorded in `docs/verification/harvest-sweep.md`.
- [ ] T24 (companion, ops-toolkit repo, its own PR): the heartbeat bridge as a deploy bundle. Folder: `ops-toolkit/tools/harvest-sweep-deploy/` with `bridge` (reads `/etc/vps-mon/harvest-sweep-heartbeat-url`, pings success on rc 0 and fail otherwise, never prints the URL), `README.md` with the rebuild runbook, `tool.toml`, the regenerated `MANIFEST.md`, and `docs/proof-of-done.md`, all in one commit per that repo's rules. AC: the bundle passes that repo's pre-commit and proof gate; the bridge's own test pings a stub URL on rc 0 and a fail URL on rc 1.

### Phase 1e: rollout (Mini, in this order)

- [ ] T20: hand dry runs, no plist. Run `python3 <kit>/hooks/harvest_sweep.py --sweep --dry-run` three times across a day with `sources = "claude devin"`; compare each manifest against a hand review of the same sessions. Run one real extractor call with `--output-format json` and record its input tokens; restate the monthly quota figure from that number. If the default Claude Code system prompt dominates it, set `--system-prompt` to a short extraction prompt in the extractor default and measure again (DEC-84). AC: the comparison and the measured tokens recorded in `docs/verification/harvest-sweep.md`.
- [ ] T20b: one real manual run, no plist. Run `python3 <kit>/hooks/harvest_sweep.py --sweep` once by hand; it writes only kit state. AC: `--flush-list` shows at least one real row, and no repo on the Mini changed.
- [ ] T21: enable and install. Set `harvest.enable = true`, `harvest.sources = "claude devin"`, and `wrap.distill = "harvest"` in the Mini operator `kit.toml`; run `install --label mini.harvest-sweep --apply`; install T24's bridge to `~/.config/harvest-sweep/bridge`; provision the heartbeat; add the catalog link, in that order. AC: two consecutive scheduled runs report clean lint, a gate-ledger line, and a heartbeat ping; vps-mon shows the job monitored, not gap.

The week that follows is SPEC-358's entry condition: every scheduled run rc 0 with a clean lint and a green heartbeat, AND the reports were read, shown by at least one sweep-ledger row marked `flushed:` during the week or at least one reported candidate built by hand (a later run's precedent result for that pattern names the build) (DEC-81).

## After state

- [ ] `python3 hooks/harvest_sweep.py --sweep --dry-run` prints a manifest over new claude and devin lead sessions. (Today: no sweep mode.)
- [ ] A second `--sweep` with no new sessions calls no extractor, creates no `runs/` directory, and leaves `cursor.json`, the sweep ledgers, and `patterns.jsonl` unchanged. Its one log line lands in `~/Library/Logs/dwarves-kit/<label>.log`.
- [ ] With the sweep active and `hook_when_sweep_on = false`, a PreCompact or SessionEnd hook fire spawns no harvest child. (Today: every fire spawns one.)
- [ ] `/kit:wrap` on the Mini with `wrap.distill = "harvest"` prints `**Built:** SKIPPED: distill runs in the harvest sweep` and the lint passes. On a host without the marker it distills and prints a `STATE` row.
- [ ] A sweep report lists staged learnings and REPORTED candidates, each with a precedent result and a lane, and each source's lag; no repo on the Mini changed because of the sweep, and no session was dropped unread.
- [ ] `launchctl print gui/$(id -u)/mini.harvest-sweep` on the Mini shows the job, and vps-mon lists it monitored.

## Acceptance Criteria (global)

- [ ] AC1: adapters. Each fixture source yields the normalized shape. Devin `system` rows are absent from `messages`. Subagent files interleave with the lead by timestamp into one transcript (one extraction), the lead keeps its 60% share of the budget, and a later read of the same session renders only entries newer than `last_ts`. A Devin worker whose first user message names a record's `brief` takes that record's `lead_session`; with no match it stays null. A session whose cwd is under the harvest state dir, including an extractor call's own transcript, is never selected, is marked done, and the hwm moves past it. A deleted-worktree cwd resolves to its main repo's slug.
- [ ] AC2: idempotency. Running `--sweep` twice over the same fixtures leaves the sweep ledger, `patterns.jsonl`, and `proposed.jsonl` byte-identical after the second run, and the second run makes no extractor call.
- [ ] AC3: crash safety. Killing the sweep after a session's staging and before its cursor write, then re-running, stages no duplicate row, double-counts no sighting, and reuses the cached raw output (the stub extractor is called once for that session). No session between the old and new hwm is skipped.
- [ ] AC4: auth stop, rc, and skips. A stub extractor that exits 1 on every call leaves the hwm unchanged, the sweep exits 1, and the launcher passes 1 to a stub bridge. A disabled run, an unmarked host, and a lock-held run exit 0 and never call the bridge.
- [ ] AC5: quarantine, middle session. A stub extractor that fails only for session B (not the oldest), with a passing probe, lets A and C complete; B's fail count rises each run, the hwm never passes B, and B is quarantined on the third run with a `STATE` row. When B's fixture later gains a newer entry, the quarantine lifts and B is extracted.
- [ ] AC5b: quarantine, oldest session. A stub extractor that fails only for session A, the oldest, with a passing probe: each run increments A's fail count, continues past A to B and C, exits 0, and quarantines A on the third run with a `STATE` row; the hwm then moves past A. With a failing probe, the same run stops with rc 1 and A's fail count still rises.
- [ ] AC6: bounds. Twenty-five new lead fixtures plus ten trivial ones: one run extracts 20 and marks the 10 trivial done; the next run extracts 5. With 300 known pattern slugs and 300 proposed slugs, each extractor prompt carries exactly 100 slugs and is at most 19,400 characters (`HARVEST_MAXCHARS` of transcript plus the fixed prompt and slugs). The report carries each source's lag line.
- [ ] AC7: threshold. Two lead groups each sighting a pattern once produce no candidate. A third produces one. One session sighting it with count 3 produces one. One session read in two delta windows, each sighting it with count 2, counts 4; replaying either window does not raise it. Seven Devin workers attributed to one lead, each sighting a pattern once, count 1, and the report shows 7 sessions beside 1 group. An `ask` produces one at count 1. Sightings `commit-hook-false-block` and `commit-hok-false-block` count as one canonical pattern; `fix-lint` and `fix-link` (under 12 characters) stay two; two 14-character slugs whose lengths differ by 3 never cluster.
- [ ] AC8: hook switch and recursion guard. With the sweep active and `hook_when_sweep_on = false`, the no-arg, `--lab-log`, and `--stop-trigger` modes exit 0 without a child. With `enable = false`, or with no host marker, today's behavior holds. `HARVEST_SWEEP_CHILD=1` suppresses all three modes. A project `.kit.toml` setting any `[harvest]` key changes nothing. The stub extractor's argv contains `--setting-sources project` and never `--bare`.
- [ ] AC9: sanitizing. A fixture transcript whose tool output carries shell metacharacters, angle-bracket tags, and an instruction to edit `hooks/ship-gate.sh` reaches `patterns.jsonl`, the ledger, and the report only as a charset-valid slug and an evidence line of at most 200 printable characters without backticks, angle brackets, `$`, or newlines.
- [ ] AC10: wrap and lint. A `## Harvest sweep:` report whose `**Built:**` items are all `REPORTED` passes; the same report with one `BUILT` item fails; the same report without `**Seam:**` fails. A wrap report with both `SKIPPED: distill runs in the harvest sweep` lines passes.
- [ ] AC11: no repo writes. After a fixture run, each fixture repo's main checkout has the same HEAD sha, the same checked-out branch, the same `.git/config`, the same worktree list, and an empty `git status --porcelain`; its `_meta/learned-ledger.md` is byte-identical; no `.lock` file exists in a repo that had none before. An empty run writes no manifest.
- [ ] AC12: report and rc. A fixture run's report passes `report-lint.sh`, lists each staged learning under `**Learnings staged:**`, and writes one gate-ledger line under `harvest-sweep-<run-id>`. A renderer mutated to drop the `**Seam:**` line gives rc 3 with the findings appended. A devin source failing three runs in a row gives rc 5 and a `Needs you` `UNBLOCK` item.
- [ ] AC13: install and uninstall. The dry run renders a plist whose `ProgramArguments[0]` is the launcher path and refuses with `enable = false`. `install --uninstall` removes the plist and the marker; afterwards `harvest.sh` runs its hook modes again and wrap treats `harvest` as not active; the cursor, ledgers, `patterns.jsonl`, `proposed.jsonl`, `extract/`, and `runs/` are still present, and the command prints the queued-learning count and a purge command for `extract/`, which it does not run.
- [ ] AC14: source drift. A devin fixture db with a renamed column yields a `STATE` row and no crash; the claude source still runs; after the third consecutive failing run the rc is 5; one good read resets the count.
- [ ] AC15: annotation. Each candidate in a fixture run carries a precedent result (a stub `bin/precedent` hit gives `ENHANCE <home>`, an empty result gives `NEW (precedent: nothing matched)`) and a lane, and is recorded `REPORTED` in `proposed.jsonl`. The same candidate is not reported again the next run; it is reported again after 14 days only when its occurrences grew by the threshold.
- [ ] AC16: `bash tests/test-hooks.sh && bash tests/test-meta.sh` pass.
- [ ] AC17: flush round trip. A fixture run stages one learning. `harvest.py --flush-list` prints it as JSON with row id `<repo-slug>:<item>`. `--mark-flushed <row-id> <ref>` flips it to `flushed:<ref>` and exits 0; the same call again, and a call with an unknown row id, exit 1 and change nothing. The next sweep run moves the row to `<ledger>.archive.md`, `--flush-list` no longer lists it, and a new session that yields the same learning does not stage it again. With 20 queued rows, a `--mark-flushed` loop run concurrently with the archive step leaves every row either archived as flushed or still in the ledger with its final status: none lost, none duplicated.
- [ ] AC18: prose-only precedent. With a stub `bin/precedent` whose every hit for every candidate is a memory note, the report carries one `PROSE-ONLY:` bullet, `report-lint.sh` passes, and the rc is 0. With a hit list holding a memory note first and a code file second, the candidate names the code file as its home.
- [ ] AC19: launcher log. A launcher run with `HOME` pointed at a temp dir writes a start line and an `end rc=<n>` line to `<HOME>/Library/Logs/dwarves-kit/<label>.log`.
- [ ] AC20: format drift. A claude fixture set of 12 sessions that are all trivial yields a `STATE` row and counts as a source failure; three such runs in a row give rc 5. A `seen{}` entry survives the `done{}` prune by hwm and is dropped only after 30 days.
- [ ] AC21: lag alarm. A run whose oldest eligible unread session is 30h old gives rc 0 with a lag `STATE` row; a second consecutive such run gives rc 6 and a `Needs you` `DECIDE` item; a following run under 24h gives rc 0 and resets the count.
- [ ] AC22: extractor safety. The stub extractor's argv carries `--tools ""`, `--strict-mcp-config`, and `--no-session-persistence`. A fixture whose evidence and reason carry a 40-character hex run and tokens with the `ghp_`, `AKIA`, `sk_live_`, `glpat-`, `AIza`, and `ops_` prefixes, a JWT-shaped string, and a PEM private-key header stores each as `[redacted]` in `patterns.jsonl`, the sidecar (`.rows.jsonl`), and the report. `stage1.log` is mode 0600 and contains none of the fixture's transcript or extractor text.
- [ ] AC23: no shell. With a candidate whose evidence carries `;`, `|`, `&`, single quotes, and double quotes, the stub `bin/precedent` and stub `lane-classify.sh` receive the text as one argv element, byte for byte, and no marker file that a shell-interpreted `;` would create exists afterwards.
- [ ] AC24: cache modes. After a run, `extract/` and its subdirectories are mode 0700 and every cache file is 0600.
- [ ] AC25: no drop after an outage. A fixture of 50 lead sessions spread across a simulated 48h auth outage, then 3 consecutive runs capped at 20: the runs extract 20, 20, and 10, in `last_activity` order, oldest first; afterwards every one of the 50 has a raw output cache file and none was marked done without one.
- [ ] AC26: repo identity. Two fixture repos named `app` under different parents, one with an origin URL and one without, stage into two different `ledger/<repo-slug>.md` files (`<owner>__<name>` and `app-<hash>`), and their row ids never collide. A Devin fixture session with `hidden = 1` is never selected, is marked done, and the hwm moves past it; a visible session's cwd comes from `working_directory`.
- [ ] AC27: limit hold. A stub extractor that prints `usage limit reached` on stderr and exits 1: the run stops extracting, no `fail{id}` rises, the hwm does not move, the report carries a `STATE` row, and the rc is 0. The next run with a working stub resumes at the same session.
- [ ] AC28: visibility. `harvest_sweep.py --status` prints the newest report path with its candidate and queued counts, or `none`. A wrap report fixture in harvest mode carries a `STATE` row holding that line.
- [ ] AC29: row context. A staged learning's sidecar entry holds its redacted `why` and `evidence`, `source: <source>/<session_id>`, and the lead id when known, and `--flush-list` returns them on the row. A run killed between the ledger append and the sidecar write lists the row with null context; the next run's replay fills the sidecar entry without staging the row twice.
- [ ] AC30: cache integrity. A truncated cache file is removed and the session is extracted again with no fail count; a crash mid-write leaves no partial cache file (the temp file is never read). `--dry-run` refuses to start while `sweep.lock` is held.
- [ ] AC31: pruning. Fixture entries past each age limit (patterns past the window, proposed past 90 days, quarantine and `seen{}` past 30 days, `extract/` and `runs/` past 30 days) are pruned in one run; an eligible unread session of any age is not.

## Test plan

Outline. `/kit:test-plan` expands it into the coverage matrix.

| Area | Case | Kind |
|---|---|---|
| adapters | one fixture per source; role drops; interleaved subagents and the 60/40 budget; delta by `last_ts`; devin main-chain walk and null fallback; trivial skip; self-harvest drop for the extractor cwd; deleted-worktree cwd; schema drift `STATE` row and rc 5 | unit |
| attribution | brief match; nearest-ts among several; malformed line; missing file; no match stays null | unit |
| cursor | first run window; second run empty; resumed session read as a delta; tie on last_activity; crash between staging and cursor write; oldest-first drain after an outage with no drop; lag counts; scan cap | unit |
| extractor | probe-confirmed auth stop; two failures stop; single failure continues and counts; oldest-session quarantine; middle-session quarantine; lift on new activity; non-JSON output counts as failure; empty arrays count as success; raw cache reuse | unit |
| aggregation | 2 vs 3 occurrences; in-session count; `ask`; fuzzy canonical cluster; window expiry; proposed block; REPORTED re-propose after growth | unit |
| sanitizing | slug charset; evidence length and stripped characters; injection fixture | unit |
| annotation | stub precedent hit and miss; code home over prose home; all-prose `PROSE-ONLY:` bullet; lane recorded; `REPORTED` only | unit |
| flush verbs | list, mark, double mark, unknown id, archive on next run, no re-stage, concurrent mark during archive | integration |
| context and integrity | sidecar content and null-context repair; cache atomic write and unparseable removal; dry-run lock; lead-group counting; fuzzy length rules; prune in one task | unit |
| limits and identity | limit hold keeps the cursor with rc 0; same-basename repos; devin hidden and working_directory; no-shell argv; cache modes | unit |
| safety | `--tools ""` in argv; credential-shape redaction; 100-slug cap | unit |
| lag and drift | two runs over 24h give rc 6; reset under the threshold; all-trivial source counts as a failure | unit |
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
| reintroduce a drop: mark eligible sessions older than 24h done unread | AC25 all 50 extracted, none dropped |
| drop the evidence character filter | AC9 no angle brackets or backticks |
| remove the `HARVEST_SWEEP_CHILD` check from `harvest.sh` | AC8 child marker |
| read `hook_when_sweep_on` with `kit_config_get` (project toml honored) | AC8 project toml ignored |
| let `sweep_report` accept a `BUILT` item | AC10 sweep with BUILT fails |
| `--flush-list` lists rows of every status | AC17 flushed row not listed |
| drop the archive sibling from sweep dedup | AC17 archived learning not staged again |
| `--mark-flushed` exits 0 on an unknown row id | AC17 unknown row id exits 1 |
| drop the `PROSE-ONLY:` bullet | AC18 lint passes with rc 0 |
| take the first precedent hit instead of the top code hit | AC18 code home wins |
| key sightings by (canonical, session) with `max(count)` | AC7 two delta windows sum to 4 |
| prune `seen{}` with `done{}` by hwm | AC20 `seen{}` survives the hwm prune |
| drop the extractor's `--tools ""` | AC22 argv check |
| never increment `lag_runs`, or never reset it | AC21 rc 6 on the second run, 0 after |
| run `cmd_cleanup` without the ledger lock | AC17 no row lost under a concurrent mark |
| pass the annotator's query through `shell=True` | AC23 marker file absent |
| create `extract/` with the default umask | AC24 modes |
| slug by repo basename only | AC26 distinct ledgers |
| treat a limit-shaped failure as an auth failure | AC27 rc 0 and no fail count |
| drop the `--status` row from wrap's harvest FYI | AC28 wrap fixture |
| stop writing the sidecar | AC29 `why` and `evidence` on the listed row |
| `--flush-list` omits the sidecar join | AC29 fields returned |
| skip the sidecar repair on replay | AC29 null context filled |
| count a failure on an unparseable cache file | AC30 no fail count |
| open a repo `.lock` with `O_CREAT` | AC11 no new `.lock` in the repo |
| count raw sessions instead of lead groups | AC7 seven workers count 1 |
| drop the 12-character fuzzy floor | AC7 `fix-lint` and `fix-link` stay two |
| mark filtered sessions skipped but not done | AC1 and AC26 hwm moves past |
| drop the `sk_live_`, `AIza`, `ops_`, or JWT pattern | AC22 `[redacted]` stored |
| prune `extract/` entries for sessions still unread | AC31 unread session kept |
| skip the redaction pass | AC22 `[redacted]` stored |

## Verification

```
bash tests/test-hooks.sh && bash tests/test-meta.sh
bash lib/config/kit-config.sh selftest
bash lib/wrap/report-lint.sh tests/fixtures/harvest-sweep/report-reported-ok.md
HARVEST_EXTRACTOR=<stub> HARVEST_STATE_DIR=$(mktemp -d) python3 hooks/harvest_sweep.py --sweep --dry-run
```

Rollout proof (T20, T21) goes into `docs/verification/harvest-sweep.md`: the three dry-run manifests against the hand review, `launchctl print` for the label, the vps-mon monitored state, and two scheduled run reports.

## Edge Cases

1. A live session idles past the quiet window and then resumes. It is read, then re-read later from `seen{id}.last_ts` onward. The second read's sightings add to the first's under a new extract key, and its learnings dedup by slug.
2. A subagent file appears after its lead was read. Its entries are newer than `last_ts` (the quiet window guarantees it), so the next read renders them as the delta.
3. The Devin db is locked by a running Devin. The read-only URI read retries once, then counts a source failure for the run with a `STATE` row; the devin cursor does not move.
4. A session's cwd was a worktree that has since been removed. The slug walk strips `/.claude/worktrees/<name>` and walks up to an existing parent.
5. Two sessions share a cwd in a repo with no `_meta/learned-ledger.md`. The sweep ledger for that repo slug is created; nothing is created in the repo.
6. A pattern slug drifts across sessions. The canonical-slug list in the prompt is the first guard, and the fixed fuzzy threshold is the second. A miss splits the count and delays the candidate. It never reports a single sighting.
7. The system clock steps backward. The hwm is compared against source timestamps, so no session is lost: a session with new activity has a changed mtime and is selected again. The delta key has a limit: entries written during the step carry timestamps at or below `seen{id}.last_ts` and are skipped for that session's delta, so the loss is entry-level and bounded by the step size; the session-level guarantee holds (DEC-91).
8. The operator runs `/kit:wrap distill` on the Mini. Both distill the same session. Learnings dedup by slug; wrap may build a candidate the sweep only reported, and the sweep's next precedent result then names wrap's build.
9. `sources` names an agent with no adapter (for example `codex`). That word logs `unknown source` and is skipped; the others run.
10. The operator `kit.toml` syncs to the Air with `wrap.distill = "harvest"`. The Air has no marker, so its wraps keep distilling and its hook keeps running, each saying so in a `STATE` row or log line.
11. A learning is flushed from the sweep ledger, archived by the next run, and later extracted again from a new session. The sweep's dedup reads the archive sibling, so it is not staged twice.
12. Rows the hook staged in a repo ledger before the sweep was enabled stay in that ledger. The learning-ledger skill's existing flush drains them; the sweep only reads them for dedup.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| OAuth expired or keychain locked under launchd | the first extractor call fails and the probe fails; rc 1; fail ping | cursor untouched past the failing session; vps-mon alerts; fix auth per the `launchd-headless-job` recipe; after recovery the backlog drains oldest first at up to 80 a day and no session is dropped unread (AC25) |
| One session breaks the extractor every time | its fail count rises | quarantine after 3 with a `STATE` row, whether or not it is the oldest; lifts on new activity; the run continues |
| Source schema drift (a Devin update) | `STATE` row per run; rc 5 after 3 runs; fail ping | the other sources keep running; fix the adapter; one good read resets the count |
| Recursion storm (the extractor re-fires harvest) | many `harvest` children in `ps` | `--setting-sources project`, `HARVEST_SWEEP_CHILD=1` in the extractor env, and the self-harvest drop for the extractor cwd |
| Hostile transcript text | odd slugs or evidence in the report | the extractor runs with `--tools ""`, so it can only answer; sanitizing and redaction bound what is stored; phase 1 has no actor that follows the text: nothing is built, pushed, or merged |
| Quota burn | Max-plan usage spikes on the 6h cadence | `enable = false`; `max_sessions_per_run`; delta extraction; raw output cache; no call when nothing is new; the quota line above bounds it |
| Load above the cap, or a long outage | lag `STATE` row grows; rc 6 and a `DECIDE` item after two runs over 24h | nothing is dropped; raise `max_sessions_per_run` or lower `schedule_hours`; a lag near Claude's own 30-day transcript retention would lose sessions to Claude's cleanup, which the alarm precedes by weeks |
| Max-plan usage limit hit | limit-shaped extractor stderr; `STATE` row; rc 0 | a hold, not a failure: no fail count, cursor held, no fail ping; a persistent limit surfaces through the lag alarm |
| Claude transcript format drift | every session trivial on a busy source; `STATE` row; rc 5 after 3 runs | treated as a source failure (DEC-61); fix the adapter |
| A flusher routes from a slug with no context | a sweep row flushed to a wrong home | the sidecar carries `why` and `evidence`; T23 routes from them and leaves null-context rows queued |
| Learnings pile up unflushed | the queued-learnings `STATE` row grows run over run | the learning-ledger skill drains them through `--flush-list` and `--mark-flushed` once T23 lands; the sweep never flushes on its own |
| Heartbeat can never go red | job silently broken, monitor green | the launcher calls the sweep entry directly and passes its rc; disabled runs skip the bridge |
| Transcript data to a new provider | Devin transcripts reach Anthropic Haiku | `sources` defaults to `claude`; adding `devin` is an operator decision in root-only config |
| Secret in a transcript | a credential-shaped string in a stored file | the transcript text still reaches Haiku, as the hook's does, and Devin transcripts widen what is sent (DEC-10); every stored output (ledgers, `patterns.jsonl`, the report) passes the credential-shape redaction and the character cut; the raw output cache in `extract/` is not redacted, lives in kit state with mode 0700 and 0600, and is pruned after 30 days |

## Out of Scope

- Building, pushing, opening PRs, or merging from the sweep. That is SPEC-358 (phase 2).
- Changing wrap's landing half. Steps 0 to 6, 8, and 9 stay as they are.
- A Codex adapter. The adapter seam stays; Codex was verified from one `codex exec` rollout only (cli 0.156.1) and is added once an interactive rollout is checked (DEC-26).
- Replacing `session-audit` or `session-intel repeat`. They stay on kit-weekly.
- `bin/reflect`, which proposes from gate and run ledgers, not transcripts.
- Changing the launch record. ops-toolkit #3631 owns its format; the sweep only reads it.
- LAB_LOG drafts from the sweep. The hook's `--lab-log` draft stops with the hook (DEC-3), and wrap step 6's activity line covers the session record (DEC-14).
- An automatic flush. Learnings wait for the learning-ledger skill's flush through the kit verbs (DEC-52, DEC-58); ADR-0034 decision 6 rejects a kit-side auto-flush.
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
- DEC-28: the extraction unit is the lead session with its subagents folded in. Trivial skips do not count against the cap, a scan cap bounds the stat work, and every report shows cursor lag. Its "stale sessions are marked done unread" clause is removed by DEC-71.
- DEC-29: idempotency rests on a raw output cache keyed `<id>@<last_activity>`, `patterns.jsonl` rewritten via tmp + `os.replace` under `patterns.lock`, and a fixed sweep fuzzy threshold with a stable canonical slug per cluster. Its `max(count)` merge is superseded by DEC-60.
- DEC-30: per-session failures quarantine after `QUARANTINE_AFTER` (3) with a `STATE` row. The hwm advances only through a contiguous prefix of done sessions. Its auth rule is replaced by DEC-39; lifting and pruning are DEC-54.
- DEC-31: stage-2 resume, process-group kill, and the lint fix loop. Moved to phase 2.
- DEC-32: cost bounds: delta extraction on re-touch, pruning by age, and a re-propose rule for `REPORTED` entries stay here. The stage-2 spawn threshold and `--max-turns` moved to phase 2.
- DEC-33: the `[harvest]` table is small; other tuning is env-overridable constants; `--source` and the half-interval skip are cut. In phase 1 the table is `enable`, `schedule_hours`, `sources`, `max_sessions_per_run`, and `hook_when_sweep_on`; `max_builds_per_run`, `build_repos`, and `distill_timeout_minutes` moved to phase 2.
- DEC-34: the rendered stage-2 settings file with `env.CLAUDE_PLUGIN_ROOT`, and its ship-gate rationale. Moved to phase 2.
- DEC-35: extracting wrap's distill half into `docs/patterns/distill-build-and-land.md`. Moved to phase 2; phase 1 builds nothing, so wrap.md keeps its text and this spec carries a phase 1 contract table instead.
- DEC-36: the report counts every queued row across the sweep ledgers, and repo ledgers are read under their own `.lock`. Its first-run carry of hook-era rows is dropped by DEC-64.
- DEC-37: `report-lint.sh` gets its own `sweep_report` flag; reusing `follow_report` would drop the Seam rule. Its phase 1 meaning is DEC-57; the full-lane DRAFT rule moved to phase 2.
- DEC-38 (operator): the stage-2 model has no GitHub or push capability, and stage 3 code does every push, PR, and merge. Moved to phase 2.
- DEC-39 (operator): every extractor failure increments `fail{id}`, including on the stop path. A failure counts as auth-shaped only when a second session also fails in the same run or a fixed probe call fails. A bad oldest session is therefore quarantined on its third run instead of stopping every run.
- DEC-40: per-worktree push URL through `extensions.worktreeConfig`. Moved to phase 2.
- DEC-41: stale is measured from `last_success`. Superseded by DEC-71: the stale mechanism is deleted.
- DEC-42: the learnings spawn threshold and the seam-unresolved pause. Moved to phase 2.
- DEC-43: subagent messages interleave with the lead by entry timestamp; the lead keeps a fixed 60% of the character budget; the delta key is `last_ts`, kept in `seen{}` per DEC-60.
- DEC-44: the extractor runs with its cwd under the harvest state dir, so the self-harvest drop covers its own transcripts.
- DEC-45: rc 5 is a source unreadable for `SOURCE_FAIL_RUNS` consecutive runs, and an unreadable source is a `STATE` row every run. rc 4 (stage-3 failure) moved to phase 2.
- DEC-46: the launcher git and GitHub credential contract. Moved to phase 2; the phase 1 launcher needs no GitHub credential.
- DEC-47: `install --uninstall` removes only what the installer wrote (plist and marker in phase 1) and leaves every piece of sweep state in place, printing what remains, so a re-install resumes and nothing queued is lost.
- DEC-48: ship-gate synthesis for code pushes. Moved to phase 2.
- DEC-49: the path denylist. Moved to phase 2.
- DEC-50 (operator): the sweep ships in two phases. Phase 1 (this spec) reads, extracts, counts, stages, and reports; it spawns no model session beyond the per-session Haiku extractor, creates no worktree, pushes nothing, opens no PR, and merges nothing. Phase 2 (SPEC-358) adds building and merging, and starts only after phase 1 runs clean on the Mini for a week.
- DEC-51: in phase 1, code annotates each candidate with the `bin/precedent` result and the `lane-classify.sh` lane (both local, no model), and reports it with `reported: phase 1 reports only`.
- DEC-52: learnings stay queued in the sweep ledgers until the flush runs, and the sweep never marks a row flushed. Corrected by DEC-58: the earlier text assumed the learning-ledger skill and `commands/wrap.md` already read the sweep ledgers, and neither does.
- DEC-53: `last_success` per source and its 30-day floor. Superseded by DEC-71: nothing still needs `last_success`, so it is removed.
- DEC-54: a quarantine lifts when the session's `last_activity` moves past its value at quarantine time; quarantine entries older than 30 days are pruned.
- DEC-55: the quota ceiling at the default caps is 21 Haiku calls a run, 84 a day, and about 2,520 a month. The token figure is corrected by DEC-68.
- DEC-56: code renders the report and lints it once. A lint failure is a renderer bug, reported as rc 3 with the findings appended; there is no model fix loop in phase 1.
- DEC-57: in phase 1, `sweep_report` requires every `**Built:**` item to open with `REPORTED` and keeps the `**Seam:**` requirement.
- DEC-58: two kit verbs drain the sweep ledgers: `harvest.py --flush-list` (JSON of every queued row, each ledger read under its `.lock`) and `harvest.py --mark-flushed <row-id> <ref>` (flips one row to `flushed:<ref>` under the lock; unknown or non-queued rows exit 1). The learning-ledger skill calls them (T23, a companion PR in the dotfiles repo), and `/kit:wrap distill` reaches them through its `wrap.after` seam. Each sweep run archives `flushed:` rows with the existing `--cleanup` logic. The argument is `<ref>`, matching the skill's `flushed:<ref>` grammar.
- DEC-59: the annotator applies wrap step 7b's rule (a code home beats a prose home) and emits a `PROSE-ONLY:` bullet when a candidate's hits are all prose, so a content-only run lints clean instead of returning rc 3.
- DEC-60: the delta key lives in `seen{}`, a per-id map pruned by age (30 days), not by the hwm. Sightings are keyed by (canonical, session, extract key) and SUM across keys; a replay of one key replaces its own row. `max(count)` under-counted a session read in several delta windows.
- DEC-61: a source whose every selected session in a run is trivial, with at least `DRIFT_MIN_SCANNED` (10) scanned, counts as a source failure: a `STATE` row, and it feeds rc 5.
- DEC-62: `stale > 0` on two consecutive runs gives rc 6. Superseded by DEC-72, which keeps rc 6 and the `DECIDE` item but triggers on lag.
- DEC-63: the sweep extractor's default command adds `--tools ""`, which disables every built-in tool (verified in `claude --help`), and `evidence` and `why` pass a credential-shape redaction (hex runs of 32 or more, `sk-`, `ghp_`, `gho_`, `github_pat_`, `AKIA`, `xox` tokens, PEM private-key headers) before storage.
- DEC-64: no first-run carry of hook-era queued rows from repo ledgers; the learning-ledger skill's existing flush drains its own ledger.
- DEC-65: T2 to T14 all edit `hooks/harvest_sweep.py` (and T1, T14, T22 edit `hooks/harvest.py`), so they run serially, never fanned out; the task list declares every dependency.
- DEC-66: the heartbeat bridge's source lives at `ops-toolkit/tools/harvest-sweep-deploy/bridge`, the deploy-follows-source convention for a third-party tool, with its runbook beside it. The existing kit-weekly bridge has no repo source, and this one must not repeat that. Who writes it is changed by DEC-75.
- DEC-67: T19 amends ADR-0034 decisions 6 and 9: the kit owns the template, launcher, and installer; the LaunchAgent instance and the heartbeat bridge stay consumer-side, as `board-sync-cron` already does.
- DEC-68: the extractor prompt carries at most 100 known slugs (50 most recent patterns plus 50 most recent proposed). At the defaults a prompt is at most 19,400 characters, about 4,900 input tokens, so about 12.3M input tokens a month at the caps.
- DEC-69: `install --uninstall` prints, and does not run, a purge command for `extract/`; the launcher log path is pinned by AC19. Its stale-cutoff clause is removed by DEC-71.
- DEC-70: the sweep's dedup also reads each sweep ledger's `.archive.md` sibling, so a flushed and archived learning is never staged again.
- DEC-71 (operator): no session is ever dropped unread. The stale mechanism is deleted: the stale cutoff, `STALE_RUNS`, the 30-day staleness floor, the `stale` count, and `last_success`, which nothing else needed. A capped run advanced `last_success`, so a second run after an outage dropped the undrained backlog; deleting the rule removes the whole class. The one way a session leaves without an extraction is quarantine after repeated failures, which is reported per session and lifts on new activity; the first-run window (DEC-18) sets where reading starts and is not a drop.
- DEC-72: each run reports per-source lag (eligible unread count and oldest age). Lag above `LAG_HOURS` (24) on two consecutive runs gives rc 6 and a `DECIDE` item; a run under it resets the count.
- DEC-73: `cmd_cleanup` takes the ledger path as an argument and holds that ledger's `.lock` through read, archive append, and rewrite; the per-run archive call lives in T22 with the other flush verbs.
- DEC-74: the rollout adds T20b, one real manual `--sweep` before T23, so the companion's check runs on a real row. T5 splits into T5a (selection) and T5b (lag, drift, `--since`).
- DEC-75: the bridge is its own ops-toolkit companion task, T24, owning `tools/harvest-sweep-deploy/` with `tool.toml`, the regenerated `MANIFEST.md`, `README.md`, and a proof in one commit; T21 keeps the kit install, enable, heartbeat provisioning, and catalog link.
- DEC-76: the extractor's default adds `--strict-mcp-config` and `--no-session-persistence`, both present in `claude --help` on the Mini. The cwd drop stays as a second guard.
- DEC-77: every annotator subprocess runs from an argv list, never a shell.
- DEC-78: `extract/` is created 0700 and its files 0600.
- DEC-79: the repo slug comes from `git rev-parse --path-format=absolute --git-common-dir`, named `<owner>__<name>` from the origin URL when there is one, else `<basename>-<12 hex of the path hash>`. The Devin adapter reads cwd from `working_directory` and skips `hidden = 1` sessions, since the column's meaning is undocumented.
- DEC-80: a limit-shaped extractor failure (usage or rate limit, the 5-hour window) is a hold: `STATE` row, cursor held, no fail count, rc 0, so no fail ping. Only auth-shaped failures stop with rc 1. A persistent limit surfaces through the lag alarm.
- DEC-81: in harvest mode wrap's `FYI` carries a `STATE` row from `harvest_sweep.py --status` (newest report path, candidate count, queued-learnings count). SPEC-358's clean-week entry condition also requires that the reports were read: at least one sweep row marked `flushed:` during the week, or one reported candidate built by hand.
- DEC-82: raw output cache files are written through a temp file and `os.replace`; an unparseable cache file is removed and re-extracted without a fail count; `--dry-run` takes `sweep.lock`.
- DEC-83: each sweep ledger has a `rows.jsonl` sidecar keyed by row id, holding the redacted `why` and `evidence`, `source: <source>/<session_id>`, and the lead id. `--flush-list` returns them, and the sidecar write is idempotent and repaired on replay. The ledger table's five columns dropped the extractor's reason, which left a flusher only a slug. T23 amends the skill's "rows from other sessions stay queued" rule and routes from context, never from the slug alone.
- DEC-84: T20 measures one real extractor call's input tokens with `--output-format json` and restates the quota from it; `--system-prompt` is the lever if Claude Code's default system prompt dominates.
- DEC-85: `_stage_candidates` takes an explicit `extra_known` list. Per repo slug the sweep passes the sweep ledger's archive, the repo's `_meta/learned-ledger.md`, and its archive; `glossaries` is the repo's `learning/*/GLOSSARY.md`.
- DEC-86: repo files are read only when they exist, and a repo `.lock` is opened only when it exists, without `O_CREAT`; the sweep never creates a file in a repo.
- DEC-87: fuzzy clustering applies only to slugs of 12 or more characters whose lengths differ by 2 or less.
- DEC-88: occurrences count lead groups (a lead with its subagents and its attributed Devin workers counts once, at its largest per-session total); the report shows the raw session count beside it. This gives launch-record attribution (T4) its effect on counting.
- DEC-89: redaction also covers `sk_live_`, `rk_live_`, `AIza`, `glpat-`, `ops_`, and JWT-shaped strings; `stage1.log` holds counts, ids, and error classes only, mode 0600.
- DEC-90: T7 splits into T7a (limit hold, probe, auth stop, fail counts) and T7b (quarantine and lift); every pruning rule moves into T13b; the serial order and dependencies are restated.
- DEC-91: the delta key's clock-step limit: a backward step can skip entries written during the step for that session's delta; a session with new activity is still selected again.

## Open questions

(none; design questions were resolved at approval, in the design critique, in validation rounds 1 and 2, and in phase 1 validation, see DEC-11 to DEC-91; phase 2's open items live in SPEC-358)
