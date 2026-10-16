# Verification: backlog-stage runs as bash plus jq

Verdict: PASS

Spec: `docs/specs/SPEC-408-backlog-stage-bash.md`. Change: `hooks/backlog-stage.sh` (port), `hooks/backlog-stage.py` (removed), `lib/reflect/hook-util.sh`, `lib/reflect/staging-format.jq`, `tests/lib/hook-parity.sh`.

## Green run

```
Command: bash tests/test-backlog-stage-parity.sh
Exit: 0
Output:
backlog-stage parity: 204 passed, 0 failed
  PASS 2 MB transcript, inline: prompt of 2097962 bytes, candidate staged
  PASS 2 MB transcript, detached: prompt of 2097962 bytes, candidate staged
Verdict: PASS
```

## Checks

| Check | Command | Result |
|---|---|---|
| Parity, every golden, UTF-8 locale | `bash tests/test-backlog-stage-parity.sh` | `204 passed, 0 failed` (goldens generated from the Python at `b9306b37` through its shim, including the exact prompt and its byte count) |
| Parity under the macOS system tools | the same test with `/bin/bash` (3.2.57) and `/usr/bin/jq` (1.7.1) first on PATH | `204 passed, 0 failed` |
| Real data | the newest 204 session transcripts on this machine (subagent files excluded) through the Python at `b9306b37` and the port, the model call stubbed to a fixed answer, the real board for dedup; compared by SHA-256 of the prompt, the staging file, and stderr with paths and dates folded | identical 204, different 0; 73 of them reached the extractor and staged |
| Intake-sweep goldens | `bash tests/test-intake-sweep-parity.sh` | `160 passed, 0 failed` (one golden regenerated, see the implementation notes) |
| Helpers | `bash tests/test-hook-util.sh`, `bash tests/test-hook-parity-lib.sh` | `30 passed, 0 failed`; `21 passed, 0 failed` |
| Grammar twin | `bash tests/test-staging-format-jq.sh` | `5 passed, 0 failed` |
| Existing hook suites | `bash tests/test-intake-sweep.sh`, `bash tests/test-kit-foldin-hooks.sh` | `31 passed, 0 failed`; green inside `run-all` |
| Registry lint | `bash tests/test-config-registry.sh` | `59/59 passed` (the six `BACKLOG_STAGE_*` variables are registered) |
| Contract lint | `bash tests/test-kit-contract.sh` | `25 passed, 0 failed` |
| No Python | `grep -c python hooks/backlog-stage.sh` | `0` |
| Changed suites | `bash tests/run-all.sh --changed` | see the last section |

## Negative controls

Each ran through `lib/gate/negctl.sh` in its own scratch clone of the final head, with a hard `timeout 600`: green, mutate (`docs/verification/backlog-stage-bash-nc.sh <n>`), red, restore with `git checkout HEAD --`, green. The test command is `bash tests/test-backlog-stage-parity.sh`.

| # | Mutation | Under mutation | Verdict |
|---|---|---|---|
| NC1 | count brackets to the last `]`, not the matching one | 2 of 204 red | PASS |
| NC2 | read a string `content` as text | 2 of 204 red | PASS |
| NC3 | never write the throttle stamp | 6 of 204 red | PASS |
| NC4 | drop the board dedup | 8 of 204 red | PASS |
| NC5 | keep the payload file after `--staged-run` | 18 of 204 red | PASS |
| NC6 | exempt `--staged-run` from the `BACKLOG_STAGE_AUTO` gate | 1 of 204 red | PASS |
| NC7 | skip the forward-intent pre-filter | 7 of 204 red | PASS |
| NC8 | hand the extractor the transcript text plus a trailing newline | 120 of 204 red | PASS |

One block as `lib/gate/negctl.sh` printed it, its Output slot trimmed to the summary lines:

```
## Negative control (negctl)
Command: bash tests/test-backlog-stage-parity.sh
Exit: 0 (green before mutation)
Output:
  backlog-stage parity: 204 passed, 0 failed

Mutation: bash docs/verification/backlog-stage-bash-nc.sh 1
Changed: hooks/backlog-stage.sh
Exit: 1 (under mutation, RED expected)
Output:
  backlog-stage parity: 202 passed, 2 failed

Restore: git checkout HEAD -- hooks/backlog-stage.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The first rounds of these controls stalled for 15 minutes or more in the green run after the restore. The cause was a TERM that `negctl.sh` ignores from its restore step on and that `hu_run_capture` needed to end its watchdog; the fix and its test are in the last two `hook-util` commits, and the controls above ran after it (two to four minutes each).

## Not proven

- A real SessionEnd payload was not captured live; the hook reads one `transcript_path` and the corpus covers its shapes.
- The default extractor, the real `claude` binary, is covered by reading, not by running: a run would make a live model call.
- The recorded divergences (spec, Failure modes) are the known and judged unrealistic ones: the process group in place of a new session, `NaN` in a transcript line, a candidate field that is a list or object.
- jq 1.6 is untested; the floor is the two versions run here.
