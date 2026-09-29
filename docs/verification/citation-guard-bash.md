# Verification: citation-guard runs as bash plus jq

Verdict: PASS, one negative control pending a rerun (NC4)

Spec: `docs/specs/SPEC-356-citation-guard-bash.md` (VALIDATED, revision 3). Change: `hooks/citation-guard.sh` (port), `hooks/citation-guard.py` (removed), `tests/test-kit-foldin-hooks.sh`. Implementer: Devin (`swe-2-high`, headless, `--permission-mode dangerous`, scope-fenced to the worktree). The orchestrator wrote the spec, the goldens, and the harness, and made two review fixes.

## Checks

| Check | Command | Result |
|---|---|---|
| Parity, every golden, UTF-8 locale | `bash tests/test-citation-guard-parity.sh` | `citation-guard parity: 61 passed, 0 failed` |
| Latency, ~20 MB transcript with a 5 MB line | same test, last line | PASS, 310 to 742 ms on a loaded machine (load average near 35); the Python took 132 to 375 ms on the same fixture |
| Parity under bash 3.2 | same, `/bin` first on PATH | `61 passed, 0 failed` |
| Foldin suite | `bash tests/test-kit-foldin-hooks.sh` | `Passed: 97 / 97` |
| No Python | `grep -c python3 hooks/citation-guard.sh` | `0` |
| Real transcripts | fresh Opus review: Python vs the port on 1,002 real transcripts and 14,077 real assistant texts | identical kept text and refs; 154/154 identical exit codes and stderr on recent top-level transcripts |
| Negative controls | `lib/gate/negctl.sh <clone> "bash tests/test-citation-guard-parity.sh" "<mutation>"`, below | see below |

A real 16 MB transcript measured 521 ms in the review, over the 500 ms idle budget but far inside the 5 s hook timeout. Each cited file costs one jq process (about 15 ms), so a final message with many refs costs more; the largest real one had 46.

## Test plan coverage

| Test plan row | Evidence |
|---|---|
| P1 | parity line and latency line above |
| P2 | foldin suite above |
| P3 | not needed: the port runs no awk (jq regex and jq line counts) |
| P4 | `grep -c python3` above |
| P5 | measured under load, see the note above |
| NC1 to NC6 | table below |

## Goldens

61 cases, generated from the `ce08a00b` shim and `.py` by `tests/fixtures/citation-guard-parity/gen-expected.sh`, under `LANG=LC_ALL=en_US.UTF-8`. Five goldens are overridden to exit 0 silently where the Python crashed (the recorded divergence). Two harness bugs were found and fixed on the way: `ROOT` substitution rewrote an env var's name (found by the implementer), and an empty env array failed under bash 3.2 (found by the review). `lone-surrogate-final` is red on the port's first head (`042b7705`: exit 2 against the golden's 0).

## Negative controls

Rerun on the final head `d36a068c`, serially, in a scratch clone, with the parity test as the test command. NC4 went red under its mutation, but its restore run also failed: the load average was 198, and the parity test's 2 s latency line tripped. NC4 needs a rerun on a quieter machine.

| # | Mutation | Under mutation | Verdict |
|---|---|---|---|
| NC1 | skip the fence strip | Exit 1 | PASS |
| NC2 | keep the first assistant text instead of the last | Exit 1 | PASS |
| NC3 | treat `true` as strict | Exit 1 | PASS |
| NC4 | count lines with `wc -l` | Exit 1 | PENDING: restore run failed at load average 198 |
| NC5 | one jq pass that aborts at the first bad line | Exit 1 | PASS |
| NC6 | strip inline spans line by line | Exit 1 | PASS |

## Validation

Two fresh Opus rounds. Round 1 returned NEEDS REVISION: the UTF-8 locale trap, missing goldens, and a jq-regex design. Round 2 returned APPROVED with critical=0 after a sweep of every Unicode code point and 40k fuzz strings against Python.
