# Proof of done: wrap land ends on one outcome line

`wrap land` now prints exactly one `LAND:` line on stdout, last, after the `PROOF OF DONE` block, so a caller reads the result with `| tail -1` instead of grepping for `merged #|REFUSED|BLOCK|PULL`. Additive: every existing line, stderr refusal, and exit code is unchanged.

Code: `lib/wrap/wrap-land.sh` (`cmd_land` is a wrapper over `_land_run`; `_land_tidy` records pull and worktree state). Tests: `sec_outcome` plus one row each in `sec_landed` (TC1), `sec_draft`, and the `PB1` tail window in `tests/test-wrap-land.sh`.

## Outcome lines

| Path | Last stdout line |
|---|---|
| merged | `LAND: merged #42 (<sha7>) pull=ok worktree=removed` |
| merged, `--no-pull` | `LAND: merged #42 (<sha7>) pull=skipped worktree=removed` |
| merged, main checkout on another branch (exit 2) | `LAND: merged #42 (<sha7>) pull=blocked worktree=removed` |
| already landed | `LAND: already landed (content already on origin/main) pull=ok worktree=removed` |
| `--draft` | `LAND: draft #42 opened` |
| refused or failed | `LAND: refused (<step>, exit <rc>)`, e.g. `refused (preflight, exit 1)`, `refused (pr, exit 2)` |

## Green run

```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output:
test-wrap-land: 16 sections, 15 ran, 1 cached (21 checks credited)
test-wrap-land: all 750 passed
Verdict: PASS
```

Neighbouring suites that source or call `wrap-land.sh`:

```
Command: bash tests/test-proof-captured-output.sh; bash tests/test-wrap-adopt.sh; bash tests/test-wrap-cli.sh
Exit: 0
Output:
test-proof-captured-output: all 44 passed
test-wrap-adopt: all 210 passed
test-wrap-cli: all 22 passed
Verdict: PASS
```

## Negative control

```
Command: git checkout -- lib/wrap/wrap-land.sh && LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 1
Output:
  FAIL TC1: the last stdout line is the LAND outcome
  FAIL draft_new_pr_is_draft_with_proof: the last stdout line is the LAND outcome, after the proof block
  FAIL outcome_merged: the last line is the merged outcome
  FAIL outcome_merged: exactly one LAND line
  FAIL outcome_merged: the proof block comes before the LAND line
  FAIL outcome_no_pull: the last line says pull=skipped
  FAIL outcome_pull_blocked: the last line says pull=blocked
  FAIL outcome_refused_dirty: the last line is the refused outcome
  FAIL outcome_refused_dirty: the LAND line is on stdout, the refusal text is not
  FAIL outcome_refused_pr: the last line names the step and exit
  FAIL outcome_refused_pr: exactly one LAND line
  FAIL outcome_usage: the last line is the refused outcome
test-wrap-land: 738 passed, 12 FAILED of 750
Verdict: RED as expected
```

The code change was reverted with the new tests kept, 12 rows went RED, then the saved file was copied back (`cmp` identical) and the suite returned to 750 passed.

## Not proven

- The `<step>` in a refusal is the last phase entered, not the specific refusal message. The message itself stays on stderr where it was.
- A refusal after a verified merge cannot read `refused`: that run reads `merged` with the pull and worktree state, because the merge happened.
- A killed run (SIGKILL) prints nothing; a caught SIGINT returns 130 through the wrapper and reads `refused`.
