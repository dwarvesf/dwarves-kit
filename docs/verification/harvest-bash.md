# Verification: harvest runs as bash plus jq

Verdict: PASS

Spec: `docs/specs/SPEC-409-harvest-bash.md`. Change: `hooks/harvest.sh` (port), `hooks/harvest.py` (removed), `hooks/harvest_lib.py` (the sweep's library and operator verbs, moved out of `harvest.py`), `tests/lib/hook-parity.sh`.

## Green run

```
Command: bash tests/test-harvest-parity.sh
Exit: 0
Output:
harvest parity: 171 passed, 0 failed
Verdict: PASS
```

## Checks

| Check | Command | Result |
|---|---|---|
| Parity, every golden, UTF-8 locale | `bash tests/test-harvest-parity.sh` | `171 passed, 0 failed` (goldens generated from the Python at `b9306b37` through its shim, including the exact prompt and its byte count) |
| Parity under the macOS system tools | the same test with `/bin/bash` (3.2.57) and `/usr/bin/jq` (1.7.1) first on PATH | `171 passed, 0 failed` |
| Real data | the newest 204 session transcripts on this machine (subagent files excluded) through the Python at `b9306b37` and the port, the model call stubbed to a fixed answer; compared by SHA-256 of the prompt, the ledger, and stderr with paths and dates folded | identical 204, different 0; 185 of them reached the extractor and staged |
| Sweep suite | `bash tests/test-harvest-sweep.sh` | `Passed: 637 / 637`, with the library imported as `harvest_lib` |
| Foldin suite | `bash tests/test-kit-foldin-hooks.sh` | `Passed: 99 / 99`, including eight concurrent harvests staging one row |
| Helpers | `bash tests/test-hook-util.sh`, `bash tests/test-hook-parity-lib.sh` | `30 passed, 0 failed`; `22 passed, 0 failed` |
| No Python in the hook | `grep -c python hooks/harvest.sh` | `2`: the two routes to `hooks/harvest_sweep.py` for the operator and sweep verbs |
| Changed suites | `bash tests/run-all.sh --changed` | `all 51 suites passed, 0 skipped for missing tooling` |

## Negative controls

Each ran through `lib/gate/negctl.sh` in its own scratch clone of the final head, with a hard `timeout 600`: green, mutate (`docs/verification/harvest-bash-nc.sh <n>`), red, restore with `git checkout HEAD --`, green. NC2 to NC9 use `bash tests/test-harvest-parity.sh`; NC1 uses `bash tests/test-kit-foldin-hooks.sh`.

| # | Mutation | Under mutation | Verdict |
|---|---|---|---|
| NC1 | take no lock around the dedup and the append | 1 of 99 red (`row 4c`, expected 1 row, got 7) | PASS |
| NC2 | never apply the fuzzy threshold | 3 of 171 red | PASS |
| NC3 | ignore the glossary files | 6 of 171 red | PASS |
| NC4 | let one batch stage the same slug twice | 1 of 171 red | PASS |
| NC5 | keep the payload file after a detached child | 14 of 171 red | PASS |
| NC6 | fire the stop-trigger on every turn | 13 of 171 red | PASS |
| NC7 | keep a timed-out extractor's stdout | 1 of 171 red | PASS |
| NC8 | drop the sweep-child recursion guard | 1 of 171 red | PASS |
| NC9 | append to a ledger that is not valid UTF-8 | 1 of 171 red | PASS |

One block as `lib/gate/negctl.sh` printed it (NC9), its Output slot trimmed to the summary lines:

```
## Negative control (negctl)
Command: bash tests/test-harvest-parity.sh
Exit: 0 (green before mutation)
Output:
  harvest parity: 171 passed, 0 failed

Mutation: bash docs/verification/harvest-bash-nc.sh 9
Changed: hooks/harvest.sh
Exit: 1 (under mutation, RED expected)
Output:
  harvest parity: 170 passed, 1 failed

Restore: git checkout HEAD -- hooks/harvest.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- A real PreCompact, SessionEnd, or Stop payload was not captured live; the hook reads `transcript_path` and `session_id`, and the corpus covers their shapes.
- The default extractor, the real `claude` binary, is covered by reading, not by running: a run would make a live model call.
- The sweep verbs run in Python, so the Python on the host must still work for them; the hook itself no longer needs it.
- The recorded divergences (spec, Failure modes) are the known and judged unrealistic ones: the process group in place of a new session, `NaN` in a transcript line, a candidate field that is a list or object, a lone `\r` as a line break in a jsonl file.
- jq 1.6 is untested; the floor is the two versions run here.
