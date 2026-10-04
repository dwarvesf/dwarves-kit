# Implementation notes: master green

Delta from `docs/specs/SPEC-388-master-green.md` only: root causes, one line per suite, and the assertion rationale. The spec is the contract.

## Root cause per suite

| Suite | Root cause | Change |
|---|---|---|
| tests/test-adopt.sh | `lib/adopt/agents-known.sha256` lacked the hashes of three committed `AGENTS.md` versions (commits e2d9133927bc, 1b449c068821, f215bf115f4b); nothing regenerates the list when `AGENTS.md` changes, and the test is the only guard. | Regenerated the list with `lib/adopt/known-hashes.sh`. Three lines added, none removed. |
| tests/test-gate-opt-out.sh | Already fixed on master (#886 gate opt-out base config). Exit 0 on re-measure. | None |
| tests/test-gate-validate-round.sh (C12) | Already green on re-measure. Exit 0, no change. | None |
| tests/test-config-registry.sh (AC10) | Already fixed on master (#901 declared the root-only `proof.*` keys). Exit 0 on re-measure. | None |
| tests/test-install-contract.sh | Already fixed on master (#887 reads lane data from the install kit.toml). Exit 0 on re-measure. | None |
| tests/test-research-arch-contract.sh (row 7) | Already green on re-measure. Exit 0, no change. | None |
| test-gauntlet-proof-audit, test-gitattributes-union, test-hooks, test-ledger-durability, test-lint-scattered-ids, test-proof-contract-visual, test-run-all-time | Environment, not code: a `git archive` export carries no `.git`, and each suite reads git state (`git ls-files`, `origin/master`, `git status`). All exit 0 on a full-history clone. Four of them also exit 0 on the export after `git init` plus one commit. | None |
| tests/test-codex-hooks.sh | Host: the installed `codex` binary (Homebrew cask 0.160.0) hangs on `codex --version` and `codex --help`, with and without the sandbox and with a fresh `CODEX_HOME`. The suite's loader probe (`codex plugin marketplace add`) had no time bound, so the run reached the 300 s runner ceiling. The suite joined this sub-goal because it is red on master on this host. | Added a bounded liveness probe (`codex --version`, 10 s, `timeout` else `gtimeout`, unbounded when neither exists as before). A hang or failure prints a SKIP line and runs no loader assert, the same as a missing binary. The two `codex plugin` calls are bounded at 60 s so a hang there FAILS the assert. No assertion deleted or weakened. |

## Assertion rationale

No assertion was edited, deleted or weakened. The codex change wraps the existing loader assertion in a guard; the assertion text and its fail path are unchanged. `test-adopt` T5 is right: a committed `AGENTS.md` version missing from the list reads as an operator edit and is never swapped by `adopt`. The data was stale, so the data changed.

## Decisions the spec did not make

- The five-suite list in the goal was stale; four of the five were fixed by #875, #886, #887 and #901 before this branch. Each got one recorded run and no change, per the goal.
- The branch was written on master 144c2279 and rebased onto a7301653. The rebase needed two follow-ups: the `docs/FEATURES.md` citation counts, and one more known-hash regeneration (#899 changed `AGENTS.md`). A parallel merge (#907) also took spec number 387, so this spec is 388.
- Measured both shapes on purpose: a `git archive` export (the goal's literal form) and a full-history `git clone` (the shape CI checks out with `fetch-depth: 0`). The export shape is red for seven suites by construction; the clone shape is the honest signal.

## Decided by the lead

- Recurrence of the known-hash list: `test-adopt` stays as the guard and nothing auto-regenerates the list. Decided, not open. It re-fired during this work: #899 changed `AGENTS.md` after the first regeneration and turned `test-adopt` red again on master, so the list was regenerated once more after the rebase.
- A hung host `codex` skips the loader proof with a visible SKIP line instead of failing the suite.
