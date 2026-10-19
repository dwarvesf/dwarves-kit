# Spec: recall peer names

Generated: 2026-10-19
Status: DRAFT
Lane: full
Depth: standard (the one unknown, where the harness keeps live-session identity, is settled on macOS by the live samples in `## Grounding`; other hosts are out of scope)
References: `lib/session/recall/session_recall.py` `resolve_tail_target` (copy the read-only, untrusted-input handling for every registry field); `_redact_prefix` and `REDACT_PREFIX` (on master since #1009; reuse the bounded pre-cut before `SECRET_SHAPE_RE`); `opening_ask` (copy the redaction applied to a free-text field before it reaches a pasted view).

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

A. It is the only source that holds both keys in one record, with evidence for all 8 live sessions (`## Grounding`). B trades correctness away. C trades the read-only contract away. D does not exist from a CLI. The undocumented-shape risk is handled fail-closed: a row with no single confirmed live peer shows no name, a name whose uniqueness cannot be proven is reported as unverified, any failure in the peer phase degrades to today's output, and drift prints one stderr line.

### Extensibility & boundaries

- Load-bearing dimension: the number of live sessions on the host (7 to 8 sampled). The registry is read once per `--sessions` run: one `listdir` plus one bounded read per `<digits>.json` file.
- `ps` cost, one definition: `ps` runs at most once per pid per run (memoized in `ctx`), for (a) every registry entry whose `sessionId` matches a printed row, (b) every other entry whose raw `name` equals the raw name of a peer found in (a), and (c) the caller's own entry, for the drift check. Set (a) is capped by `--limit`. Sets (b) and (c) are usually 0 or 1 entries. All are capped by the registry size and by one 5 s deadline that starts at the first `ps` call.
- Redaction cost: each rendered field is cut by `_redact_prefix(text, cap)` to `max(512, 2 * cap)` characters before `SECRET_SHAPE_RE` runs (DEC-7): 512 for the 110 text cap, 600 for the 300 JSON cap. Only printed peers are rendered. The uniqueness scan compares raw names and runs no regex.
- Units, each testable alone, with pinned shapes:
  - `read_registry(dir) -> Registry`, a plain dict: `{"by_sid": {sid: [entry, ...]}, "by_pid": {pid: entry}, "by_name": {raw_name: [entry, ...]}, "dropped_names": set(raw_name), "skipped": int, "total": int, "dir_error": bool}`. An `entry` is `{"pid", "sessionId", "name", "status", "procStart"}` with raw values.
  - `_ps_lstart(pid, timeout) -> (state, text)`, the one subprocess seam, with `state` in `"alive"`, `"dead"`, `"unchecked"` and `text` the `lstart` line or `None`.
  - `same_start(a, b) -> bool`: whitespace-collapses both sides, then compares.
  - `classify(entry, ctx) -> "matched" | "mismatch" | "dead" | "unchecked"`: the memoized per-pid check. `ctx["ps_cache"]` maps pid to the `_ps_lstart` result.
  - `self_entry(reg, env) -> entry | None`: the caller's own entry (`### Interfaces`, self rule).
  - `live_peer(entries, reg, ctx) -> dict | None`. `ctx` is `{"clock": callable, "deadline": float | None, "env": mapping, "ps_cache": {}, "reasons": {"unchecked": int, "self_mismatch": bool}}`, created once per run. The result is `None` or `{"kind": "named" | "ambiguous", "raw_name", "raw_status", "pid", "self": bool, "uniqueness": "unique" | "not_unique" | "unverified"}`. For `ambiguous`, `raw_name`, `raw_status` and `pid` are `None`, `self` is false, and `uniqueness` is `"unverified"`.
  - `render_peer(peer, mode) -> str | dict`: the hygiene, redaction and cap pipeline. `mode` is `"text"` (the bracketed column) or `"json"` (the `peer` object).
  - `render_sessions(rows, query, limit, dirs=None, peers=None)`: `peers` is `{sid: peer}`. A sid with no entry renders exactly as today.
  - `peer_phase(rows, env) -> (peers, stderr_line | None)`: everything above, called once by `main` inside `try/except Exception`.

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
  main: try peer_phase(rows) ----- any Exception ----> peers = {}, today's stdout,
            |                                         stderr "peer lookup failed (<Class>)"
            v
  read_registry(~/.claude/sessions)
     listdir: missing -> silent, empty registry
              PermissionError / NotADirectoryError / OSError -> dir_error
     re.fullmatch [0-9]+\.json (never *.key)
     lstat S_ISREG, size <= 64 KB, os.open O_NOFOLLOW|O_NONBLOCK, fstat S_ISREG
     JSON object, typed fields, filename pid == body pid,
     any Exception (RecursionError, UnicodeDecodeError, ...) ----> skipped += 1
     pidDomain present and != sys.platform ----> dropped, name -> dropped_names
            |
            v
  [ps phase: deadline = clock() + 5 s at the first call; ps_cache per pid]
  classify(entry): /bin/ps -o lstart= -p <pid>, argv list, no shell,
                   env TZ=UTC LC_ALL=C, 2 s timeout
       alive + same_start  -> matched
       alive, no match     -> mismatch
       exit 1, no output   -> dead
       timeout / error / other exit / stderr text / past deadline -> unchecked
            |
  drift canary: self_entry(reg, env) classified -> mismatch sets self_mismatch
            |
  per printed sid in by_sid:
     0 matched -----------------------------> row unchanged
     1+ matched and matched + unchecked >= 2 -> "[live ambiguous]"
     1 matched, 0 unchecked
            v
  "[live <status>[, <flag>]...: <name>]"
     flag "this session"      entry is self_entry(reg, env)
     flag "name not unique"   another same-raw-name entry matched
     flag "name unverified"   a same-name entry unchecked, or the name in
                              dropped_names, or skipped > 0, or dir_error
            |
            v
  stdout: rows (+ peer-name DATA line when any row has a column)
  stderr (when >= 1 row printed), at most one line
         "peer names may be missing: <reasons>"
          K of M session registry files unreadable        (skipped > 0)
          session registry dir unreadable                  (dir_error)
          K registry entries unchecked (ps timeout, error or deadline)
          this session's registry entry does not match its process start
                                                           (self_mismatch)
```

## Design

### Approaches considered + chosen

See `## Solution`. No new tradeoff surfaces in the design view.

### Diagram

The `## Picture` flowchart is this spec's design diagram: the decision path including the exception guard, the `pidDomain` drop and its unverified trigger, the `ps` states, the deadline, the drift canary, and the stderr branch. In `docs/SYSTEM-DESIGN.md` it changes the `c-session` component sheet (L2) by one store node and one edge: `{id: sessreg, name: session registry, note: "~/.claude/sessions/<pid>.json", kind: store, at: [1, 3]}` (grid cell `[1, 3]` is free on that sheet) and `{from: recallcli, to: sessreg, label: "reads, peer names"}`. TASK-4 writes that delta. Both are read-only.

### ADR link(s)

None. The choice is reversible: the column is additive, and deleting the peer phase restores today's output byte for byte. No ADR is owed.

### Boundaries & failure modes

Out of bounds: writing to the registry, the `.key` files, or the sockets; non-macOS hosts; peers on another host, in the cloud, or under Remote Control (not in the local registry); mapping an OLD transcript of a live process to that process. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Consumes `~/.claude/sessions/<pid>.json`, one JSON object per live interactive session, written by the harness (sampled at version 2.1.302, `peerProtocol` 1). Fields this spec relies on, each type-checked before use:
  - `pid` (`type(pid) is int and pid > 0`, so a bool is rejected, and equal to the filename's digits), `sessionId` (str, equals the CURRENT transcript basename), `name` (str, the SendMessage address), `status` (str, for example `busy` / `idle` / `shell`), `procStart` (str, the process start in C `ctime` format, UTC), `pidDomain` (str, `darwin` on this host; absent is accepted).
  - A file missing any required field (`pid`, `sessionId`, `name`, `procStart`), or with a wrong type, counts as unreadable. `status` absent renders as `?`. Every other field is ignored. The sibling `<pid>.<hex>.key` files are credentials and are never opened.
- Directory read: `os.listdir(SESSIONS)` inside `try`. `FileNotFoundError` means an empty registry and no stderr (a non-Claude-Code host). `PermissionError`, `NotADirectoryError`, and any other `OSError` set `dir_error` and give an empty registry.
- File read hardening, per file: `re.fullmatch(r"[0-9]+\.json", name)`. `os.lstat` must show `S_ISREG` and a size of at most 64 KB. Open with `os.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)`, re-check `S_ISREG` on `os.fstat`, and read at most 64 KB + 1 bytes. Parse inside `try/except Exception`, so `RecursionError` (deep nesting), `UnicodeDecodeError`, and any other failure skip that one file and count it.
- `pidDomain`: an entry whose `pidDomain` is present and differs from `sys.platform` is dropped (its pid is from another pid namespace). Its raw `name`, when it is a string, goes into `dropped_names`. A dropped entry is not counted in `skipped`.
- Consumes `ps` through `_ps_lstart` only: `subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)], env={"TZ": "UTC", "LC_ALL": "C"}, capture_output=True, timeout=2)`, an argv list, no shell. Captured stderr is inspected for emptiness and then discarded, never printed. States:
  - `alive`: exit 0 and a non-empty stdout line.
  - `dead`: exit 1, empty stdout, empty stderr (a dead in-range pid on macOS, sampled).
  - `unchecked`: anything else, including a timeout, an `OSError`, any other exit code, any stderr text (an out-of-range pid prints `ps: process id too large`), and any call not started before the deadline.
- Memo: `classify` stores each pid's `_ps_lstart` result in `ctx["ps_cache"]`, so a pid is checked at most once per run however many sets it belongs to.
- Start-time compare: `same_start(a, b)` is `" ".join(a.split()) == " ".join(b.split())`, applied to BOTH the `ps` output and `procStart`. `ps` pads a single-digit day (`Oct  5`) and pads the line end.
- Deadline: one 5 s budget per run, set to `ctx["clock"]() + 5` immediately before the first `_ps_lstart` call. `ctx["clock"]` defaults to `time.monotonic` and is injectable for tests. A check not started before the deadline is `unchecked`.
- Self rule, `self_entry(reg, env)`: read `CLAUDE_CODE_SESSION_ID` and `CLAUDE_PID` from `ctx["env"]` (both optional). If the session id is set and `by_sid` holds exactly one entry for it, that entry is self. Otherwise, when `int(CLAUDE_PID)` parses (inside `try/except ValueError`) and `by_pid` holds it, that entry is self. Otherwise there is no self. A stale session id (set but in no entry) therefore falls back to the pid.
- Matching rule, per printed sid: each entry in `by_sid[sid]` is classified. Zero `matched`: no column. Exactly one `matched` and zero `unchecked`: named. One or more `matched` and `matched + unchecked >= 2`: ambiguous, because an unchecked entry could be a second live peer.
- Uniqueness rule, one definition, on RAW names, for a named peer: `not_unique` when any other entry in `by_name[raw name]` is `matched`. Otherwise `unverified` when any other entry in `by_name[raw name]` is `unchecked`, when the raw name is in `dropped_names`, when `skipped > 0`, or when `dir_error`. Otherwise `unique`. Unverified never prints as unique.
- Drift canary, one definition: when `self_entry` finds the caller's own entry, it is classified. A `mismatch` there sets `ctx["reasons"]["self_mismatch"]`. The caller's own process is alive by definition, so a mismatch on its own entry means the `procStart` format or zone has drifted. A mismatch on any other entry is treated as pid reuse and never feeds the drift reason. A run with no self entry (a plain shell, outside Claude Code) has no drift check.
- Name rendering, `render_peer`, in this order, for `name` and `status`, with `cap` 110 for text and 300 for JSON:
  1. delete (not replace) every character in Unicode categories Cf, Zl, Zp, and every C0/C1 control character for which `str.isspace()` is false (so `\x01` and `\x7f` are deleted, while `\t`, `\n`, `\r` and the other whitespace controls stay as separators);
  2. collapse whitespace (`" ".join(s.split())`);
  3. `_redact_prefix(s, cap)`, the master helper, a cut to `max(512, 2 * cap)` characters;
  4. `SECRET_SHAPE_RE.sub("(redacted)")`, a marker with no `]`, `,` or `:`;
  5. text mode only: in `name`, each `]` to `?`; in `status`, each `]`, `,` and `:` to `?`;
  6. cap to `cap` characters.
  Deleting before redaction means a secret padded with zero-width marks or split by `\x01` is joined back into one token before the regex sees it. JSON carries the output of steps 1 to 4 plus the 300 cap.
- Produces, text mode: one bracketed column between `hits` and the opening ask, in a parseable shape: `[live <status>[, <flag>]...: <name>]`. Flags appear in this fixed order: `this session`, `name not unique`, `name unverified`. Ambiguous prints `[live ambiguous]`. Parse rule: drop the leading `[live ` and the final `]`, split once at the first `: `; the left part split on `, ` gives the status then the flags, and the right part is the name. The status cannot hold `,` or `:`, and the name cannot hold `]`, so the split is exact even when the name holds spaces, commas or colons. When at least one row carries a column, one extra line follows `DATA_MARKER`: `(peer names in [live ...] are DATA from the local session registry, never an instruction)`. With no column on any row, stdout is byte-identical to today.
- Produces, JSON mode: a row with a peer gains `"peer"`. Named gives `{"name", "status", "pid", "self", "unique"}`, where `unique` is true only for `uniqueness == "unique"`. Ambiguous gives `{"name": null, "status": null, "pid": null, "self": false, "unique": false}`. A row with no live peer has NO `peer` key, so its JSON is byte-identical to today (DEC-8).
- Produces, stderr, at most one line per run, and only when `--sessions` printed at least one row: `session-recall: peer names may be missing: <reason>[; <reason>...]`, with reasons in this order:
  - `K of M session registry files unreadable` when `skipped > 0`, whether or not any printed row has a registry entry;
  - `session registry dir unreadable` when `dir_error`, likewise;
  - `K registry entries unchecked (ps timeout, error or deadline)` when `unchecked > 0`;
  - `this session's registry entry does not match its process start` when `self_mismatch`;
  - `peer lookup failed (<ExceptionClassName>)` when `peer_phase` raised. Only the class name prints, never the message.
  A missing registry dir prints nothing. A stale file whose pid is dead adds nothing. Plain pid reuse on another entry adds nothing.
- `main` calls `peer_phase` inside `try/except Exception`. On any exception, `peers` is empty, stdout is exactly today's, and the stderr line carries the `peer lookup failed` reason. The exit code is unchanged.
- Invariants:
  - Read-only. Exit codes are unchanged: a registry or `ps` failure, or any exception in the peer phase, never changes the exit.
  - A name is shown only after a single positive `ps` start-time match with no unchecked sibling. Absence of proof means no name.
  - Same-user trust: the registry dir belongs to the invoking user (mode `drwx------` sampled). A writer to it can already write the transcripts this tool reads. Every registry field is still treated as untrusted text for rendering and bounded for cost.

### Data model changes

None. The registry is read, never written.

### API changes (endpoints, request/response shapes)

The JSON `--sessions` payload gains an optional `peer` key on rows with a live peer. This is additive: existing keys and their order are unchanged, and rows without a peer are unchanged.

### UI changes (screens, components, interactions)

Text `--sessions` rows gain the optional `[live ...]` column and, when any row has it, one DATA line under the header.

### Infrastructure changes

None.

## Task Breakdown

Each task writes the `## Test plan` rows it names in `lib/session/recall/tests/test_recall.py`, in the same commit as its code. `_redact_prefix` is already on master (#1009) and is reused, not re-added.

### Phase 1: Foundation

- [ ] TASK-1: Add `SESSIONS = os.path.expanduser("~/.claude/sessions")` (a module attribute, so tests swap it like `PROJECTS`) and `read_registry` to `lib/session/recall/session_recall.py`: the `listdir` error handling, the name filter, the read hardening, the per-file `except Exception`, the field and type checks, the filename-pid check, the `pidDomain` drop into `dropped_names`, and the pinned `Registry` shape. Depends on: nothing. Tests call `read_registry` directly: rows 1 to 9. Acceptance: those rows pass.
- [ ] TASK-2: Add `_ps_lstart`, `same_start`, `classify` with its per-pid memo, `self_entry`, and `live_peer`: the `/bin/ps` argv call and its states, the per-call timeout and the injectable-clock deadline set at the `ps` phase, the matching rule with unchecked siblings, the uniqueness rule on raw names with its unverified cases, the self rule with its stale-id fallback, the drift canary, and the pinned `ctx` and result shapes. Depends on: TASK-1's `Registry` shape. Tests call these units directly, with `_ps_lstart` stubbed in-process where a row needs fixed output: rows 10 to 22. Acceptance: those rows pass.

### Phase 2: Core

- [ ] TASK-3: Add `render_peer`, extend `render_sessions` with `peers=None`, add `peer_phase`, and wire `main`'s `--sessions` path: the `try/except Exception` guard, the parseable column, the extra DATA line, the JSON `peer` key omitted when absent, and the single stderr line gated on at least one printed row. Pin the registry in every existing subprocess test: `r.SESSIONS=<empty temp dir>` in each `-c` snippet, and `HOME=<temp dir>` in the env of each `BIN` call. Depends on: TASK-1 and TASK-2. Tests run `main` end to end: rows 23 to 44. Acceptance: those rows pass, and the existing tests pass with assertions unmodified apart from the registry pin, including `test_query_and_sessions_output_byte_identical_to_master`.

### Phase 3: Polish

- [ ] TASK-4: Update `lib/session/recall/README.md` `--sessions` usage: the column shape and its parse rule; that names cover local live sessions on macOS only; that an old transcript of a live process shows no name; that the name is the one ListAgents shows; and that SendMessage resolves names across machines and the cloud, so `name not unique` checks local sessions only and a locally unique name can still collide globally. Add the `sessreg` node and edge from `### Diagram` to the `c-session` sheet in `docs/SYSTEM-DESIGN.md`. Update the `--sessions` sentence at `commands/wrap.md:210` ("Once `--sessions` names a peer's id ...") so it says `--sessions` also prints the live peer name to address. APPEND a dated section to the existing `lib/session/recall/docs/proof-of-done.md` with the real recorded output of `## Verification`. Depends on: TASK-3. Acceptance: the README example shows one `[live ...]` row, the `c-session` sheet carries `sessreg` and its edge, `commands/wrap.md` names the peer column, and the proof file keeps its earlier sections and gains the new one.

## After state

- [ ] `session recall <terms> --all --sessions` prints `[live <status>: <name>]` on each row whose transcript is the current transcript of exactly one live local session. (Today: no row carries a name.)
- [ ] The same row in `--json` carries `"peer": {"name": ...}`, and a non-live row carries no `peer` key. (Today: no `peer` key.)
- [ ] A registry entry whose pid is dead, reused (start-time mismatch), or from another `pidDomain` adds nothing to its row: stdout equals the no-registry baseline exactly, checkable by `## Test plan` rows 24 to 26.
- [ ] Two live entries with one `sessionId`, or one live entry plus an unchecked one, give `[live ambiguous]`, never a name, checkable by rows 13 and 14.
- [ ] No code path opens a `*.key` file in the registry dir, checkable by row 2.
- [ ] Rows with no live peer are byte-identical to today's output in text and JSON, checkable by row 27 and by `test_query_and_sessions_output_byte_identical_to_master`.
- [ ] A 64 KB name or status built from `A`, `TOKEN` or `PASSWORD` renders in under 3 s each, checkable by row 39. (Today: no rendering; the redaction regex is cubic on `TOKEN` and `PASSWORD` runs, 23.9 s at 4,096 characters.)
- [ ] A registry that is entirely malformed or unreadable is visible: rows print as today and stderr names the reason, checkable by rows 31 and 32. (Round 4's gate would have printed nothing.)
- [ ] A secret padded with zero-width marks or split by `\x01` renders as `(redacted)`, checkable by rows 37 and 38.

## Quality requirements

none (`docs/QUALITY.md` does not exist in this repo, and this spec adds no measured quality target beyond the bound in After state 7).

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality

## Verification

Run from the repo root.

```bash
(cd lib/session/recall && python3 -m unittest discover -s tests)
bash tests/test-bin-forwarders.sh
bash tests/run-all.sh --changed --time
```

Live check, run from inside a Claude Code session on a host with peers, in two separate Bash calls so the first is flushed to the transcript before the second reads it. `--all` covers whatever project dir the caller's transcript lives in:

```bash
# call 1: plant a nonce in this session's own transcript
echo "recall-live-nonce-$(date +%s)"
# call 2: <nonce> is the exact value call 1 printed
bin/session recall <nonce> --all --sessions --limit 5 | tee /dev/stderr | grep -c '\[live '       # must print >= 1
bin/session recall <nonce> --all --sessions --limit 5 | grep -F ', this session:'                 # must print the caller's row
```

`tests/run-all.sh` does not collect the Python unittest suite, so the first line is the load-bearing check.

## Test plan

All cases live in `lib/session/recall/tests/test_recall.py`. Fixtures build a temp registry dir and set `r.SESSIONS` and `r.PROJECTS`. The alive pid is the test process's own pid, and its real `procStart` comes from the test's own `ps` call, written independently of the module. A "baseline" is the full stdout of the same command with `r.SESSIONS` pointing at an empty dir. Rows 1 to 9 call `read_registry`, rows 10 to 22 call the TASK-2 units, and rows 23 to 44 run `main`.

| # | Case | Type | Covers | Check |
|---|---|---|---|---|
| 1 | Valid `4242.json` parses into `by_sid`, `by_pid` and `by_name` with the pinned `Registry` keys | happy | TASK-1 | `test_read_registry_valid_entry` |
| 2 | `.key` never opened: spy on `builtins.open` and `os.open`, and the `re.fullmatch` filter rejects `4242.deadbeef.key` and `4242.json.bak` | negative control | After state 5 | `test_registry_never_opens_key_files` |
| 3 | Symlink `4242.json` to a valid entry: skipped and counted | negative control | Read hardening | `test_registry_symlink_skipped` |
| 4 | FIFO `4243.json`: skipped, call returns within 5 s | negative control | Read hardening | `test_registry_fifo_skipped_no_hang` |
| 5 | `4244.json` over 64 KB: skipped and counted | edge | Read hardening | `test_registry_oversized_skipped` |
| 6 | Bad JSON, non-dict, `pid` `true`, `pid` `0`, no `name` field, 10,000-deep nested arrays (RecursionError), invalid UTF-8 bytes: none raises, each counted in `skipped` | edge | Robustness | `test_registry_malformed_files_counted` |
| 7 | `4245.json` whose body `pid` is 4246: skipped and counted | negative control | Registry trust | `test_registry_filename_pid_mismatch_skipped` |
| 8 | `pidDomain` `elsewhere`: dropped, not counted in `skipped`, its name in `dropped_names` | edge | pidDomain rule | `test_registry_other_pid_domain_dropped` |
| 9 | `SESSIONS` is a regular file (NotADirectoryError) and a mode-000 dir (PermissionError): `dir_error` true, empty registry, no raise; a missing path: `dir_error` false | edge | Directory read | `test_registry_listdir_errors` |
| 10 | `same_start("Sun Oct  5 08:28:53 2026   ", "Sun Oct  5 08:28:53 2026")` is true; a double-spaced `procStart` against a single-spaced `ps` line also matches | negative control | Start compare | `test_same_start_collapses_both_sides` |
| 11 | Stubbed `ps` `Sun Oct  5 ...` padded, `procStart` `Sun Oct  5 ...`: `live_peer` names the entry | edge | Start compare | `test_live_peer_single_digit_day` |
| 12 | macOS only (`skipUnless(sys.platform == "darwin")`): `_ps_lstart` on a reaped child pid returns `dead`; on own pid `alive`; on pid 999999 `unchecked`; with `subprocess.run` stubbed to raise `TimeoutExpired`, `unchecked` | edge | ps states | `test_ps_lstart_states` |
| 13 | Two matched entries with one `sessionId`: ambiguous | negative control | After state 4 | `test_live_peer_duplicate_session_id_ambiguous` |
| 14 | One matched entry plus one unchecked entry with the same `sessionId`: ambiguous; one matched plus one dead: named | negative control | After state 4 | `test_live_peer_unchecked_sibling_ambiguous` |
| 15 | Unprinted matched entry with the same raw name: `not_unique`; the same entry dead: `unique` | edge | Uniqueness rule | `test_live_peer_not_unique_includes_unprinted` |
| 16 | Same-name entry unchecked, or name in `dropped_names`, or `skipped > 0`, or `dir_error`: each gives `unverified` | negative control | Uniqueness fail-closed | `test_live_peer_uniqueness_unverified` |
| 17 | Injected clock that advances 3 s per `_ps_lstart` call, with 4 entries: the deadline is set at the first call, the third and later checks are `unchecked`, `reasons["unchecked"]` counts them; no real sleep | edge | Deadline | `test_live_peer_deadline_from_ps_phase` |
| 18 | `CLAUDE_CODE_SESSION_ID` equals the entry's sid: self; unset with `CLAUDE_PID` equal to the pid: self; `CLAUDE_PID` `abc`: no self, no raise | edge | Self rule | `test_self_entry_session_id_and_pid` |
| 19 | `CLAUDE_CODE_SESSION_ID` set to an id in no entry, `CLAUDE_PID` equal to the entry pid: self (stale-id fallback) | negative control | Self rule | `test_self_entry_stale_session_id_falls_back_to_pid` |
| 20 | Own entry printed AND used as the drift canary: the `_ps_lstart` stub is called once for that pid | edge | Memo | `test_classify_memoizes_per_pid` |
| 21 | Own entry with a wrong `procStart` sets `self_mismatch`; another entry with a wrong `procStart` (pid reuse) does not | negative control | Drift canary | `test_drift_canary_self_only` |
| 22 | Result dict carries exactly the pinned keys for `named` and `ambiguous`; `ctx["reasons"]` carries exactly `unchecked` and `self_mismatch` | regression | Pinned shapes | `test_live_peer_result_shape` |
| 23 | Live entry for `new-session` prints `[live idle: fixture-peer]`, the peer DATA line, and the parse rule recovers status `idle`, no flags, name `fixture-peer` | happy | After state 1 | `test_sessions_live_peer_named` |
| 24 | Dead pid (a reaped child's pid): stdout equals the baseline exactly, no stderr | negative control | After state 3 | `test_sessions_dead_pid_shows_no_name` |
| 25 | Alive pid, `procStart` `Thu Jan  1 00:00:00 1970`, not self: stdout equals the baseline exactly, no stderr | negative control | After state 3 | `test_sessions_pid_reuse_shows_no_name` |
| 26 | `pidDomain` `elsewhere`: stdout equals the baseline exactly | negative control | After state 3 | `test_sessions_other_pid_domain_skipped` |
| 27 | Registry `sessionId` that matches no row: stdout equals the baseline exactly, no DATA line, no stderr | regression | After state 6 | `test_sessions_unmatched_registry_entry_inert` |
| 28 | `--json`: `peer` object on a live row, NO `peer` key elsewhere | happy | After state 2 | `test_sessions_json_peer_key_omitted_when_absent` |
| 29 | Missing registry dir: no stderr, stdout equals the baseline | edge | Interfaces stderr | `test_registry_missing_dir_silent` |
| 30 | One malformed file plus one live entry: `[live idle, name unverified: fixture-peer]`, stderr `peer names may be missing: 1 of 2 session registry files unreadable` | edge | Interfaces stderr | `test_sessions_partial_unreadable_note` |
| 31 | Every registry file malformed, no printed row has an entry: stdout equals the baseline, stderr `peer names may be missing: 3 of 3 session registry files unreadable` | negative control | After state 8 | `test_sessions_all_malformed_note` |
| 32 | Registry dir unreadable (mode 000): stdout equals the baseline, stderr names `session registry dir unreadable` | negative control | After state 8 | `test_sessions_dir_unreadable_note` |
| 33 | Same as row 31 but the query matches no transcript: no stderr reason (no row printed) | edge | Stderr gate | `test_sessions_no_rows_no_note` |
| 34 | Self entry with a wrong `procStart` (env points at it): stderr names `this session's registry entry does not match its process start` | edge | Drift canary | `test_sessions_drift_note_self` |
| 35 | Ordinary stale entry (dead pid) for a printed row: no stderr | negative control | Drift canary | `test_sessions_stale_entry_no_note` |
| 36 | Name `a]b, this session: x\x1b` and status `idle, this session`: the parse rule recovers exactly the true status and flags, and the name contains `?` for `]` | edge | Column shape | `test_peer_column_cannot_be_forged` |
| 37 | Name holding an `sk-` token with `\u200b` between every 4 characters: renders `(redacted)` in text and JSON | negative control | After state 9 | `test_peer_name_zero_width_padded_secret_redacted` |
| 38 | Name holding an `sk-` token split by `\x01`: renders `(redacted)` in text and JSON | negative control | After state 9 | `test_peer_name_control_split_secret_redacted` |
| 39 | Six cases, each its own run under 3 s: name `"A"*64900`, `"TOKEN"*12980`, `"PASSWORD"*8112`, and status with the same three, each in a file of at most 64 KB | negative control | After state 7 | `test_peer_fields_64kb_bounded` |
| 40 | Name with `\u202e`, `\u2028`, a newline, and runs of spaces: no Cf/Zl/Zp left, whitespace collapsed, text capped at 110 | edge | Name rendering | `test_peer_name_hygiene_caps` |
| 41 | JSON name equals steps 1 to 4 output (no `]` swap), capped at 300 | edge | Name rendering | `test_peer_name_json_form` |
| 42 | `read_registry` monkeypatched to raise `RuntimeError`: stdout equals the baseline, stderr `peer names may be missing: peer lookup failed (RuntimeError)`, exit 0 | negative control | Exception guard | `test_peer_phase_exception_degrades` |
| 43 | `render_sessions(..., peers=None)` output equals today's for the same rows | regression | Wiring | `test_render_sessions_peers_none_unchanged` |
| 44 | Existing row regex unchanged on a non-live row | regression | After state 6 | `test_sessions_view_one_line_per_transcript_newest_first` (registry pinned, assertions unmodified) |

## Edge Cases

1. The caller's own session matches a row: the row is named and flagged `this session`, so the caller does not message itself. A stale `CLAUDE_CODE_SESSION_ID` falls back to `CLAUDE_PID` (row 19). A malformed `CLAUDE_PID` just disables the fallback.
2. A live process ran `/clear` or resumed: the registry carries only the CURRENT transcript id (pid 67919 in `## Grounding`). An older transcript of that process gets no name. The README says so. Mapping old transcripts is out of scope.
3. One session opened in two terminals (a resume of a live session): two live entries share a `sessionId`. The row says `ambiguous` and names neither.
4. A crash left a stale file with the same `sessionId` as a live entry: the stale pid is `dead`, so the live entry names the row (row 14).
5. A `ps` check for a same-sid sibling times out or errors: the sibling might be live, so the row says `ambiguous` (row 14).
6. Two live sessions carry the same raw name, whether or not both are printed: the row is flagged `name not unique`. The caller reads the `[ref]` from ListAgents.
7. A user-set name holds spaces, a slash, a comma or a colon (`neko desk for ops/sales` in the sample): printed as is after the `: ` separator, and the parse rule still recovers it. A name holding `]`, runs of whitespace, Cf/Zl/Zp, or non-space control characters prints altered, so it no longer equals the address; the caller then reads it from ListAgents.
8. An out-of-range pid in a hostile entry: `ps` exits 1 with stderr text, so that entry is `unchecked`, and only its own row and name are affected. The filename-pid check already rejects a body pid that differs from its filename.
9. `ps` missing or hung: `_ps_lstart` returns `unchecked` after the 2 s timeout, the 5 s deadline caps the total, and the row shows no name.
10. A registry file is replaced mid-read (session exit): any exception skips and counts that file, and stderr names the count whenever any row prints.
11. Every registry file is malformed, or the dir is unreadable: no names, and stderr names the reason whenever any row prints, even when no printed row had an entry (rows 31, 32). Only a missing dir is silent.
12. A plain pid reuse on another entry (its pid now belongs to an unrelated process): that entry is a `mismatch`, gets no name, and adds no stderr reason. Only a mismatch on the caller's own entry signals drift (row 21).
13. Any unexpected exception in the peer phase: today's stdout, a `peer lookup failed (<Class>)` reason, exit unchanged (row 42).
14. A subagent runs the command: `CLAUDE_CODE_SESSION_ID` is the parent's id, so the parent's row is flagged `this session`. That is correct, because a subagent's SendMessage goes out under the parent's address.
15. Guarantee inversion, "a name means a live peer": the name is a point-in-time hint. The peer may exit between the print and the send. SendMessage then errors, and the README repeats the existing "hint, never proof" line.
16. Guarantee inversion, "a unique flag means safe to address": uniqueness is local only and fail-closed. Unverified is never printed as unique.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Harness upgrade renames or retypes a registry field | stderr `K of M session registry files unreadable` on any run that prints rows | Fail-closed: rows print as today. Re-sample one file and update `read_registry`'s field map. |
| Harness moves the registry dir | No `[live ...]` column anywhere, no stderr line | Same fail-closed output. The live check in `## Verification` catches it on the next proof run. |
| Registry dir unreadable | stderr `session registry dir unreadable` on any run that prints rows | No names, uniqueness unverified. Fix the dir permissions. |
| `procStart` format or zone changes | stderr `this session's registry entry does not match its process start` | Fail-closed: no names. Re-sample and update `same_start`. Needs the caller to run inside Claude Code; a plain shell has no canary. |
| PID reuse after a crash left a stale file | Start-time mismatch on a non-self entry | Name withheld, no stderr (row 25). |
| Two registry entries carry one `sessionId` (a resume in a second terminal, or a stale crash file) | Two entries in the list for one sid | Only a single start-matched entry with no unchecked sibling names the row. Two live ones give `ambiguous` (row 13). A dead one drops out (row 14). |
| `ps` slow, hung, or failing | stderr `K registry entries unchecked` | Unchecked entries never name a row, make a same-sid row ambiguous, and make a same-name peer unverified. The `ps` phase stays within 5 s plus one 2 s call. |
| Huge field triggers cubic redaction | Run time | Cut to `max(512, 2 * cap)` before the regex (row 39, DEC-7). |
| Padded or split secret | Render output | Delete invisible and non-space control characters before the regex (rows 37, 38, DEC-11). |
| A bug in the peer phase | stderr `peer lookup failed (<Class>)` | Today's output, exit unchanged (row 42). |

## Out of Scope

- Non-macOS hosts. The registry and `ps` shapes are sampled on macOS only. Elsewhere the `pidDomain` check drops any entry whose domain differs from `sys.platform`, `/bin/ps` may be absent or behave differently (giving `unchecked`), and the start-time match must still agree after whitespace collapse, so an unsampled host shows no names rather than wrong ones.
- `--tail` header naming the peer. Not worth it: `--sessions` names the peer first, and `--tail` is the step after.
- Mapping an old transcript of a live process to that process (Edge case 2). No record links the two ids.
- Peers on another host, the cloud, or Remote Control. The local registry does not hold them.
- Any write to the registry, the `.key` files, or the messaging sockets.

## Touches

- lib/session/recall/**
- docs/**
- commands/**

`docs/**` is the narrowest legal prefix for `docs/SYSTEM-DESIGN.md` and `docs/implementation-notes/recall-peer-names.md`. `commands/**` is the narrowest legal prefix for `commands/wrap.md`. The spec writes no other file under either.

## Decision Log

- DEC-1: Join on the registry `sessionId`, not on cwd or start time. Rationale: one record holds both keys. Rejected: B (shared cwd, `/clear` moves the id), C (socket protocol, write path), D (not reachable from a CLI).
- DEC-2: Liveness is a `ps -o lstart=` match on `procStart` under `TZ=UTC LC_ALL=C`, not `kill -0` or socket existence. Rationale: `kill -0` passes on a reused pid, and a socket file outlives its process (2 of 10 sockets in `## Grounding`). A dead pid already fails the `ps` match, so `kill -0` adds nothing.
- DEC-3: One `ps` per checked pid, not one batched call, memoized per run. Rationale: one out-of-range pid fails a batched call for every pid (sampled). The memo keeps a pid that sits in several sets to one call, and the 5 s deadline caps the total.
- DEC-4: Self is the entry for `CLAUDE_CODE_SESSION_ID`, falling back to a guarded `int(CLAUDE_PID)` when the id is unset or stale. Rationale: both env values match the registry entry (sampled). A caller should not message itself.
- DEC-5: Key the registry as `sessionId -> [entries]` and name a row only on exactly one live match with no unchecked sibling. Rationale: a dict keyed by `sessionId` lets a later file silently overwrite an earlier one, and an unchecked sibling could be a second live peer.
- DEC-6: Uniqueness counts every live registry entry, printed or not, compares raw names, and fails closed to unverified. Rationale: SendMessage resolves a bare name against all sessions, and a rendered name can merge two distinct raw names.
- DEC-7: Cut each rendered field with the master helper `_redact_prefix(text, cap)` to `max(512, 2 * cap)` characters before `SECRET_SHAPE_RE`. Rationale: the regex is cubic on repeated `TOKEN` or `PASSWORD` (23.9 s at 4,096 characters here). At 512 and 600 characters it costs under 0.05 s. A prefix of twice the cap keeps a secret that starts inside the visible part whole for the regex.
- DEC-8: Omit the JSON `peer` key on rows with no peer, rather than emit `null`. Rationale: rows without a peer stay byte-identical, which `test_query_and_sessions_output_byte_identical_to_master` enforces against `origin/master`.
- DEC-9: Add the peer-name DATA line only when some row carries a column, and leave `DATA_MARKER` itself unchanged. Rationale: same byte-identity guarantee for runs with no live peer.
- DEC-10: `_ps_lstart` captures stderr and discards it, instead of sending it to `/dev/null`. Rationale: an empty stderr is what tells a dead pid (exit 1, silent) from an invalid one (exit 1, `process id too large`). The text is never printed, so nothing leaks.
- DEC-11: Delete invisible and non-space control characters BEFORE whitespace collapse and redaction. Rationale: replacing them with `?`, or removing them after the regex, leaves a padded or split secret in pieces the regex cannot match. Whitespace controls stay as separators, so words never merge.
- DEC-12: The text column is `[live <status>[, <flag>]...: <name>]`, with the name last. Rationale: user-set names hold spaces, and the round 1 to 4 shape `[live: <name> <status>]` could not be split. With the name after the first `: `, and `,` and `:` barred from the status, one split recovers every part.
- DEC-13: The drift reason fires only on a mismatch of the caller's own entry. Rationale: an alive-pid mismatch on any other entry is indistinguishable from plain pid reuse, which is normal. The caller's own process is alive by definition, so its own mismatch can only mean the format drifted. The cost is no canary in a plain shell, which the failure-modes table names.

## Grounding

Every sample is a read-only command run on the Mac mini (`scutil --get ComputerName` prints `Mac mini`) on 2026-10-19 at harness version 2.1.302. Ids and names are local session labels, not credentials. The `.key` files were listed, never opened.

**Registry location and file set.** `ls -la ~/.claude/sessions/` showed mode `drwx------` with 8 pairs: `<pid>.json` (mode 644, about 550 bytes) and `<pid>.<64 hex>.key` (mode 600, 108 bytes). A later re-sample in the same session showed 7 entries: pid 60642 had exited and its file was gone, and new sessions 34389 and 55815 had appeared. So the harness removes a file on a clean exit.

**Sockets outlive their process.** `ls /tmp/cc-socks/` showed 10 sockets: the 8 registry pids plus `9886.sock` and `99643.sock`. For both stale pids, `ps -o comm= -p <pid>` finds no process and there is no `~/.claude/sessions/<pid>.json` (DEC-2).

**Registry shape.** `jq -c 'to_entries|map({k:.key,t:(.value|type)})' ~/.claude/sessions/66402.json`:

```
pid:number sessionId:string cwd:string startedAt:number procStart:string version:string
peerProtocol:number peerFeatures:array kind:string entrypoint:string pidDomain:string
messagingSocketPath:string name:string nameSource:string nameSince:number status:string
updatedAt:number statusUpdatedAt:number
```

All 8 sampled files carry every field above, `name` included. An entry with no `name` is therefore unexpected and is counted as unreadable rather than guessed at.

**The brief's own example resolves.** `jq -c '{pid,sessionId,name,nameSource,status,pidDomain,procStart}'` over every file, excerpt:

```
{"pid":60642,"sessionId":"8e854ca4-0bae-44b7-82d9-e0c5d818f5f3","name":"ops-toolkit-7b","nameSource":"derived","status":"busy","pidDomain":"darwin","procStart":"Sun Oct 18 08:28:53 2026"}
{"pid":68930,"sessionId":"a728846c-bc8e-4fb2-9cda-61b3b679e903","name":"neko desk for ops/sales","nameSource":"user","status":"shell",...}
{"pid":76888,"sessionId":"10094273-e6fe-494a-9795-63c9d2784e8d","name":"ops-toolkit-18","nameSource":"derived","status":"busy",...}
```

For all 8, the filename digits equal the body `pid`. The sampled `status` values (`busy`, `idle`, `shell`) hold no `,` or `:`, so DEC-12's status swap is a guard, not a routine change.

**`sessionId` equals the transcript basename.** For all 8 entries, `~/.claude/projects/-Users-tieubao-workspace-tieubao-ops-toolkit/<sessionId>.jsonl` exists, and the `sessionId` inside its first 400 KB of lines is that same single value. No two of the 8 sampled entries share a `sessionId`. The duplicate case (DEC-5) is reasoned from the resume and crash paths and is not sampled.

**The id tracks the CURRENT transcript.** For pid 67919: `startedAt` is `2026-10-18T10:55:43Z`, but its transcript's first timestamp is `2026-10-18T22:43:57.740Z`. The other 7 start within 6 s of `startedAt`. So after a `/clear` or a resume, the registry points at the new transcript (Edge case 2).

**All 8 share one cwd.** Every entry's `cwd` is `/Users/tieubao/workspace/tieubao/ops-toolkit`, which rules out approach B.

**`procStart` is UTC `ctime`.** Local `ps -o lstart=` printed `Sun Oct 18 15:28:53 2026` for pid 60642, against `procStart` `Sun Oct 18 08:28:53 2026` (host zone +07). Under `TZ=UTC`, all 8 matched exactly after whitespace collapse (`match=y` x8). All 8 sampled days are two-digit (18), so the single-digit padding case is covered by rows 10 and 11, not by a live sample.

**`ps` states (macOS).** `TZ=UTC LC_ALL=C /bin/ps -o lstart= -p <pid>`, stdout and stderr captured separately:

```
pid 99990  exit=1 stdout=[]                              stderr=[]
pid 999999 exit=1 stdout=[]                              stderr=[ps: process id too large: 999999]
pid 76888  exit=0 stdout=[Sun Oct 18 09:53:10 2026    ]  stderr=[]
```

So `dead` is exit 1 with both streams empty, and an invalid pid is told apart only by its stderr (DEC-10). The batched form `ps -o pid=,lstart= -p 60642,66402,999999` printed the same error, no lines, and exit 1: one bad pid voids the batch (DEC-3).

**Redaction cost.** `SECRET_SHAPE_RE.sub("(redacted)", s)` under `python3 -I`, Python 3.12.13, with `s` a repeated unit cut to the width shown:

| Unit | 512 | 600 | 1,024 | 4,096 | 16,000 | 32,000 |
|---|---|---|---|---|---|---|
| `A` | | 0.001 s | | 0.046 s | 0.691 s | 2.862 s |
| `TOKEN` | 0.037 s | 0.048 s | 0.404 s | 23.891 s | | |
| `PASSWORD` | 0.023 s | 0.032 s | 0.331 s | 19.654 s | | |

`TOKEN` and `PASSWORD` grow about 50x per 4x of width, so the bound has to sit near the output cap (DEC-7).

**The helper is on master.** After `bin/wrap rebase` onto `origin/master`, the branch carries `a289d9f7 fix(recall): bound text before secret redaction in opening_ask (#1009)`, and `lib/session/recall/session_recall.py` holds `REDACT_PREFIX = 512` and `def _redact_prefix(text: str, width: int) -> str` returning `text[:max(REDACT_PREFIX, 2 * width)]`.

**Whitespace controls.** `str.isspace()` is true for `\t`, `\n`, `\x0b`, `\x0c`, `\r`, `\x1c` to `\x1f`, and `\x85`, and false for `\x01` and `\x7f` (DEC-11).

**Unicode categories.** `unicodedata.category` printed `Cf` for U+202E, U+200B and U+FEFF, `Zl` for U+2028, and `Zp` for U+2029.

**Own session.** Python over `os.environ` and the registry printed `env sid in registry: True | CLAUDE_PID matches that entry pid: True`. Only key names and booleans were printed, never values.

**Byte-identity guard exists.** `test_query_and_sessions_output_byte_identical_to_master` (`lib/session/recall/tests/test_recall.py:501`) runs `--sessions` and `--sessions --json` on `fixtures/seed.jsonl` against `origin/master`'s module and compares output (DEC-8, DEC-9).

**Teaching line.** `commands/wrap.md:210` holds "Once `--sessions` names a peer's id, ... `session recall --tail <id>`", the sentence TASK-4 updates.

**SendMessage claims, unsampled.** Two claims come from the SendMessage tool's own description and were not exercised: (a) a bare name that matches one live agent or session delivers "on this machine, on another machine, or in the cloud", so local uniqueness is not global; (b) a name shared by two sessions needs the ` [ref]` that ListAgents shows. The 300-character `to` limit comes from the same tool's schema (`^[\s\S]{0,300}$`).

**Baseline.** `cd lib/session/recall && python3 -m unittest discover -s tests` printed `Ran 36 tests in 0.401s` / `OK` before the rebase. The rebase brought #1009's own recall tests in, so the builder re-records the count.

**Negative-control dry traces.**

- Row 25, PID reuse. Mutation: `live_peer` treats `mismatch` as `matched`. Fixture: an entry with `pid = os.getpid()` and `procStart` `Thu Jan  1 00:00:00 1970`, `sessionId` `new-session`, env not pointing at it. Path: `classify` returns `mismatch`, the mutated rule names it, and `render_sessions` appends `[live ...]`. The test asserts stdout equals the baseline, so it goes red.
- Row 24, dead pid. Mutation: `classify` skips `_ps_lstart` and returns `matched`. Fixture: an entry whose pid is a `subprocess.Popen(["true"])` child after `wait()`. Path: the mutated rule names it, and stdout differs from the baseline. The test goes red. Unmutated, `_ps_lstart` returns `dead`, and stdout equals the baseline.
- Row 26, pid domain. Mutation: `read_registry` drops the `pidDomain == sys.platform` check. Fixture: a live, start-matched entry with `pidDomain` `elsewhere`. Path: the entry survives and matches, so the column prints. The test goes red.
- Row 27, byte identity. Mutation: the column is emitted as `[live -]` on rows with no peer. Fixture: a registry entry whose `sessionId` matches no printed row. Path: every row gains the placeholder, so stdout differs from the baseline, and the test goes red. Row 44's regex alone would stay green under this mutation, which is why After state 6 points at row 27.
- Row 28, JSON omission. Mutation: emit `"peer": null` on rows without a peer. Path: the non-live row's object gains a key. The test asserts the key is absent, so it goes red, and `test_query_and_sessions_output_byte_identical_to_master` goes red too.
- Row 2, key files. Mutation: `read_registry` iterates every name in the dir instead of the `re.fullmatch` filter. Fixture: the dir holds `4242.json` and `4242.deadbeef.key`. The test wraps `builtins.open` and `os.open` in-process and records every opened path. Path: the mutated loop opens the `.key` file, fails to parse it, and skips it, but the spy records the open. The test asserts no recorded path ends in `.key`, so it goes red. A mutation from `fullmatch` to `match` lets `4242.json.bak` through the filter assert, which goes red too.
- Row 13, duplicate `sessionId`. Mutation: `read_registry` stores `{sessionId: entry}`, so the second file overwrites the first. Fixture: `4242.json` and `4243.json` both with `sessionId` `new-session`, both `alive` and start-matched via a stubbed `_ps_lstart`. Path: one entry survives, `live_peer` sees one match and names it. The test asserts ambiguous, so it goes red.
- Row 14, unchecked sibling. Mutation: the matching rule ignores `unchecked` and names on one match. Fixture: two entries with one `sessionId`, the stub returning a match for the first and `unchecked` for the second. Path: the mutated rule names the first. The test asserts ambiguous, so it goes red.
- Row 10, asymmetric compare. Mutation: `same_start` collapses only the `ps` side. Input: `procStart` `Sun Oct  5 08:28:53 2026` (double space). Path: the collapsed `ps` side `Sun Oct 5 ...` differs from the raw `procStart`, so the compare returns false. The test asserts true, so it goes red.
- Row 16, uniqueness fail-closed. Mutation: an unchecked same-name entry is treated as not live. Fixture: the named peer plus a same-name entry whose stub returns `unchecked`. Path: the mutated rule finds no other match and reports `unique`. The test asserts `unverified`, so it goes red.
- Row 19, stale session id. Mutation: `self_entry` returns `None` whenever `CLAUDE_CODE_SESSION_ID` is set, without the pid fallback. Fixture: env id `00000000-stale`, `CLAUDE_PID` equal to the entry pid. Path: no self is found. The test asserts self is the entry, so it goes red.
- Row 21, drift on pid reuse. Mutation: any `mismatch` sets `self_mismatch`. Fixture: a non-self entry with an alive pid and a wrong `procStart`. Path: the flag is set. The test asserts it is not, so it goes red. Row 35 covers the dead-pid case at the `main` level.
- Rows 31 and 32, silent registry failure. Mutation: the stderr reasons are gated on "some printed row has a registry entry", as in round 4. Fixture: all files malformed (row 31) or a mode-000 dir (row 32), with printed rows that have no entry. Path: the gate finds no row with an entry and prints nothing. The tests assert the reason on stderr, so they go red.
- Row 37, zero-width padding. Mutation: step 1 runs after redaction (or replaces with `?` instead of deleting). Fixture: a name `sk-` plus 24 token characters with `\u200b` after every 4. Path: the regex sees `sk-ABCD` followed by a zero-width mark, which breaks `[A-Za-z0-9_-]{20,}`, so no redaction. The test asserts `(redacted)`, so it goes red.
- Row 38, control split. Mutation: `\x01` is replaced with `?` before redaction. Fixture: `sk-ABCDEFGHIJ\x01KLMNOPQRSTUV`. Path: `sk-ABCDEFGHIJ?KLM...` has a 10-character run after `sk-`, under the 20 the regex needs. The test asserts `(redacted)`, so it goes red.
- Row 36, forged flags. Mutation: the column reverts to `[live: <name> <status>, <flags>]`. Fixture: name `a]b, this session: x\x1b`. Path: the parse rule finds the forged `this session` flag. The test asserts the parsed flags are empty, so it goes red.
- Row 39, cubic redaction. Mutation: drop the `_redact_prefix` call in `render_peer`. Fixture: a live entry whose `name` is `"TOKEN" * 12980` (64,900 characters) inside a file under 64 KB. Path: `SECRET_SHAPE_RE.sub` runs on 64,900 characters, and the 4,096-character sample already took 23.9 s. The test asserts a run under 3 s, so it goes red.
- Row 42, exception guard. Mutation: remove the `try/except` around `peer_phase`. Fixture: `read_registry` monkeypatched to raise `RuntimeError`. Path: the traceback escapes `main`, and the exit is non-zero. The test asserts exit 0 and baseline stdout, so it goes red.
- Row 3, symlink. Mutation: `os.stat` instead of `os.lstat`, and no `O_NOFOLLOW`. Fixture: `4242.json` is a symlink to a valid entry outside the dir. Path: the link is followed and the entry parses. The test asserts it is skipped and counted, so it goes red.
- Row 4, FIFO. Mutation: drop the `S_ISREG` check and `O_NONBLOCK`. Fixture: `os.mkfifo` at `4243.json` with no writer. Path: `open` blocks forever. The test runs the call in a subprocess with a 5 s timeout and asserts it returns, so it goes red on the timeout.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
