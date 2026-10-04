# Proof of done: master green

Branch `fix/master-green`, base master 144c2279. Spec: `docs/specs/SPEC-388-master-green.md`. Notes: `docs/implementation-notes/master-green.md`.

Recorded runs below ran on a clean export of branch head `ed3e1d51` (the fix commit is `06693125`; the two later commits touch only docs). Two export shapes were used on purpose. A `git archive` export has no `.git`, so seven suites that read git state cannot pass on it by construction; `test-adopt` reads the git log and needs a full-history clone. Both shapes are labelled per block.

## Before and after

| Suite | master export exit | branch export exit | Change |
|---|---|---|---|
| test-gate-opt-out | 0 | 0 | none (already green) |
| test-gate-validate-round | 0 | 0 | none (already green) |
| test-config-registry | 0 | 0 | none (already green) |
| test-install-contract | 0 | 0 | none (already green) |
| test-research-arch-contract | 0 | 0 | none (already green) |
| test-adopt | 1 (clone shape; also 1 on export) | 0 (clone shape) | regenerated `lib/adopt/agents-known.sha256` |
| test-codex-hooks | 124 (hang) | 124 (hang) | none; host `codex` binary hangs |

## Recorded run

Suite 1, test-gate-opt-out, export of `ed3e1d51`:

```
Command: bash tests/test-gate-opt-out.sh
Exit: 0
Output: ALL PASS
Verdict: PASS
```

Suite 2, test-gate-validate-round (C12), export of `ed3e1d51`:

```
Command: bash tests/test-gate-validate-round.sh
Exit: 0
Output: === results: 196/196 pass, 0 fail ===
Verdict: PASS
```

Suite 3, test-config-registry (AC10), export of `ed3e1d51`:

```
Command: bash tests/test-config-registry.sh
Exit: 0
Output: === 59/59 passed ===
Verdict: PASS
```

Suite 4, test-install-contract, export of `ed3e1d51`:

```
Command: bash tests/test-install-contract.sh
Exit: 0
Output: PASS=4 FAIL=0
Verdict: PASS
```

Suite 5, test-research-arch-contract (row 7), export of `ed3e1d51`:

```
Command: bash tests/test-research-arch-contract.sh
Exit: 0
Output: Passed: 28 / 28
Verdict: PASS
```

Suite 6, test-adopt, full-history clone of `ed3e1d51` (it walks `git log -- AGENTS.md`, so an export cannot run it):

```
Command: bash tests/test-adopt.sh
Exit: 0
Output: PASS=55 FAIL=0
Verdict: PASS
```

Full list, full-history clone of `ed3e1d51`, run as `RUN_ALL_JOBS=3 bash tests/run-all.sh --all --time`: 197 suites ran, 0 skipped. Two were not green and neither is a kit defect:

| Suite | Result in the full run | Cause | Re-run result |
|---|---|---|---|
| test-codex-hooks | TIMED OUT at 300 s | host: `timeout 15 codex --version` exits 124 on this host, so the installed `codex` binary never returns, and the suite calls it with no time bound | unchanged, host fault |
| test-run-all-time | FAIL | the clone's `origin/master` had advanced to 7b2ca7aa (#906 changed `tests/run-all.sh`) and this suite diffs against `origin/master:tests/run-all.sh` | passes with `origin/master` pinned to the base, below |

```
Command: bash tests/test-run-all-time.sh
Exit: 0
Output: test-run-all-time: all 4 passed
Verdict: PASS
```

Export-shape evidence: the seven suites that fail on a `git archive` export and pass on a clone (`test-gauntlet-proof-audit`, `test-gitattributes-union`, `test-hooks`, `test-ledger-durability`, `test-lint-scattered-ids`, `test-proof-contract-visual`, `test-run-all-time`) are green on a clone of the head. Four of them also pass on the export after `git init` plus one commit.

Rebase rehearsal on master 7b2ca7aa (the three branch commits cherry-picked, clean):

```
Command: bash tests/test-adopt.sh && bash tests/test-run-all-time.sh && bash tests/test-run-all-changed.sh
Exit: 0
Output: PASS=55 FAIL=0 / all 4 passed / exit 0 each
Verdict: PASS
```

## Negative control (revert -> RED -> restore)

Mutant: the pre-fix `lib/adopt/agents-known.sha256` (3 lines removed), copied over the fixed file from a saved copy. The fixed file was copied aside first and copied back after, never `git checkout --`.

```
Command: bash tests/test-adopt.sh   # mutant: pre-fix known-hash list
Exit: 1
Output: NOT ok - known list complete against git log (3 missing; run lib/adopt/known-hashes.sh)
        PASS=54 FAIL=1
Verdict: RED as expected

Command: bash tests/test-adopt.sh   # restored from the saved copy
Exit: 0
Output: PASS=55 FAIL=0
Verdict: PASS (tree clean vs HEAD after restore: yes)
```

The five already-green suites carry no change, so they owe no negative control.

## Reproduce

```
git clone <repo> k && cd k && git checkout fix/master-green
bash tests/test-adopt.sh
git archive HEAD | tar -x -C "$(mktemp -d)"   # then run the five suites inside it
```

Headless, no visible surface.
