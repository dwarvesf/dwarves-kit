# Spec: recall peer names

Generated: 2026-10-19
Status: DRAFT
Lane: full
Depth: standard (the one unknown, where the harness keeps live-session identity, is settled on macOS by the live samples in `## Grounding`; other hosts are out of scope)
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

A. It is the only source that holds both keys in one record, with evidence for all 8 live sessions (`## Grounding`). B trades correctness away. C trades the read-only contract away. D does not exist from a CLI. The undocumented-shape risk is handled fail-closed: a row with no single confirmed live peer shows no name, and any registry file that fails to parse prints one stderr note.

### Extensibility & boundaries

- Load-bearing dimension: the number of live sessions on the host (8 sampled). The registry is read once per `--sessions` run: one `listdir` plus one bounded read per `<digits>.json` file.
- `ps` cost, one definition: `ps` runs for (a) every registry entry whose `sessionId` matches a printed row, and (b) every other entry whose `name` equals the name of a peer found in (a). Set (a) is capped by `--limit`. Set (b) is usually empty. Both are capped by the registry size and by one overall deadline.
- Units, each testable alone:
  - `read_registry(dir) -> ({sessionId: [entry, ...]}, skipped_count, total_count)` lists, hardens, parses and type-checks registry files.
  - `proc_start_utc(pid, deadline) -> str | None` runs one `ps` per pid and normalizes whitespace.
  - `live_peer(entries, by_name, deadline) -> peer | None` picks the single start-matched entry, flags ambiguity and name collisions.
  - `render_sessions` gains one optional column. The JSON payload gains one key per row.

### Architecture

See `## Design`.

## Picture

```
 session recall <terms> --sessions
            |
            v
  rows: (mtime, ~/.claude/projects/<slug>/<sid>.jsonl, hits, ask)        [today]
            |   sid = basename without .jsonl
            v
  read_registry(~/.claude/sessions)
     names ^[0-9]+\.json$ only (never *.key)
     lstat S_ISREG, size <= 64 KB, open O_NOFOLLOW|O_NONBLOCK
     pid int > 0, typed fields ------- any file skipped --> stderr note (once)
     pidDomain != sys.platform ------> entry skipped
            |   {sessionId -> [entry, ...]}
            v
  sid in registry? ---------no-------> row unchanged
            | yes
            v
  per entry: TZ=UTC LC_ALL=C ps -o lstart= -p <pid> == procStart ?
     (2 s per call, 5 s overall deadline --> unchecked = not matched)
            |
     0 matched -----------------------> row unchanged
     2+ matched ----------------------> row + "[live: ambiguous]"
     exactly 1
            v
  row + "[live: <name> <status>]"
     + ", this session"     sid == CLAUDE_CODE_SESSION_ID, else pid == CLAUDE_PID
     + ", name not unique"  another live entry, printed or not, has the same name
```

## Design

### Approaches considered + chosen

See `## Solution`. No new tradeoff surfaces in the design view.

### Diagram

The `## Picture` flowchart is this spec's design diagram, the decision path including the `pidDomain` skip and the stderr note branch. In `docs/SYSTEM-DESIGN.md` it changes the `c-session` component sheet (L2) by one store node and one edge: `registry` (`~/.claude/sessions/<pid>.json`, kind `store`) and `recallcli --reads, peer names--> registry`. TASK-4 writes that delta. Both are read-only.

### ADR link(s)

None. The choice is reversible: the column is additive, and deleting the registry read restores today's output byte for byte. No ADR is owed.

### Boundaries & failure modes

Out of bounds: writing to the registry, the `.key` files, or the sockets; non-macOS hosts; peers on another host, in the cloud, or under Remote Control (not in the local registry); mapping an OLD transcript of a live process to that process. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Consumes `~/.claude/sessions/<pid>.json`, one JSON object per live interactive session, written by the harness (sampled at version 2.1.302, `peerProtocol` 1). Fields this spec relies on, each type-checked before use:
  - `pid` (`type(pid) is int and pid > 0`, so a bool is rejected), `sessionId` (str, equals the CURRENT transcript basename), `name` (str, the SendMessage address), `status` (str, for example `busy` / `idle` / `shell`), `procStart` (str, the process start in C `ctime` format, UTC), `pidDomain` (str, `darwin` on this host; absent is accepted).
  - Every other field is ignored. The sibling `<pid>.<hex>.key` files are credentials and are never opened.
- Read hardening, per file: the name must match `^[0-9]+\.json$`. `os.lstat` must show `S_ISREG` and a size of at most 64 KB. Open with `os.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)`, re-check `S_ISREG` on `os.fstat`, and read at most 64 KB + 1 bytes. A symlink, a FIFO, a directory, or an oversized file is skipped without blocking.
- Consumes `ps -o lstart= -p <pid>` with env `TZ=UTC` and `LC_ALL=C`, one call per pid. Output is one line padded with trailing spaces. A dead pid prints nothing. A pid out of range makes `ps` exit non-zero. Each call has a 2 s timeout. All calls in one run share a 5 s deadline. A pid not checked before the deadline counts as not matched.
- Consumes the env vars `CLAUDE_CODE_SESSION_ID` and `CLAUDE_PID` (both optional) to mark the caller's own row.
- Matching rule: a row's sid maps to a list of entries. Each entry is `ps`-checked. Exactly one start-matched entry names the row. Two or more give `ambiguous`. Zero give nothing.
- Name uniqueness, one definition: a named peer is `not unique` when any OTHER registry entry passes the `pidDomain` check and the `ps` start-time match and carries the same rendered name, whether or not its transcript is a printed row.
- Name rendering, in this order: (1) `_clean_ctrl`, then replace each `]` and `,` with `?`, so a name cannot forge or close the suffixes; (2) `SECRET_SHAPE_RE.sub("(redacted)")`, a marker with no `]` or `,`; (3) cap at 300 characters, the SendMessage `to` limit. `status` goes through the same three steps.
- Produces, text mode: one bracketed column between `hits` and the opening ask. `[live: <name> <status>]` for a single live peer, with suffix `, this session` when the sid equals `CLAUDE_CODE_SESSION_ID`, or else when the entry pid equals `int(CLAUDE_PID)`, and suffix `, name not unique` per the uniqueness rule. `[live: ambiguous]` when two or more entries match. A row with no live peer is byte-identical to today's row.
- Produces, JSON mode: each `sessions[]` object gains `"peer"`. A single live peer gives `{"name", "status", "pid", "self", "unique"}`. Ambiguous gives `{"name": null, "status": null, "pid": null, "self": false, "unique": false}`. No live peer gives `null`.
- Produces, stderr, at most one line per run: `session-recall: <K> of <M> session registry files unreadable, peer names may be missing` when `K >= 1` of the `M` `<digits>.json` files were skipped for shape, type, size, or file type. When the 5 s deadline cuts the checks, the run appends ` (ps deadline hit)` to that line, or prints it as `session-recall: ps deadline hit, peer names may be missing`. A missing registry dir prints nothing (a non-Claude-Code host).
- Invariants:
  - Read-only. Exit codes are unchanged: a registry or `ps` failure never changes the exit.
  - A name is shown only after a single positive `ps` start-time match. Absence of proof means no name.
  - An entry whose `pidDomain` is present and differs from `sys.platform` is skipped (the pid would be from another pid namespace).

### Data model changes

None. The registry is read, never written.

### API changes (endpoints, request/response shapes)

The JSON `--sessions` payload gains one key per row (`peer`). This is additive: existing keys and their order are unchanged.

### UI changes (screens, components, interactions)

Text `--sessions` rows gain the optional `[live: ...]` column described above.

### Infrastructure changes

None.

## Task Breakdown

Each task writes the `## Test plan` rows it names in `lib/session/recall/tests/test_recall.py`, in the same commit as its code.

### Phase 1: Foundation

- [ ] TASK-1: Add `SESSIONS = os.path.expanduser("~/.claude/sessions")` (a module attribute, so tests swap it like `PROJECTS`) and `read_registry` to `lib/session/recall/session_recall.py`, with the read hardening, the field type checks, the `pidDomain` skip, and the `sessionId -> [entries]` shape. Pin the registry in every existing subprocess test: `r.SESSIONS=<empty temp dir>` in each `-c` snippet, and `HOME=<temp dir>` in the env of each `BIN` call. Tests: rows 4, 6, 7, 8, 14, 15, 16. Acceptance: those rows pass, and the existing 36 tests pass with no real `~/.claude/sessions` read.
- [ ] TASK-2: Add `proc_start_utc` and `live_peer`: the per-pid `ps` call (env `TZ=UTC`, `LC_ALL=C`, stdout read whatever the exit code, whitespace collapsed, `None` on `OSError`, timeout, or empty output), the 2 s per-call timeout and 5 s overall deadline, the exactly-one match rule, the uniqueness rule, and the self marker with its `CLAUDE_PID` fallback. Tests: rows 2, 3, 9, 10, 11, 12, 13. Acceptance: those rows pass.

### Phase 2: Core

- [ ] TASK-3: Wire the peer into the `--sessions` path of `main`: the text column and suffixes, the name rendering order, the JSON `peer` key, and the single stderr line. Tests: rows 1, 5, 17, 18. Acceptance: every `## Test plan` row passes, including row 19 (the existing row-regex test, unmodified apart from the TASK-1 registry pin).

### Phase 3: Polish

- [ ] TASK-4: Update `lib/session/recall/README.md` `--sessions` usage: the column and its suffixes; that names cover local live sessions on macOS only; that an old transcript of a live process shows no name; and that SendMessage resolves names across machines and the cloud, so `name not unique` checks local sessions only and a locally unique name can still collide globally. Add the `registry` node and the `recallcli --reads, peer names--> registry` edge to the `c-session` sheet in `docs/SYSTEM-DESIGN.md`. Write `lib/session/recall/docs/proof-of-done.md`. Acceptance: the README example shows one `[live: ...]` row, the `c-session` sheet carries the node and edge, and the proof carries the real recorded output of `## Verification`.

## After state

- [ ] `session recall <terms> --project ops-toolkit --sessions` prints `[live: <name> <status>]` on each row whose transcript is the current transcript of exactly one live local session. (Today: no row carries a name.)
- [ ] The same row in `--json` carries `"peer": {"name": ...}`, and a non-live row carries `"peer": null`. (Today: no `peer` key.)
- [ ] A registry entry whose pid is dead, reused (start-time mismatch), or from another `pidDomain` adds nothing to its row: stdout equals the no-registry baseline exactly, checkable by `## Test plan` rows 2 to 4.
- [ ] Two live entries with one `sessionId` give `[live: ambiguous]`, never a name, checkable by row 9.
- [ ] No code path opens a `*.key` file in the registry dir, checkable by row 6.
- [ ] Rows with no live peer are byte-identical to today's output, checkable by row 5 (full stdout compared with and without a registry).

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

All cases live in `lib/session/recall/tests/test_recall.py`. They build a temp registry dir, set `r.SESSIONS` and `r.PROJECTS`, and use the test process's own pid as the alive pid. Its real `procStart` comes from the test's own `ps` call, written independently of the module. A "baseline" is the full stdout of the same command with `r.SESSIONS` pointing at an empty dir.

| # | Case | Type | Covers | Check |
|---|---|---|---|---|
| 1 | Live entry for `new-session` shows `[live: fixture-peer idle]` | happy | After state 1 | `test_sessions_live_peer_named` |
| 2 | Dead pid (a reaped child's pid): stdout equals the baseline exactly | negative control | After state 3 | `test_sessions_dead_pid_shows_no_name` |
| 3 | Alive pid, `procStart` `Thu Jan  1 00:00:00 1970`: stdout equals the baseline exactly | negative control | After state 3 | `test_sessions_pid_reuse_shows_no_name` |
| 4 | `pidDomain` `elsewhere`: stdout equals the baseline exactly | negative control | After state 3 | `test_sessions_other_pid_domain_skipped` |
| 5 | Registry `sessionId` that matches no row: stdout equals the baseline exactly | regression | After state 6 | `test_sessions_unmatched_registry_entry_inert` |
| 6 | A `.key` file is never opened: spy on `os.open` and `io.open`, plus a unit assert that the name filter rejects `4242.deadbeef.key` | negative control | After state 5 | `test_registry_never_opens_key_files` |
| 7 | Bad JSON, non-dict, wrong types, `pid` `true`, `pid` `0`: no crash, one stderr line `2 of 3 ...` style when some files skip | edge | Interfaces stderr | `test_registry_partial_unreadable_note` |
| 8 | Missing registry dir: no stderr line, stdout equals the baseline | edge | Interfaces stderr | `test_registry_missing_dir_silent` |
| 9 | Two start-matched entries with one `sessionId`: `[live: ambiguous]`, JSON `peer.unique` false and `name` null | negative control | After state 4 | `test_sessions_duplicate_session_id_ambiguous` |
| 10 | One `sessionId`, a stale dead entry plus a live one: the live one names the row | edge | Matching rule | `test_sessions_stale_duplicate_session_id_named` |
| 11 | Unprinted live entry with the same name: `, name not unique`; the same entry with a dead pid: no flag | edge | Uniqueness rule | `test_peer_name_not_unique_includes_unprinted` |
| 12 | `CLAUDE_CODE_SESSION_ID` equals the sid: `, this session`; unset, with `CLAUDE_PID` equal to the entry pid: `, this session` | edge | Interfaces text | `test_peer_self_marked_with_pid_fallback` |
| 13 | `ps` stubbed to sleep past the deadline: no name, stderr names the deadline, exit 0 | edge | Interfaces `ps` | `test_ps_deadline_fails_closed` |
| 14 | Symlink `4242.json` pointing at a valid entry: skipped | negative control | Read hardening | `test_registry_symlink_skipped` |
| 15 | FIFO `4243.json`: skipped, run returns within 5 s | negative control | Read hardening | `test_registry_fifo_skipped_no_hang` |
| 16 | `4244.json` over 64 KB: skipped | edge | Read hardening | `test_registry_oversized_skipped` |
| 17 | Name `a]b, this session\x1b` plus an `sk-` shaped token: rendered `a?b? this session?` with `(redacted)`, no forged suffix, capped at 300 | edge | Name rendering | `test_peer_name_cleaned_redacted_capped` |
| 18 | `--json`: `peer` object on a live row, `null` elsewhere | happy | After state 2 | `test_sessions_json_peer_key` |
| 19 | Existing row regex unchanged on a non-live row | regression | After state 6 | `test_sessions_view_one_line_per_transcript_newest_first` (registry pinned, assertions unmodified) |

## Edge Cases

1. The caller's own session matches a row: the row is named and marked `, this session`, so the caller does not message itself. When the env session id is stale or absent, `CLAUDE_PID` still marks it.
2. A live process ran `/clear` or resumed: the registry carries only the CURRENT transcript id (pid 67919 in `## Grounding`). An older transcript of that process gets no name. The README says so. Mapping old transcripts is out of scope.
3. One session opened in two terminals (a resume of a live session): two live entries share a `sessionId`. The row says `ambiguous` and names neither.
4. A crash left a stale file with the same `sessionId` as a live entry: the stale pid fails the `ps` match, so the live entry names the row (row 10).
5. Two live sessions carry the same user-set name, whether or not both are printed: the row says `name not unique`. The bare name would not resolve in SendMessage, and ListAgents shows the `[ref]`.
6. A user-set name holds spaces or a slash (`neko desk for ops/sales` in the sample): printed as is. A name holding `]` or `,` prints with `?` in their place, so it no longer equals the address; the caller then reads it from ListAgents.
7. An out-of-range pid in a hostile entry: `ps` exits non-zero for that pid only, because `ps` runs per pid. Other rows are unaffected.
8. `ps` missing or hung: `proc_start_utc` returns `None` after the 2 s timeout, the 5 s deadline caps the total, and the row shows no name.
9. A registry file is replaced mid-read (session exit): `OSError` or JSON error, skipped and counted like any malformed file.
10. A subagent runs the command: `CLAUDE_CODE_SESSION_ID` is the parent's id, so the parent's row is marked `this session`. That is correct, because a subagent's SendMessage goes out under the parent's address.
11. Guarantee inversion, "a name means a live peer": the name is a point-in-time hint. The peer may exit between the print and the send. SendMessage then errors, and the README repeats the existing "hint, never proof" line.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Harness upgrade renames or retypes a registry field | stderr `<K> of <M> session registry files unreadable` while sessions are live | Fail-closed: rows print as today. Re-sample one file and update `read_registry`'s field map. |
| Harness moves the registry dir | No `[live:]` column anywhere, no stderr line | Same fail-closed output. The live check in `## Verification` catches it on the next proof run. |
| `procStart` format or zone changes | Every live row loses its name (start-time mismatch) | Fail-closed. `## Test plan` row 1 still passes on fixtures, so the live check is the detector. |
| PID reuse after a crash left a stale file | Start-time mismatch | Name withheld (row 3). |
| Two registry entries carry one `sessionId` (a resume in a second terminal, or a stale crash file) | Two entries in the list for one sid | Only a single start-matched entry names the row. Two live ones give `ambiguous` (row 9). A stale one drops out (row 10). |
| `ps` slow or hung | Deadline hit, stderr says so | Unchecked entries count as not matched. Run time stays bounded at 5 s plus the transcript walk. |

## Out of Scope

- Non-macOS hosts. The registry and `ps` shapes are sampled on macOS only. Elsewhere the `pidDomain` check skips any entry whose domain differs from `sys.platform`, and the `ps` start-time match must still agree byte for byte, so an unsampled host shows no names rather than wrong ones.
- `--tail` header naming the peer. Not worth it: `--sessions` names the peer first, and `--tail` is the step after.
- Mapping an old transcript of a live process to that process (Edge case 2). No record links the two ids.
- Peers on another host, the cloud, or Remote Control. The local registry does not hold them.
- Any write to the registry, the `.key` files, or the messaging sockets.

## Touches

- lib/session/recall/**
- docs/**

`docs/**` is the narrowest legal prefix for `docs/SYSTEM-DESIGN.md` and `docs/implementation-notes/recall-peer-names.md`. The spec writes no other file under `docs/`.

## Decision Log

- DEC-1: Join on the registry `sessionId`, not on cwd or start time. Rationale: one record holds both keys. Rejected: B (shared cwd, `/clear` moves the id), C (socket protocol, write path), D (not reachable from a CLI).
- DEC-2: Liveness is a `ps -o lstart=` match on `procStart` under `TZ=UTC LC_ALL=C`, not `kill -0` or socket existence. Rationale: `kill -0` passes on a reused pid, and a socket file outlives its process (2 of 10 sockets in `## Grounding`). A dead pid already fails the `ps` match, so `kill -0` adds nothing.
- DEC-3: One `ps` per checked pid, not one batched call. Rationale: one out-of-range pid fails a batched call for every pid (sampled). The checked set is bounded per `### Extensibility & boundaries`, and the 5 s deadline caps the total.
- DEC-4: Mark own session from `CLAUDE_CODE_SESSION_ID`, falling back to `CLAUDE_PID`. Rationale: both env values match the registry entry (sampled). A caller should not message itself.
- DEC-5: Key the registry as `sessionId -> [entries]` and name a row only on exactly one live match. Rationale: a dict keyed by `sessionId` lets a later file silently overwrite an earlier one, and the survivor could be the stale one or one of two live peers.
- DEC-6: Uniqueness counts every live registry entry, printed or not. Rationale: SendMessage resolves a bare name against all sessions, not against the rows a query happened to print.

## Grounding

Every sample is a read-only command run on the Air on 2026-10-19 at harness version 2.1.302. Ids and names are local session labels, not credentials. The `.key` files were listed, never opened.

**Registry location and file set.** `ls -la ~/.claude/sessions/` shows mode `drwx------` with 8 pairs: `<pid>.json` (mode 644, about 550 bytes) and `<pid>.<64 hex>.key` (mode 600, 108 bytes).

**Sockets outlive their process.** `ls /tmp/cc-socks/` shows 10 sockets: the 8 registry pids plus `9886.sock` and `99643.sock`. For both stale pids, `ps -o comm= -p <pid>` finds no process and there is no `~/.claude/sessions/<pid>.json` (DEC-2).

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

**`sessionId` equals the transcript basename.** For all 8 entries, `~/.claude/projects/-Users-tieubao-workspace-tieubao-ops-toolkit/<sessionId>.jsonl` exists, and the `sessionId` inside its first 400 KB of lines is that same single value. No two of the 8 sampled entries share a `sessionId`. The duplicate case (DEC-5) is reasoned from the resume and crash paths and is not sampled.

**The id tracks the CURRENT transcript.** For pid 67919: `startedAt` is `2026-10-18T10:55:43Z`, but its transcript's first timestamp is `2026-10-18T22:43:57.740Z`. The other 7 start within 6 s of `startedAt`. So after a `/clear` or a resume, the registry points at the new transcript (Edge case 2).

**All 8 share one cwd.** Every entry's `cwd` is `/Users/tieubao/workspace/tieubao/ops-toolkit`, which rules out approach B.

**`procStart` is UTC `ctime`.** Local `ps -o lstart=` printed `Sun Oct 18 15:28:53 2026` for pid 60642, against `procStart` `Sun Oct 18 08:28:53 2026` (host zone +07). Under `TZ=UTC`, all 8 matched exactly after whitespace collapse (`match=y` x8). `LC_ALL=C` was not set in that sample. The host locale already prints English day and month names, and the env pin keeps that true under other locales.

**`ps` edge behavior (macOS).** `TZ=UTC ps -o pid=,lstart= -p 60642,99990,66402` printed 2 lines with trailing spaces (`60642 Sun Oct 18 08:28:53 2026    `) and exit 0: a dead in-range pid is just left out. `... -p 60642,66402,999999` printed `ps: process id too large: 999999`, no lines, exit 1: one bad pid voids the batch (DEC-3).

**Own session.** Python over `os.environ` and the registry printed `env sid in registry: True | CLAUDE_PID matches that entry pid: True`. Only key names and booleans were printed, never values.

**Baseline.** `cd lib/session/recall && python3 -m unittest discover -s tests` printed `Ran 36 tests in 0.401s` / `OK`.

**Negative-control dry traces.**

- Row 3, PID reuse. Mutation: `live_peer` drops the `== procStart` compare and accepts any pid `ps` lists. Fixture: an entry with `pid = os.getpid()` (alive) and `procStart` `Thu Jan  1 00:00:00 1970`, `sessionId` `new-session`. Path: `read_registry` returns the entry, `proc_start_utc` returns the test process's real start, and the mutated `live_peer` returns a peer, so `render_sessions` appends `[live: fixture-peer ...]`. `test_sessions_pid_reuse_shows_no_name` asserts stdout equals the baseline, so it goes red.
- Row 2, dead pid. Mutation: `live_peer` skips `ps` and trusts the registry. Fixture: an entry whose pid is a `subprocess.Popen(["true"])` child after `wait()`, with any `procStart`. Path: the mutated `live_peer` returns a peer without a `ps` call, so the column prints and stdout differs from the baseline. `test_sessions_dead_pid_shows_no_name` goes red. Unmutated, `ps -p <reaped pid>` prints nothing, `proc_start_utc` returns `None`, and stdout equals the baseline.
- Row 4, pid domain. Mutation: `read_registry` drops the `pidDomain == sys.platform` check. Fixture: a live, start-matched entry with `pidDomain` `elsewhere`. Path: the entry survives, and `live_peer` matches the start, so the column prints. `test_sessions_other_pid_domain_skipped` goes red.
- Row 5, byte identity. Mutation: the column is emitted as `[live: -]` on rows with no peer. Fixture: a registry entry whose `sessionId` matches no printed row. Path: every row gains the placeholder, so stdout differs from the baseline. `test_sessions_unmatched_registry_entry_inert` asserts equality, so it goes red. Row 19's regex alone would stay green under this mutation, which is why After state 6 points at row 5.
- Row 6, key files. Mutation: `read_registry` iterates every name in the dir instead of `^[0-9]+\.json$`. Fixture: the dir holds `4242.json` and `4242.deadbeef.key`. The test wraps `os.open` and `io.open` in-process (`main` is called directly, not through a subprocess) and records every opened path. Path: the mutated loop opens the `.key` file and fails to parse it, which is skipped, but the spy records it. The test asserts no recorded path ends in `.key`, and that the name filter rejects `4242.deadbeef.key`, so it goes red on either.
- Row 9, duplicate `sessionId`. Mutation: `read_registry` stores `{sessionId: entry}`, so the second file overwrites the first. Fixture: `4242.json` and `4243.json`, both with `sessionId` `new-session` and both start-matched (the test's own pid and its parent's pid, each with its real `procStart`). Path: one entry survives, `live_peer` sees one match and names the row. The test asserts `[live: ambiguous]`, so it goes red.
- Row 14, symlink. Mutation: `read_registry` uses `os.stat` instead of `os.lstat` and drops `O_NOFOLLOW`. Fixture: `4242.json` is a symlink to a valid, start-matched entry outside the dir. Path: the link is followed and the entry names the row. The test asserts stdout equals the baseline, so it goes red.
- Row 15, FIFO. Mutation: `read_registry` drops the `S_ISREG` check and `O_NONBLOCK`. Fixture: `os.mkfifo` at `4243.json` with no writer. Path: `open` blocks forever. The test runs `main` in a subprocess with a 5 s timeout and asserts it returns, so it goes red on the timeout.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
