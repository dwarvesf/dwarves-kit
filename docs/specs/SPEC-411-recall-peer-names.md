# Spec: recall peer names

Generated: 2026-10-19
Status: DRAFT
Lane: full
Depth: standard (the one unknown, where the harness keeps live-session identity, is settled by the live samples in `## Grounding`)
References: `lib/session/recall/session_recall.py` `resolve_tail_target` and `_clean_ctrl` (copy the read-only, untrusted-input handling for every registry field); `opening_ask` and `SECRET_SHAPE_RE` (copy the redaction applied to a free-text field before it reaches a pasted view).

## Problem

`session recall <terms> --sessions` lists matching sessions by transcript id, for example `8e854ca4-0bae-44b7-82d9-e0c5d818f5f3`. To message a live peer, the SendMessage tool needs the harness peer NAME, for example `ops-toolkit-7b`, which the ListAgents tool shows. Nothing maps the id to the name today. One session grepped the transcript for the name (the name is not in it) and then guessed from start times. A guess can deliver a message to the wrong session.

## Terms

none (the kit coins no term; `session registry` and `peer name` are harness vocabulary, defined once in `### Interfaces`).

## Solution

### Approaches considered

- A. Read the harness session registry `~/.claude/sessions/<pid>.json`. Join its `sessionId` to the transcript basename. Show `name` only when `ps` confirms the pid is alive with the same start time. Tradeoff: the file is undocumented harness state, so its shape can change in an upgrade.
- B. Match process cwd plus start time to the transcript's first timestamp (the guess the session fell back to). Tradeoff: wrong by construction. All 8 sampled live sessions share one cwd. Pid 67919 started 12 hours before its current transcript began, after a `/clear` or a resume.
- C. Ask each peer over its messaging socket `/tmp/cc-socks/<pid>.sock`. Tradeoff: an undocumented wire protocol, and a write into another session's socket from a read-only tool.
- D. Call ListAgents. Rejected: it is a harness tool, not reachable from a CLI. Its rows also carry names, not transcript ids, so it cannot do the join.

### Chosen approach + why

A. It is the only source that holds both keys in one record, with evidence for all 8 live sessions (`## Grounding`). B trades correctness away. C trades the read-only contract away. D does not exist from a CLI. The undocumented-shape risk is handled fail-closed: a row with no confirmed live peer shows nothing extra, and a registry that stops parsing prints one stderr note.

### Extensibility & boundaries

- Load-bearing dimension: the number of live sessions on the host (8 sampled). The registry is read once per `--sessions` run: one `listdir` plus one small JSON read per `<digits>.json` file. `ps` runs only for registry entries whose `sessionId` matches a printed row, so the `ps` count is capped by `--limit` and is usually 0 to 3.
- Units, each testable alone:
  - `read_registry(dir) -> {sessionId: entry}` parses and type-checks registry files and skips anything malformed.
  - `proc_start_utc(pid) -> str | None` runs one `ps` per pid under `TZ=UTC` and normalizes whitespace.
  - `live_peer(entry) -> dict | None` returns the peer only when the pid's start matches `procStart`.
  - `render_sessions` gains one optional column. The JSON payload gains one key per row.

### Architecture

See `## Design`.

## Picture

```
 session recall <terms> --sessions
            |
            v
  rows: (mtime, ~/.claude/projects/<slug>/<sid>.jsonl, hits, ask)   [today]
            |
            |  sid = basename without .jsonl
            v
  read_registry(~/.claude/sessions)  -- only ^[0-9]+\.json$ , never *.key
            |   {sessionId -> {pid, name, status, procStart, pidDomain}}
            v
  sid in registry? --no--> row unchanged
            | yes
            v
  TZ=UTC ps -o lstart= -p <pid> == procStart ? --no--> row unchanged
            | yes
            v
  row + "[live: <name> <status>]"  (+ ", this session" / ", name not unique")
```

## Design

### Approaches considered + chosen

See `## Solution`. No new tradeoff surfaces in the design view.

### Diagram

The `## Picture` flowchart is the decision path. The only new data edge in the system is `session-recall --reads--> ~/.claude/sessions/<pid>.json` plus one `ps` call per matched pid. Both are read-only.

### ADR link(s)

None. The choice is reversible: the column is additive, and deleting `read_registry` restores today's output byte for byte. No ADR is owed.

### Boundaries & failure modes

Out of bounds: writing to the registry, the `.key` files, or the sockets; peers on another host, in the cloud, or under Remote Control (not in the local registry); mapping an OLD transcript of a live process to that process. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Consumes `~/.claude/sessions/<pid>.json`, one JSON object per live interactive session, written by the harness (sampled at version 2.1.302, `peerProtocol` 1). Fields this spec relies on, each type-checked before use:
  - `pid` (int), `sessionId` (str, equals the CURRENT transcript basename), `name` (str, the SendMessage address), `status` (str, for example `busy` / `idle` / `shell`), `procStart` (str, the process start in C `ctime` format, UTC), `pidDomain` (str, `darwin` on this host).
  - Every other field is ignored. The sibling `<pid>.<hex>.key` files are credentials and are never opened.
- Consumes `TZ=UTC ps -o lstart= -p <pid>`, one line per live pid, padded with trailing spaces. A dead pid prints nothing. A pid out of range makes `ps` exit non-zero.
- Consumes the env var `CLAUDE_CODE_SESSION_ID` (optional) to mark the caller's own row.
- Produces, text mode: a row whose sid has a live peer gains one bracketed column between `hits` and the opening ask: `[live: <name> <status>]`. Suffixes: `, this session` when the sid equals `CLAUDE_CODE_SESSION_ID`, and `, name not unique` when two or more live entries carry the same name (the caller then reads the `[ref]` from ListAgents). A row with no live peer is byte-identical to today's row.
- Produces, JSON mode: each `sessions[]` object gains `"peer": {"name", "status", "pid", "self", "unique"}` or `"peer": null`.
- Produces, stderr: one note, `session-recall: session registry unreadable, peer names omitted`, when the registry dir holds `<digits>.json` files and none of them parse with the required fields. A missing registry dir prints nothing (a non-Claude-Code host).
- Invariants:
  - Read-only. Exit codes are unchanged: a registry failure never changes the exit.
  - A name is shown only after a positive `ps` start-time match. Absence of proof means no name.
  - `name` and `status` pass through `_clean_ctrl` and `SECRET_SHAPE_RE` before output. A name is capped at 300 characters, the SendMessage `to` limit.
  - `pidDomain`, when present, must equal `sys.platform`, or the entry is skipped (the pid would be from another pid namespace).

### Data model changes

None. The registry is read, never written.

### API changes (endpoints, request/response shapes)

The JSON `--sessions` payload gains one key per row (`peer`). This is additive: existing keys and their order are unchanged.

### UI changes (screens, components, interactions)

Text `--sessions` rows gain the optional `[live: ...]` column described above.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: Add `SESSIONS = os.path.expanduser("~/.claude/sessions")` (a module attribute, so tests swap it like `PROJECTS`), `read_registry`, `proc_start_utc`, and `live_peer` to `lib/session/recall/session_recall.py`. Acceptance: `read_registry` opens only `^[0-9]+\.json$` names. It skips non-dict JSON, invalid JSON, files over 64 KB, wrong field types, and a `pidDomain` that differs from `sys.platform`. `proc_start_utc` runs `ps` with `TZ=UTC` in its env, reads stdout whatever the exit code, collapses whitespace, and returns `None` on any `OSError`, timeout (2 s), or empty output. `live_peer` returns a peer only when `proc_start_utc(pid) == procStart` after whitespace collapse.

### Phase 2: Core

- [ ] TASK-2: Wire the peer into the `--sessions` path of `main`: text column and suffixes, JSON `peer` key, the duplicate-name check over live entries only, the own-session mark from `CLAUDE_CODE_SESSION_ID`, the single stderr note. Acceptance: every `## Test plan` row passes. The existing 36 tests still pass unchanged, including the `test_sessions_view_one_line_per_transcript_newest_first` row regex.

### Phase 3: Polish

- [ ] TASK-3: Update `lib/session/recall/README.md` `--sessions` usage (the column, its meaning, that names cover local live sessions only, that an old transcript of a live process shows no name) and `docs/proof-of-done.md`. Acceptance: the README example shows one `[live: ...]` row, and the proof carries the real recorded output of `## Verification`.

## After state

- [ ] `session recall <terms> --project ops-toolkit --sessions` prints `[live: <name> <status>]` on each row whose transcript is the current transcript of a live local session. (Today: no row carries a name.)
- [ ] The same row in `--json` carries `"peer": {"name": ...}`, and a non-live row carries `"peer": null`. (Today: no `peer` key.)
- [ ] A registry entry whose pid is dead, reused (start-time mismatch), or from another `pidDomain` adds nothing to its row, checkable by `## Test plan` rows 2 to 4.
- [ ] No code path opens a `*.key` file in the registry dir, checkable by `## Test plan` row 6.
- [ ] Rows with no live peer are byte-identical to today's output, checkable by the existing sessions-view test passing unmodified.

## Quality requirements

none (`docs/QUALITY.md` does not exist in this repo, and this spec adds no measured quality target).

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality

## Verification

```bash
cd lib/session/recall && python3 -m unittest discover -s tests
bash tests/test-bin-forwarders.sh
bash tests/run-all.sh --changed --time
# live check on a host with peers (read-only):
bin/session recall SendMessage --project ops-toolkit --sessions --limit 5
```

`tests/run-all.sh` does not collect the Python unittest suite, so the first line is the load-bearing check.

## Test plan

All cases live in `lib/session/recall/tests/test_recall.py`. They build a temp registry dir, set `r.SESSIONS` and `r.PROJECTS`, and use the test process's own pid as the alive pid (its real `procStart` comes from the test's own `ps` call, written independently of the module).

| # | Case | Type | Covers | Check |
|---|---|---|---|---|
| 1 | Live entry for `new-session` shows `[live: fixture-peer idle]` | happy | After state 1 | `test_sessions_live_peer_named` |
| 2 | Dead pid (a reaped child's pid) shows no column | negative control | After state 3 | `test_sessions_dead_pid_shows_no_name` |
| 3 | Alive pid, `procStart` `Thu Jan  1 00:00:00 1970` shows no column | negative control | After state 3 | `test_sessions_pid_reuse_shows_no_name` |
| 4 | `pidDomain` `elsewhere` shows no column | negative control | After state 3 | `test_sessions_other_pid_domain_skipped` |
| 5 | Registry `sessionId` that matches no row changes nothing | edge | After state 5 | `test_sessions_unmatched_registry_entry_inert` |
| 6 | A `.key` file in the dir is never opened (spy on `builtins.open`) | negative control | After state 4 | `test_registry_never_opens_key_files` |
| 7 | Bad JSON, non-dict, wrong types: no crash, one stderr note when nothing parses | edge | Interfaces stderr | `test_registry_unreadable_note_once` |
| 8 | Missing registry dir: no note, rows unchanged | edge | Interfaces stderr | `test_registry_missing_dir_silent` |
| 9 | Name with `\x1b`, a newline, and an `sk-` shaped token: cleaned and redacted | edge | Invariants | `test_peer_name_cleaned_and_redacted` |
| 10 | Two live entries share a name: `, name not unique` | edge | Interfaces text | `test_peer_name_not_unique_flag` |
| 11 | `CLAUDE_CODE_SESSION_ID` equals the sid: `, this session` | edge | Interfaces text | `test_peer_self_marked` |
| 12 | `--json`: `peer` object on a live row, `null` elsewhere | happy | After state 2 | `test_sessions_json_peer_key` |
| 13 | Existing row regex unchanged on a non-live row | regression | After state 5 | `test_sessions_view_one_line_per_transcript_newest_first` (unmodified) |

## Edge Cases

1. The caller's own session matches a row: the row is named and marked `, this session`, so the caller does not message itself.
2. A live process ran `/clear` or resumed: the registry carries only the CURRENT transcript id (pid 67919 in `## Grounding`). An older transcript of that process gets no name. The README says so. Mapping old transcripts is out of scope.
3. Two live sessions carry the same user-set name: the row says `name not unique`. The bare name would not resolve in SendMessage, and ListAgents shows the `[ref]`.
4. A user-set name holds spaces or a slash (`neko desk for ops/sales` in the sample): printed as is inside the brackets. It is a valid SendMessage `to` (no newline, under 300 characters).
5. An out-of-range pid in a hostile entry: `ps` exits non-zero for that pid only, because `ps` runs per pid. Other rows are unaffected.
6. `ps` missing or hung: `proc_start_utc` returns `None` after the 2 s timeout, and the row shows no name. Absence of proof is never a name.
7. A registry file is replaced mid-read (session exit): `OSError` or JSON error, skipped like any malformed file.
8. A subagent runs the command: `CLAUDE_CODE_SESSION_ID` is the parent's id, so the parent's row is marked `this session`. That is correct, because a subagent's SendMessage goes out under the parent's address.
9. Guarantee inversion, "a name means a live peer": the name is a point-in-time hint. The peer may exit between the print and the send. SendMessage then errors, and the README repeats the existing "hint, never proof" line.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Harness upgrade renames or retypes a registry field | stderr `session registry unreadable, peer names omitted` while sessions are live | Fail-closed: rows print as today. Re-sample one file and update `read_registry`'s field map. |
| Harness moves the registry dir | No `[live:]` column anywhere, no stderr note | Same fail-closed output. The live check in `## Verification` catches it on the next proof run. |
| `procStart` format or zone changes | Every live row loses its name (start-time mismatch) | Fail-closed. `## Test plan` row 1 still passes on fixtures, so the live check is the detector. |
| PID reuse after a crash left a stale file | Start-time mismatch | Name withheld (row 3). |

## Out of Scope

- `--tail` header naming the peer. Not worth it: `--sessions` names the peer first, and `--tail` is the step after.
- Mapping an old transcript of a live process to that process (Edge case 2). No record links the two ids.
- Peers on another host, the cloud, or Remote Control. The local registry does not hold them.
- Any write to the registry, the `.key` files, or the messaging sockets.

## Touches

- lib/session/recall/**

## Decision Log

- DEC-1: Join on the registry `sessionId`, not on cwd or start time. Rationale: one record holds both keys. Rejected: B (shared cwd, `/clear` moves the id), C (socket protocol, write path), D (not reachable from a CLI).
- DEC-2: Liveness is a `TZ=UTC ps -o lstart=` match on `procStart`, not `kill -0` or socket existence. Rationale: `kill -0` passes on a reused pid, and a socket file outlives a crash. A dead pid already fails the `ps` match, so `kill -0` adds nothing.
- DEC-3: One `ps` per matched pid, not one batched call. Rationale: one out-of-range pid fails a batched call for every pid (sampled). Matched pids are capped by `--limit`, so the call count stays small.
- DEC-4: Mark own session from `CLAUDE_CODE_SESSION_ID`. Rationale: the env value matches the registry entry and its `CLAUDE_PID` (sampled). A caller should not message itself.

## Grounding

Every sample is a read-only command run on the Air on 2026-10-19 at harness version 2.1.302. Ids and names are local session labels, not credentials. The `.key` files were listed, never opened.

**Registry location and file set.** `ls -la ~/.claude/sessions/` shows mode `drwx------` with 8 pairs: `<pid>.json` (mode 644, about 550 bytes) and `<pid>.<64 hex>.key` (mode 600, 108 bytes). `ls /tmp/cc-socks/` shows the same 8 pids as `<pid>.sock`.

**Registry shape.** `jq -c 'to_entries|map({k:.key,t:(.value|type)})' ~/.claude/sessions/66402.json`:

```
pid:number sessionId:string cwd:string startedAt:number procStart:string version:string
peerProtocol:number peerFeatures:array kind:string entrypoint:string pidDomain:string
messagingSocketPath:string name:string nameSource:string nameSince:number status:string
updatedAt:number statusUpdatedAt:number
```

**The brief's own example resolves.** `jq -c '{pid,sessionId,name,nameSource,status,pidDomain,procStart}'` over every file, excerpt:

```
{"pid":60642,"sessionId":"8e854ca4-0bae-44b7-82d9-e0c5d818f5f3","name":"ops-toolkit-7b","nameSource":"derived","status":"busy","pidDomain":"darwin","procStart":"Sun Oct 18 08:28:53 2026"}
{"pid":68930,"sessionId":"a728846c-bc8e-4fb2-9cda-61b3b679e903","name":"neko desk for ops/sales","nameSource":"user","status":"shell",...}
{"pid":76888,"sessionId":"10094273-e6fe-494a-9795-63c9d2784e8d","name":"ops-toolkit-18","nameSource":"derived","status":"busy",...}
```

**`sessionId` equals the transcript basename.** For all 8 entries, `~/.claude/projects/-Users-tieubao-workspace-tieubao-ops-toolkit/<sessionId>.jsonl` exists, and the `sessionId` inside its first 400 KB of lines is that same single value.

**The id tracks the CURRENT transcript.** For pid 67919: `startedAt` is `2026-10-18T10:55:43Z`, but its transcript's first timestamp is `2026-10-18T22:43:57.740Z`. The other 7 start within 6 s of `startedAt`. So after a `/clear` or a resume, the registry points at the new transcript (Edge case 2).

**All 8 share one cwd.** Every entry's `cwd` is `/Users/tieubao/workspace/tieubao/ops-toolkit`, which rules out approach B.

**`procStart` is UTC `ctime`.** Local `ps -o lstart=` printed `Sun Oct 18 15:28:53 2026` for pid 60642, against `procStart` `Sun Oct 18 08:28:53 2026` (host zone +07). Under `TZ=UTC`, all 8 matched exactly after whitespace collapse (`match=y` x8).

**`ps` edge behavior (macOS).** `TZ=UTC ps -o pid=,lstart= -p 60642,99990,66402` printed 2 lines with trailing spaces (`60642 Sun Oct 18 08:28:53 2026    `) and exit 0: a dead in-range pid is just left out. `... -p 60642,66402,999999` printed `ps: process id too large: 999999`, no lines, exit 1: one bad pid voids the batch (DEC-3). Not sampled on Linux. The procps `lstart` format is the same `ctime` shape, and `pidDomain` should read `linux` there; both are unsampled assumptions.

**Own session.** Python over `os.environ` and the registry printed `env sid in registry: True | CLAUDE_PID matches that entry pid: True`. Only key names and booleans were printed, never values.

**Baseline.** `cd lib/session/recall && python3 -m unittest discover -s tests` printed `Ran 36 tests in 0.401s` / `OK`.

**Negative-control dry traces.**

- Row 3, PID reuse. Mutation: `live_peer` drops the `== procStart` compare and accepts any pid `ps` lists. Fixture: an entry with `pid = os.getpid()` (alive) and `procStart` `Thu Jan  1 00:00:00 1970`, `sessionId` `new-session`. Path: `read_registry` returns the entry, `proc_start_utc` returns the test process's real start, and the mutated `live_peer` returns a peer, so `render_sessions` appends `[live: fixture-peer ...]`. `test_sessions_pid_reuse_shows_no_name` asserts `"[live:" not in stdout`, so it goes red.
- Row 2, dead pid. Mutation: `live_peer` skips `ps` and trusts the registry. Fixture: an entry whose pid is a `subprocess.Popen(["true"])` child after `wait()`, with any `procStart`. Path: the mutated `live_peer` returns a peer without a `ps` call, so the column prints. `test_sessions_dead_pid_shows_no_name` goes red. Unmutated, `ps -p <reaped pid>` prints nothing, `proc_start_utc` returns `None`, and there is no column.
- Row 4, pid domain. Mutation: `read_registry` drops the `pidDomain == sys.platform` check. Fixture: a live, start-matched entry with `pidDomain` `elsewhere`. Path: the entry survives, and `live_peer` matches the start, so the column prints. `test_sessions_other_pid_domain_skipped` goes red.
- Row 6, key files. Mutation: `read_registry` iterates every name in the dir instead of `^[0-9]+\.json$`. Fixture: the dir holds `4242.json` and `4242.deadbeef.key`. The test wraps `builtins.open` in-process (`main` is called directly, not through a subprocess) and records every opened path. Path: the mutated loop opens the `.key` file and fails to parse it, which is skipped silently, but the spy records it. `test_registry_never_opens_key_files` asserts no recorded path ends in `.key`, so it goes red.
- Row 13, back-compat. Mutation: the column is emitted as `[live: -]` on rows with no peer. Path: the row regex `^\d{4}-\d{2}-\d{2} \d{2}:\d{2}  new-session\s+\d+ hits  ` still matches, so this test would NOT go red. The byte-identity guarantee is held by row 5 instead: `test_sessions_unmatched_registry_entry_inert` compares the full stdout with and without the registry dir and asserts equality. That mutation turns it red.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
