# Proof of done: master green

Branch `fix/master-green`, rebased onto master a7301653. Spec: `docs/specs/SPEC-388-master-green.md`. Notes: `docs/implementation-notes/master-green.md`.

Recorded runs below ran on a clean export (or, where stated, a full-history clone) of branch head `e83ff544`. Code changes on the branch: the known-hash list regeneration (two commits) and the bounded codex probe in `tests/test-codex-hooks.sh`; every other commit is docs. Two export shapes were used on purpose. A `git archive` export has no `.git`, so seven suites that read git state cannot pass on it by construction; `test-adopt`, `test-run-all-time` and `test-meta` read git state and ran on the clone.

## Before and after

| Suite | master export exit | branch export exit | Change |
|---|---|---|---|
| test-gate-opt-out | 0 | 0 | none (already green) |
| test-gate-validate-round | 0 | 0 | none (already green) |
| test-config-registry | 0 | 0 | none (already green) |
| test-install-contract | 0 | 0 | none (already green) |
| test-research-arch-contract | 0 | 0 | none (already green) |
| test-adopt | 1 (clone shape; also 1 on export) | 0 (clone shape) | regenerated `lib/adopt/agents-known.sha256` (twice: #890/#892/#894, then #899) |
| test-codex-hooks | 124 (hang) | 0 | bounded liveness probe; a hung codex skips the loader proof |

## Recorded run

Suite 1, test-gate-opt-out, export of `e83ff544`:

```
Command: bash tests/test-gate-opt-out.sh
Exit: 0
Output: ALL PASS
Verdict: PASS
```

Suite 2, test-gate-validate-round (C12), export of `e83ff544`:

```
Command: bash tests/test-gate-validate-round.sh
Exit: 0
Output: === results: 196/196 pass, 0 fail ===
Verdict: PASS
```

Suite 3, test-config-registry (AC10), export of `e83ff544`:

```
Command: bash tests/test-config-registry.sh
Exit: 0
Output: === 59/59 passed ===
Verdict: PASS
```

Suite 4, test-install-contract, export of `e83ff544`:

```
Command: bash tests/test-install-contract.sh
Exit: 0
Output: PASS=4 FAIL=0
Verdict: PASS
```

Suite 5, test-research-arch-contract (row 7), export of `e83ff544`:

```
Command: bash tests/test-research-arch-contract.sh
Exit: 0
Output: Passed: 28 / 28
Verdict: PASS
```

Suite 6, test-adopt, full-history clone of `e83ff544` (it walks `git log -- AGENTS.md`, so an export cannot run it):

```
Command: bash tests/test-adopt.sh
Exit: 0
Output: PASS=55 FAIL=0
Verdict: PASS
```

Suite 7, test-codex-hooks, export of `e83ff544`, with the hanging `codex` still first on PATH (`timeout 15 codex --version` exits 124 on this host):

```
Command: timeout 120 bash tests/test-codex-hooks.sh
Exit: 0
Output: SKIP Codex loader proof: codex --version did not return within 10s (host binary unavailable)
        93 passed, 0 failed
Verdict: PASS
```

Doc and registry freshness, full-history clone of `e83ff544` (`test-meta` includes the `docs/FEATURES.md` freshness check and the duplicate spec number check):

```
Command: bash tests/test-meta.sh
Exit: 0
Output: All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/test-run-all-time.sh
Exit: 0
Output: test-run-all-time: all 4 passed
Verdict: PASS
```

Full list: run on a clone of `073d7631` (the same code as `e83ff544`, before the spec renumber) with `KIT_RUN_ALL=1 RUN_ALL_JOBS=3 bash tests/run-all.sh --all --time`: 198 suites ran, 0 skipped, one red: `test-meta`, "no duplicate SPEC numbers (dups: SPEC-387)". Cause: #907 had taken SPEC-387 while this branch also used it. The spec was renumbered to 388 and `test-meta` then passed on `e83ff544` (block above). No other suite was red, including `test-codex-hooks` (ok in 16 s).

Export-shape evidence: the seven suites that fail on a `git archive` export and pass on a clone (`test-gauntlet-proof-audit`, `test-gitattributes-union`, `test-hooks`, `test-ledger-durability`, `test-lint-scattered-ids`, `test-proof-contract-visual`, `test-run-all-time`) were green on a clone of the pre-rebase head. Four of them also pass on the export after `git init` plus one commit.

## Negative control (revert -> RED -> restore)

Both controls ran on the rebased, committed tree. Each fixed file was copied aside first and copied back after, never `git checkout --`. The tree was clean after each restore.

Control 1, test-codex-hooks. Mutant: the pre-fix `tests/test-codex-hooks.sh`, which calls the hanging codex with no time bound.

```
Command: timeout 120 bash tests/test-codex-hooks.sh   # mutant: pre-fix file
Exit: 124
Output: last line "PASS adapter command target is executable", then the codex loader call hangs until the 120 s bound kills the run
Verdict: RED as expected

Command: timeout 100 bash tests/test-codex-hooks.sh   # restored from the saved copy
Exit: 0
Output: 93 passed, 0 failed
Verdict: PASS (tree clean vs HEAD after restore: yes)
```

Control 2, test-adopt. Mutant: the pre-fix `lib/adopt/agents-known.sha256` (4 versions missing against the rebased history).

```
Command: bash tests/test-adopt.sh   # mutant: pre-fix known-hash list
Exit: 1
Output: NOT ok - known list complete against git log (4 missing; run lib/adopt/known-hashes.sh)
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
bash tests/test-adopt.sh && bash tests/test-meta.sh
git archive HEAD | tar -x -C "$(mktemp -d)"   # then run the other suites inside it
```

Headless, no visible surface.
