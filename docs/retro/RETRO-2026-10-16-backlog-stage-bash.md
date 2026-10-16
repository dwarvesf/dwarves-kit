# Retro: backlog-stage runs as bash plus jq (SPEC-408)
Date: 2026-10-16
Sprint: one session, third of the four remaining Python hook ports

Answers below were drafted by the lead from the session record, not collected one question at a time.

## Metrics
- Goldens: 204 cases generated from the Python before the port, each with the exact prompt and its byte count
- Real transcripts: 204 replayed through both hooks on the final head with the model stubbed, identical prompts, staging, and stderr (an earlier 400-transcript replay found the trailing newline)
- Fresh review rounds: none; the proof is the corpus, the real-data replay, and the negative controls
- Negative controls: 8

## What worked
- Starting from the previous port's review findings. The Linux `stat` bug, the temp-file leak, the argument-length limit, the unset-HOME bug, and the universal-newline and BOM classes were fixed in the first cut, and a corpus case pins each.
- Replaying real transcripts and comparing SHA-256 of the prompt files. It found a trailing newline (`jq -r` where `-j` was needed) that all 177 corpus cases missed, because the harness reads files through `$(cat)`.
- The stub extractor now records the prompt's byte count, so the corpus can see a trailing byte too.

## What hurt
- The default extractor is the real `claude` binary. A corpus case that left the extractor at its default would have made a live model call and written `.claude.json` backups into the sandbox. The case was removed; the default command is covered by reading, not by running.
- The detached child needs a process group of its own, and macOS has no `setsid`. `set -m` gives the group; a session would need a helper binary. The gap is recorded in the spec.

## Action items
- None for the operator.

## Also hurt
- Every negative control stalled for 15 minutes or more in its final green run. `negctl.sh` ignores TERM after its restore step and `hu_run_capture` ended its watchdog with TERM, so each case waited for the per-case alarm. It took four attempts, one of them blaming machine load, to find it. Look at which process holds a wait before blaming the machine.
