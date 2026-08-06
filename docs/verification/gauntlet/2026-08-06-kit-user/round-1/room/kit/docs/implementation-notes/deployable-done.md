# Implementation notes: SPEC-095 conditional deployable-done (kit-hardening SG-07)

Delta from SPEC-095 / ADR-0028 "Conditional deployable-done" property.

## 2026-07-02 Deployable IS the existing `stateful` proof class, not a new classifier

Context: the SG-07 goal file and SPEC-095 both call for deployability to be "explicit +
testable" without reinventing the ADR-0025 proof machinery.
Decision: `deployable` is a one-line relabel of `lib/gate/proof-ledger.sh classify()`'s
`stateful` output (`stateful -> yes`, everything else -> `no`), added as a brand-new
function + case-arm; `classify()`'s and `check()`'s bodies are byte-unchanged.
Why: the deploy/rollout/production/migration/schema/database/persistent-state keyword set
`classify()` already scores against is exactly the definition of "runs somewhere" ADR-0028
uses for deployable work. A second, parallel classifier would drift from `classify()` over
time (two keyword lists to keep in sync) and would risk a repo being told "deployable" by
one path and "stateful, needs proof" by another. Reusing the SAME function call means the
two can never disagree.

## 2026-07-02 UAT is a documented contract, not a new hard grep in `check()`

Context: the goal contract explicitly warns against tightening the shared `check()` stateful
branch, since other repos consume `lib/gate/proof-ledger.sh` via `~/.claude/dwarves-kit` and
already have stateful proofs that predate any UAT convention.
Decision: the UAT/acceptance requirement lives in AGENTS.md prose and the
`well-formed-proof.md` fixture, not as a `grep -qi 'UAT'` added to `check()`'s stateful
branch.
Why: `check()`'s stateful branch requirement (`rollback|[UNAVAILABLE` + `Command:|Exit:`)
already ships in every ADR-0025-adopted repo. Adding a hard UAT requirement there would
retroactively BLOCK every existing stateful proof that does not carry that exact string --
exactly the "if ANY previously-green test breaks, you tightened the shared path" failure
mode the goal file warns against. The contract still bites: AGENTS.md tells an agent what a
complete deployable proof looks like, and AC2/AC5 test that the contract is documented and
that a well-formed example (with UAT) satisfies the existing gate -- the gate's actual pass
condition (rollback + Command/Exit) is unchanged.

## 2026-07-02 Test harness mirrors `test-lane-escalation.sh` / `test-ship-gate-fail-closed.sh`

Context: several `tests/test-*.sh` files build disposable git repos in `mktemp -d` and drive
`proof-ledger.sh` / `ship-gate.sh` directly against crafted commits.
Decision: `tests/test-deployable-done.sh` follows the same shape: `mkrepo()` builds an
"adopted" repo (a `docs/verification/README.md` marker), a `base()` helper captures the SHA
BEFORE the load-bearing commit, and `run_classify`/`run_deployable`/`run_check` wrap the
library calls with an explicit `<base>` argument (not a recomputed `$(base "$dir")` at call
time, which would silently compare the current HEAD to itself once a second commit lands --
caught during the first test run, see below).
Why: consistency with the existing harness family keeps the negative-control style ("empty
proof BLOCKS") legible to anyone who has read `test-ship-gate-fail-closed.sh`, and isolates
the override-log path via `DWARVES_KIT_LOG_DIR` so the test never touches the real
`~/.claude/dwarves-kit/logs/proof-overrides.log`.

## 2026-07-02 `tests/test-ship-gate-profiles.sh` fails open in this sandbox (pre-existing, not this change)

Context: the VERIFY block lists `tests/test-ship-gate-profiles.sh` as a shared-path safety
check.
Finding: it exits 1 with `[NO EXECUTABLE CHECK: ship-gate hook not installed at
$HOME/.claude/dwarves-kit/hooks/ship-gate.sh]` in this dev sandbox, because the kit is not
installed to `~/.claude/dwarves-kit` here (it drives the REAL installed hook, not the repo
copy, by design -- see its own header comment).
Confirmed pre-existing: `git stash` (reverting every change in this branch) reproduces the
identical failure, so this is an environment precondition, not a regression introduced by
SPEC-095. All other listed shared-path tests (`test-proof-dir-layout.sh`,
`test-proof-visual-evidence.sh`, `test-ship-gate-fail-closed.sh`, `test-meta.sh`,
`test-hooks.sh`) exercise `lib/gate/proof-ledger.sh` and `hooks/ship-gate.sh` from the repo copy
and stay green.
