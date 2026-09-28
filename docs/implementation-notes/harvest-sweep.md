# Implementation notes -- harvest-sweep

Deltas from SPEC-357 (phase 1, kit-side tasks T1 to T19, T13b, T22). Nothing here repeats what the spec already states.

## 2026-09-29 Sweep tests live in their own suite, not in tests/test-hooks.sh
- Context: the Task Breakdown says tests go "in the harvest section of `tests/test-hooks.sh`", and the negative-control table runs `bash tests/test-hooks.sh`. `tests/test-hooks.sh` has no harvest section; the existing harvest tests live in `tests/test-kit-foldin-hooks.sh`. A full `tests/test-hooks.sh` run takes about 220s, and `negctl.sh` runs its test command three times per control.
- Decision/Change: every sweep test goes in a new `tests/test-harvest-sweep.sh`, which `tests/run-all.sh` picks up by its glob with no registration. Each negative control runs `bash lib/gate/negctl.sh <root> "bash tests/test-harvest-sweep.sh" "<mutate>"`. T18's wrap assertions stay in `tests/test-meta.sh`, as the spec says. The existing hook tests in `tests/test-kit-foldin-hooks.sh` are the T1 regression set.
- Why: about 36 controls at three runs of a 220s suite each would cost over six hours, with no added signal.
- Impact: AC16 reads as `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh && bash tests/test-hooks.sh && bash tests/test-meta.sh`.

## 2026-09-29 Baseline test state before T1
- `tests/test-hooks.sh`: 709/709. `tests/test-kit-foldin-hooks.sh`: 97/97.
- `tests/test-meta.sh`: 878/879. The one failure is `docs/FEATURES.md is fresh`: the generated registry lags the spec files already on this branch. It predates this build; the regenerate runs once at the end of the build, after the new files exist.

## 2026-09-29 Validation preflight and per-task re-audit
- The last validate line for rid `harvest-sweep-spec` is a `skipped` NEEDS REVISION entry, so `/kit:execute`'s preflight would dispatch a validator. By operator decision no further validation round runs: the ledger records `validate skipped "operator decision: last folds approved with no further validation round"`, and Status stays APPROVED.
- The per-task `kit:recheck-verifier` re-audit (execute.md step 2c-1, advisory) is not dispatched per task; each task gets one fresh `kit:task-verifier`, and the whole build gets one integration verification at the end.

## 2026-09-29 T1 shared stager
- T1 (DEC-85, DEC-86): the sweep suite lives in `tests/test-harvest-sweep.sh`, not `tests/test-hooks.sh`, by operator brief.
- Change: `_stage_candidates(ledger, glossaries, candidates, extra_known=())` holds the lock, read-known, dedup, and append block. `extra_known` is accepted and not read yet; T9 wires it.
- Impact: hook behavior is unchanged. The per-call summary print stays in `_harvest_payload`. All 97 existing kit-foldin tests pass unedited.

## 2026-09-29 T2 claude adapter
- Change (DEC-43, DEC-44, DEC-60; AC1 claude parts): `hooks/harvest_sweep.py` holds `list_claude_sessions()` (stat only, returns `{session_id, path, subagent_paths, last_activity}`), `load_claude(item)` (the normalized transcript), `newest_ts(t)`, `render(t, after_ts, max_chars)`, `is_trivial(t)`, and `is_self_harvest(t)`. Enumeration and load are separate calls so T5a can scan without parsing.
- Decision: the 60/40 split stays fixed. A share one side leaves unused is not lent to the other. Why: lending would let a huge subagent push the lead out, which is what the split prevents, and the hard cap keeps the AC6 prompt-size bound. Cost: a lead with no subagents renders at most 60% of `HARVEST_MAXCHARS`.
- Decision: a share keeps whole recent messages. When the newest message alone exceeds the share, its tail is kept, cut mid-line, so it loses its `<role>:` prefix.
- Decision: the `subagent: ` prefix lives in the normalized message text, not in `render`. A subagent line therefore reads `assistant: subagent: <text>`, and a subagent tool call reads `tool: subagent: <name> <input>`.
- Decision: a user entry whose `content` is a bare string counts as a text message (typed prompts are stored that way). `tool_result` blocks are dropped. Tool input is `json.dumps(input)` cut to 200 characters.
- Decision: `is_trivial` counts user plus assistant messages across lead and subagents, so a lead that delegated all its work is not trivial.
- Decision: an entry with no parseable timestamp inherits the previous entry's ts in the same file, else the file mtime. `newest_ts` is the newest kept message ts; T5a stores it as `seen{id}.last_ts`.
- Decision: no time seam added. Nothing in the adapter reads the clock. T5a, the first task that needs "now", picks the seam (suggested: one `_now()` reading `HARVEST_SWEEP_NOW`).
- Impact: `is_self_harvest` compares `realpath` of the cwd to the state dir with a path-separator boundary, so `state-other` is not matched.

## 2026-09-29 T3 devin adapter
- Context (DEC-16, DEC-79; AC1, AC14, AC26 devin parts): the real `sessions.db` exists on this host. Only `sqlite3 -readonly <db> .schema` ran, no row content. The fixture copies the real `sessions` and `message_nodes` columns the adapter reads. The `chat_message` JSON shape (`role`, `content` as string or block list, `tool_calls[].function.name`) is spec-derived, not observed. Open question: confirm it against one real row before T20.
- Change: `list_devin_sessions()` returns items `{session_id, cwd, started, last_activity, hidden, main_chain_id}` or a `SourceFailure`. `load_devin(item)` returns the normalized transcript or a `SourceFailure`. `is_hidden(item)` is the predicate T5a uses to mark a hidden session done. `started` is `sessions.created_at`.
- Change: `SourceFailure` carries `source`, `error_class`, `message`, and `state_row()` (`STATE devin: <class>: <message>`). It is returned, never raised. `source_fail_update(cursor, source, failed)` keeps `cursor["source_fail"][source]`. `source_fail_tripped(cursor, source)` reads `HARVEST_SWEEP_SOURCE_FAIL_RUNS`. T13 maps the trip to rc 5.
- Decision: a locked or busy db retries once after 0.2s inside the same call. Any other sqlite error, including a missing column, fails at once. A dangling `main_chain_id` falls back like a null one.
- Decision: a tool-role row keeps its content cut to 200 characters. Each `tool_calls` name becomes its own `tool` line, so the text of an assistant node and its calls stay separate lines.
- Deviation (T2 code): `render` put same-timestamp messages in reverse order, because `_take_recent` returns newest first and the sort is stable. A text block and its tool call share one entry timestamp, so claude output was affected too. Fix: reverse each share before the sort. The devin render assertion covers it.
- Deviation (test file): the spec row names `tests/test-hooks.sh`. Tests live in `tests/test-harvest-sweep.sh` per the earlier note.

## 2026-09-29 T4 launch-record attribution
- Change (DEC-19, DEC-23; AC1 attribution): `load_launch_records()` reads the record file once and returns the valid JSON objects. `attribute(t, records)` sets `lead_session_id` in place and returns it. The run calls the first once, then the second per Devin session after `load_devin`.
- Decision: the brief match reads the first `user` message in the normalized transcript. The transcript already holds only kept messages, so "first kept user message" is that.
- Decision: a matching record with no parseable `ts` sorts after every dated match. With only such records, the first listed wins.
- Decision: `attribute` writes one stderr line per attribution naming session, lead, and brief. This is the "log the choice" line. Non-JSON-object lines (a bare list) are skipped like malformed ones.
- Impact: attribution of a claude session is a no-op. The spec's Devin-only rule holds in the function, not only in the caller.

## 2026-09-29 T5a selection and cursor
- Change (DEC-18, DEC-28, DEC-30, DEC-60, DEC-71; AC6, AC25, AC20 `seen{}` part, AC1/AC26 hwm parts): `run_selection(process, schedule_hours=6, max_sessions=20)` selects, loops per session, and writes `cursor.json` after each one. `process(t, rendered_delta)` returns True on success. Any other value marks the session failed: not done, hwm held. T7a hangs fail counts, the limit hold, and the stop rules on that `ok` line. T14 resolves the config key for `max_sessions`.
- Decision: the clock seam is `_now()`, which reads `HARVEST_SWEEP_NOW` (epoch seconds) else `time.time()`.
- Decision: classification and processing run in one oldest-first pass. A hidden or self-harvest or trivial session goes to `done{}` without counting against the cap. A processing attempt counts against it, success or failure. The pass stops taking sessions at the cap and returns the rest unloaded as `deferred`, which T5b turns into the lag line.
- Decision (lead): `max_sessions` is one run-wide budget. Eligible sessions of all sources are taken in global `last_activity` order, oldest first, so a busy claude backlog cannot starve devin. Why: DEC-55 bounds a run at 21 Haiku calls (20 extractions plus 1 probe), and a per-source cap breaks that bound once `sources = "claude devin"`. Cursors, `done{}`, `seen{}`, hwm, and `deferred` stay per source. Filtered and trivial sessions still do not count.
- Decision: the hwm advances over the longest settled prefix of the scan. A quarantined id counts as settled, so quarantine can free the hwm. T7b owns the lift.
- Decision: a session whose rendered delta is empty is marked done without calling `process`. Why: nothing new to read, and `seen{}` stays as it was.
- Decision: a source with no cursor entry gets its first-run hwm written at the end of the run, even when nothing was selected. Why: otherwise a quiet first run would slide the window forward on the next run and skip sessions. Later runs write only after a session settles.
- Decision: a `SourceFailure` from a lister or a loader ends that source for the run and is returned as `source_failure`. `source_fail_update` is not called here.
- Bug caught in test: pruning `done{}` by hwm made the next `_advance_hwm` see the pruned prefix as unsettled. Sessions below the current hwm now count as passed.
