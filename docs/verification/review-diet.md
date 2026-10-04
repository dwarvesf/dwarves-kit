# Proof of done: review diet

Verdict: PASS for the six rules and their pins. Five other suites fail identically on `origin/master` (table below), so the change adds no red.

Scope: prose rules in `commands/spec.md`, `commands/spec-validate.md`, `commands/execute.md`, `commands/wrap.md`, `docs/WORKFLOW.md`, `docs/MANUAL.md`, plus asserts in `tests/test-meta.sh`. No code under `lib/gate`, `lib/classify` or `hooks/` changed.

## Rules and their pins

| Rule | Where the wording lands | Pin in `tests/test-meta.sh` |
|---|---|---|
| L lane copies the classifier | `docs/WORKFLOW.md` "Size the work first" | `WORKFLOW.md: a kit spec copies its lane from the classifier; full by habit is a misroute` |
| C1 round cap | `commands/spec.md` step 5 | `spec.md step 5: normal lane gets 1 validation round, full lane keeps ceiling 3` |
| C2 critical bar | `commands/spec-validate.md` "Critical bar" | `spec-validate.md: critical only if the spec's own tests would miss it` |
| C3 fold-diff check | `commands/spec.md` step 5 | `spec.md step 5: fold-diff check is the default re-check` |
| C4 warnings to notes | `spec.md`, `spec-validate.md`, `execute.md`, `wrap.md` | `spec.md and spec-validate.md route build-catchable warnings to implementation notes` |
| C5 model tier | `spec.md` (2 places), `execute.md`, `docs/MANUAL.md` | `spec.md validator tier ...` (replaced), `spec.md: no reviewer tier rides the lane any more`, `execute.md preflight dispatches the same tiers as spec.md step 5` |

## Runs

| Check | Command | Result |
|---|---|---|
| Red before the doc edits | `bash tests/test-meta.sh` with the 8 new or replaced asserts and the old docs | 8 FAIL, one per assert above, no other FAIL |
| Green after the edits | `bash tests/test-meta.sh` | 894 / 894, exit 0 |
| Negative control | revert the C1, C2 and C5 doc lines in `spec.md` and `spec-validate.md`, run `bash tests/test-meta.sh`, restore with `git checkout --` | 890 / 894: the C1, C2, C5 tier and old-wording asserts go red, nothing else |
| Affected suites | `bin/test-affected --base origin/master --no-cache` | 41 selected, 36 pass, 5 fail (all pre-existing, next table), 2 uncovered (the new spec and notes) |
| Registry freshness | `bash lib/registry/feature-registry.sh check docs/FEATURES.md` | `docs/FEATURES.md is fresh` after `check --fix` |
| No dashes | `grep -nP '\x{2013}\|\x{2014}'` over the new files and the added diff lines | no output |

## Failures that predate this change

Each suite ran on a `git archive origin/master` export and failed the same way.

| Suite | Failure on master | Same on this branch |
|---|---|---|
| `tests/test-gate-opt-out.sh` | 3 FAIL (two hard-path `.kit.toml` blocks, `hook reads config: hooks/harvest.sh`) | yes |
| `tests/test-install-contract.sh` | `PASS=2 FAIL=2` | yes |
| `tests/test-research-arch-contract.sh` | `row 7: dispatcher Step 2 is brownfield-gated` | yes |
| `tests/test-wrap-deploy.sh` | 145 of 146, `step 10 re-sizes the real diff before landing` | yes |
| `tests/test-wrap-report-lint.sh` | 134 of 135 | yes |

## Gate ledger

`start review-diet normal`, then `override Validate` (operator approved the design in session, fast path), `record spec ran`, `record build ran`. The review and ship gates stay open for the lead.
