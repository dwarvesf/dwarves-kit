# Implementation notes: ship-gate subject-word trap

No spec. The contract is the operator's task brief: a tests-only branch must not classify stateful because a commit subject says "restore", and real stateful changes must keep their verdict. This note carries the decisions the brief left open.

## Where the signal is cut

Context: `lib/gate/proof-ledger.sh` `classify()` joins the changed paths and the commit subjects into one blob, then greps the blob for stateful keywords. `hooks/ship-gate.sh` calls it through `check()`; no other classifier reads subjects.
Decision: read the subjects only when some non-doc changed path is not a test path. Paths are matched in every case.
Why: a subject describes the change it rides with. On a tests-only diff the subject describes a test, and a negative-control commit names the revert step ("restore"). The paths are the ground truth the subject only summarises.
Alternatives: (1) match only the conventional-commit type/scope. Rejected: `fix(gate): add the nightly backup` would lose the real signal on a source change. (2) Drop subjects entirely. Rejected: it weakens the gate for source changes whose paths carry no keyword. (3) Skip subjects when every path is under `tests/` only. Rejected as too narrow: the kit's own tests are `tests/test-*.sh`, but adopters use `foo_test.go`, `foo.test.ts`, `test_foo.py`, `spec/`.

## Fail-closed boundary

Decision: the guard only narrows the tests-only case. A diff with any path outside the test pattern keeps the subject signal exactly as before.
Why: the brief requires an ambiguous branch to still classify stateful. A mixed code+test diff is ambiguous, so it keeps the old behaviour (pinned by the code+test "backup" case).
Tradeoff: a stateful change hidden entirely inside test paths, with no keyword in any path, now reads behavioral. It still owes a green run and a negative control, so the gate does not open; only the rollback-note requirement drops. A test fixture under a migrations or deploy path still matches on the path.

## Test-path pattern

Decision: a root `tests/`, `test/` or `__tests__/` tree, a `__tests__/` dir anywhere, or a code file (py, go, rs, rb, js, jsx, ts, tsx, sh, bash, swift, kt, java, ex, exs) named `test_*`, `*_test.*` or `*.test.*`.
Why: covers the kit's `tests/`, Go `_test.go`, JS `.test.ts`, Python `test_*.py`. `latest.json` and `contest.py` do not match because the pattern needs `.` or `_` before `test.`.
Probe change: the second draft matched `test/` at any depth and `test_*` for any extension. An adversarial probe showed `db/seeds/test_accounts.sql` and `k8s/overlays/test/kustomization.yaml` read as tests, so a "seed ... production database" or "rollout" subject was skipped. Nested test dirs and data/config extensions (.sql, .yaml, .json, .toml, .env) now never count as tests. A monorepo with `pkg/foo/tests/` keeps reading subjects, the fail-closed direction.
Review change: the first draft also matched `spec/` and `.spec.`. The review lens showed `api/spec/openapi.yaml` or `openapi.spec.yaml` is production contract, not a test. Both were dropped. RSpec and `.spec.ts` repos keep the old subject-reading behaviour, which is the fail-closed direction.

## Renames list both sides

Context: the probe found `_changed` ran `git diff --name-only` with rename detection on. A `git mv db/migrations/0042_legacy.sql tests/fixtures/0042_legacy.sql` listed only the destination. The diff read as tests-only, the subject was skipped, and the verdict dropped from stateful to behavioral.
Decision: every `git diff --name-only` in `_changed` passes `--no-renames`, so the deleted source path is listed too.
Why: the source path carries the stateful signal on its own (`migrat`), and it is a non-test path, so the subject is read as well. Before this branch the subject alone caught it; the guard made the path loss visible.

## Guard must not use grep -q under pipefail

Context: the review lens found the first draft piped into `grep -qv`. With `set -o pipefail`, `grep -q` exits on its first match, the upstream `grep -v` takes SIGPIPE (141), and the pipeline status is 141. On a large diff where a source path sorts before thousands of test paths, the guard read "no source path" and skipped the subjects. That fails open.
Decision: capture the filtered list and test `[ -n ... ]`, so both greps drain their input.
Proof: case (b3) builds a source file plus 4000 test paths with a "backup" subject. It failed on the draft (read behavioral) and passes on the fix (stateful).

## Existing negative control needed a second strip

Context: the md-only control in `tests/test-classify-md-inert.sh` built a pre-fix lib by stripping the inert-FIRST block up to the `subjects=` line. The new guard also skips subjects on an md-only diff, so the stripped lib read md-only "migrate" as behavioral and the control went vacuous.
Decision: the control now strips both the inert-FIRST block and the new guard, restoring the unconditional subjects read. It reproduces the original bug again.

## PROOF_LEDGER_LIB override in the test

Decision: the suite honours `PROOF_LEDGER_LIB` to pick the lib under test.
Why: `negctl.sh --base-ref` runs the test command inside an extract of the base ref. The new cases do not exist at that ref, so the command runs this branch's suite against the extracted lib.
