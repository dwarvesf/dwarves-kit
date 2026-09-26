# Proof of done: every spec is validated in a fresh context

2026-09-26. Spec: `docs/specs/SPEC-320-spec-autovalidate.md`. Lane: full. Files: `docs/WORKFLOW.md`, `commands/spec.md`, `commands/execute.md`, `commands/wrap.md`, `commands/spec-validate.md`, `tests/test-hooks.sh`, `tests/test-meta.sh`, `tests/test-e2e.sh`, `tests/test-gate-ledger-plan-record.sh`, `tests/test-wrap.sh`, `docs/CHANGELOG.md`, `docs/MANUAL.md`, `docs/FEATURES.md` (regenerated), `docs/implementation-notes/spec-autovalidate.md`, this file.

Acceptance: `/kit:spec` and a `/kit:execute` preflight dispatch a fresh-context, read-only validator; the lead records `Validate ran` on APPROVED only; wrap step 10 workers stop with `VALIDATE PENDING`; the Validate row is `run-lite` on normal and backfill, so the plan lists it and the normal ship-gate does not refuse.

## Red first

The T2 asserts ran before any matrix or command edit.

| Suite | Red result | What failed |
|---|---|---|
| `tests/test-hooks.sh` | Passed 502 / 510, Failed 8 | `plan: normal lists validate lite`, `plan: backfill lists validate lite`, six `progress` pins at `/10` |
| `tests/test-meta.sh` | Passed 861 / 879, Failed 18 | all 17 command-wiring asserts, plus FEATURES freshness |
| `tests/test-e2e.sh` (pre-change matrix via `GATE_LEDGER_WORKFLOW`) | Passed 17 / 20 | `step 1/10 (grill)`, `step 6/10 (test-plan)`, `complete (10/10)` |
| `tests/test-gate-ledger-plan-record.sh` (pre-change matrix) | 19/41 passed | `'validate' is not a phase of lane 'normal'`; C14 `missing validate exits 64 (got 0)` |

## Green runs

| Command | Exit | Last lines |
|---|---|---|
| `bash tests/test-hooks.sh` | 0 | `Passed: 510 / 510` · `All tests passed.` |
| `bash tests/test-meta.sh` | 0 | `Passed: 879 / 879` · `All meta tests passed.` |
| `bash tests/test-e2e.sh` | 0 | `Passed: 20 / 20` · `Golden run green.` |
| `bash tests/test-gate-ledger-plan-record.sh` | 0 | `PASS C14 with a validate disposition exits 0` · `=== 41/41 passed ===` |
| `bash tests/test-command-emit-sweep.sh` | 0 | `Passed: 18 / 18` · `All command-emit-sweep tests passed.` |
| `bash tests/test-gate-vocab-recording.sh` | 0 | `PASS NEGATIVE CONTROL: 'verify' does NOT satisfy the 'review' gate` · `=== Summary: 20/20 passed ===` |
| `bash tests/test-wrap.sh` | 0 | `test-wrap: all 1196 passed` |
| `bash lib/registry/feature-registry.sh check` (after the T4 prose) | 0 | `feature-registry: docs/FEATURES.md is fresh` |
| `bash tests/test-outcome-emit-sweep.sh` (after bracketing the step-10 worker's `Spec ran`) | 0 | `Passed: 51 / 51` · `All outcome-emit-sweep tests passed.` |
| `bash tests/run-all.sh --changed` (final tree; covers every suite above) | 0 | `run-all: all 38 suites passed, 0 skipped for missing tooling` |

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-hooks.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/^| Validate | skip | run-lite | measure-twice | skip | run-lite |$/| Validate | skip | skip | measure-twice | skip | run-lite |/' docs/WORKFLOW.md
Changed: docs/WORKFLOW.md
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- docs/WORKFLOW.md
Exit: 0 (green after restore)
Verdict: PASS
```

## Test plan coverage

| Test plan case | Covered by | Run |
|---|---|---|
| Normal plan lists validate lite | `test-hooks.sh` `plan: normal lists validate lite`, `plan: backfill lists validate lite` | test-hooks green; negctl RED on the normal cell |
| Normal ship not refused | `test-hooks.sh` `check: normal ship without validate exits 0`, `required: normal unchanged (no validate)` | test-hooks green |
| Full ship refused on skipped Validate | `test-hooks.sh` `check: full with Validate skipped exits 1`, `check: full names the missing validate gate` | test-hooks green |
| Preflight ignores a failed validation | `test-hooks.sh` `preflight grep: a skipped validate line does not match`, `a ran validate line matches` (the exact grep from `commands/execute.md`) | test-hooks green |
| Honest direct record | `test-meta.sh` `spec-validate.md records ran on APPROVED only, skipped otherwise`, `records a Reviewer 6 critical as design-record skipped`, `no longer records ran on NEEDS REVISION` | test-meta green; emit-sweep and vocab-recording green on the kept literals |
| plan-record refusal | `test-gate-ledger-plan-record.sh` C14 (exit 64 naming validate; exit 0 with a disposition) | plan-record green |
| Tiny, bug untouched | `test-hooks.sh` `plan: tiny has no validate`, `plan: bug has no validate` | test-hooks green |
| Commands wired | `test-meta.sh` spec.md dispatch, prompt, tier, records, `VALIDATE PENDING`, order after `Spec ran`, reminder absent; execute.md grep, placement, stop, records; wrap.md split, both old sentences absent | test-meta green; test-wrap green on the new `reported:` literal |
| Live | `/kit:spec` on a throwaway idea in this worktree | recorded below (2026-09-26) |

## Live run (2026-09-26)

The lead ran the fresh-context dispatch against a scratch git repo (not this worktree), branch `feat/live-probe` (rid `live-probe`), holding a short-lived fixture spec at `docs/specs/SPEC-001-flag-rename.md`, with a scratch `KIT_LEDGER_DIR` pointed away from any real ledger. The lead recorded `Spec ran`, opened both timing brackets, and dispatched one fresh `general-purpose` subagent, model Sonnet, with `commands/spec.md` step 5's prompt verbatim (the spec path substituted).

The validator reported `invoked: kit:spec-validate`, verdict APPROVED (0 critical, 3 warnings), `design-bearing=no pass`, and left the scratch tree clean: `git status --porcelain` showed only the lead's own `ledger/`, no edits to the fixture spec, no Status flip. The lead then recorded per step 5. The scratch ledger read:

```
| GATE | spec | ran | SPEC-001-flag-rename approved, tasks=1
| OUTCOME | validate | start
| OUTCOME | design-record | start
| GATE | validate | ran | APPROVED critical=0 warnings=3 fresh agent=<id>
| GATE | design-record | ran | design-bearing=no pass
| OUTCOME | validate | end | caught=false dur_s=74
| OUTCOME | design-record | end | caught=false dur_s=74
```

and the (then-current) preflight grep matched: execute would not have re-dispatched.

**Limit:** this ran against the installed plugin's `spec-validate` (master text, unpatched); the dispatch prompt and the ledger records above are this branch's own `commands/spec.md` step 5 text. The reviewer content itself is not proof of this branch's `spec-validate.md` wording, only of the dispatch/record wiring.

**Preflight re-check with the NEW last-line grep (fix 1).** Reproduced the same ledger shape above in a fresh temp `KIT_LEDGER_DIR` (`gate-ledger.sh record`/`outcome` calls matching each line), then ran the exact new grep from `commands/execute.md`:

```
$ bash lib/gate/gate-ledger.sh show live-probe | grep -Ei '\| GATE \| validate \| ' | tail -1 | grep -Eq '\| (ran|override) \|'
$ echo $?
0
```

Exit 0: the last `validate` GATE line is `ran`, the grep matches, execute would not re-dispatch. Consistent with the recorded run.

## Limits

The command prose is checked by grep, not by running an agent. The Live row above is the only behavioral check of the dispatch, and was the lead's to run; the preflight-regex re-check above is a mechanical replay of that same ledger shape under the fixed grep.
