# Implementation notes -- backlog-stage-bash

Deltas from SPEC-408. Nothing here repeats what the spec already states.

## 2026-10-16 The harness hid a trailing newline; real transcripts found it

- Context: the first cut printed the transcript text through `jq -r`, which adds a newline after each output, so the prompt the model received ended with an extra `\n` after the text. All 177 corpus cases passed, because the harness reads a file back through `$(cat ...)`, which strips trailing newlines.
- Decision/Change: a replay of 400 real session transcripts through the Python and the port compared the prompt files by SHA-256 and found 90 mismatches. The cause was `-r` where `-j` was needed. The stub extractor now also records the prompt's byte count (`prompt.txt.size`), and every case reads it back, so a trailing byte shows in the corpus too.
- Why: a green corpus that cannot see a trailing byte is not proof of a byte-exact prompt, and the prompt is the one place the Python's bytes reach the model.

## 2026-10-16 The child keeps its parent's opt-in gate

- Context: the Python parent spawned `python3 backlog-stage.py --staged-run`, bypassing the shim, so the child needed no `BACKLOG_STAGE_AUTO`. A first cut of the port exempted `--staged-run` from the gate; the goldens (through the shim) showed that `backlog-stage.sh --staged-run` without the variable does nothing.
- Decision/Change: no exemption. The detached child is `bash backlog-stage.sh --staged-run`, which inherits `BACKLOG_STAGE_AUTO` from its parent, so it passes the gate the way the shim already treats every entry.

## 2026-10-16 Process group, not session, for the detached child

- Context: the Python used `start_new_session=True`. macOS ships no `setsid`.
- Decision/Change: `set -m` before the background launch gives the child its own process group, and `nohup` keeps a hangup away from it. The existing foldin row 3e checks that the child's group differs from the invoker's, and it passes.
- Impact: the one recorded divergence of the design (spec, Failure modes).

## 2026-10-16 The bracket scan is a reduce, not a regex

- Context: `extract_json_array` counts `[` and `]` with no regard for JSON strings, so a `]` inside a string unbalances it (`stage-bracket-in-string-unbalances` pins the result: no candidates).
- Decision/Change: a `reduce` over the code points, tracking depth and the closing index, then `fromjson` on the slice. A regex or a JSON-aware scan would be smarter and would diverge.

## 2026-10-16 Real data

- 400 real session transcripts on this machine, with the model call stubbed to a fixed answer and the real board for dedup, went through the Python and the port: see `docs/verification/backlog-stage-bash.md` for the final counts.

## 2026-10-16 The hung negative control was a TERM that nobody could deliver

- Context: every `negctl.sh` run of the parity test finished its green and red runs in under a minute each, then spent 15 minutes or more in the green run after the restore. Each case waited for the per-case alarm. The earlier round that hung for two hours was the same stall without the alarm.
- Decision/Change: `negctl.sh` runs `trap '' INT TERM HUP` in its restore step and never undoes it, so the final run, and every hook it starts, ignores TERM. `hu_run_capture` ended its watchdog with TERM, so the wait on the watchdog ran out the whole 120 s extractor timeout. The watchdog now gets SIGKILL, and its sleep is reaped after it. `tests/test-hook-util.sh` runs the helper under `trap '' TERM` and fails the old code.
- Why: the stall hit any hook that used the helper (intake-sweep too), only under a caller that ignores TERM, which is exactly what a proof run is.

## 2026-10-16 The harness change moved one intake-sweep golden

- Context: the harness now expands `@HOME@` and `@CWD@` in seeded text. The intake-sweep case `jsonl-path-absolute` seeds `@HOME@/abs.jsonl` as an absolute path, which until now stayed a literal relative path, so its golden recorded "nothing staged" and the case never tested an absolute path.
- Decision/Change: the intake-sweep goldens were regenerated from the Python at `b9306b37`; exactly one line changed (that case now stages, as the Python does with a real absolute path). The registry also gained the six `BACKLOG_STAGE_*` variables the bash hook reads, because the drift lint scans `.sh` and never saw them in the Python.
