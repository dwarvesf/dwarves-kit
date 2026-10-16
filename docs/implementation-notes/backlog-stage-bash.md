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
