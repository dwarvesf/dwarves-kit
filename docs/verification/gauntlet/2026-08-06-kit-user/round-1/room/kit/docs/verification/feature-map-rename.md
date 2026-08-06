# Proof of done: feature-map-rename

## Acceptance criteria

| AC | Claim | Status |
|---|---|---|
| AC-1 | `/kit:features` collided with the existing maintainer-only `feature-map` skill; both now read as distinct names (`/kit:feature-map` command, `topology-drift` skill) | MET (run 1) |
| AC-2 | Every live cross-reference (skills, commands, agents, README, architecture, MANUAL, workflow-paths, glossary, patterns/audit-loop, tests) updated to the new names; historical/dated records (SPEC-218/219/220/222, their verification/implementation-notes, the shipped BACKLOG row) left untouched per the repo's own leg->stage rename precedent | MET (run 1) |
| AC-3 | Regenerated `docs/FEATURES.md` committed; freshness pin green | MET (run 2) |
| AC-4 | Full meta suite + the audit-scanner-contract suite (which pins both skill names) green | MET (run 2) |
| AC-5 | Negative control: reverting the skill directory to its old name drops the test suite to RED, proving the pinned assertions actually discriminate on the rename | MET (run 3) |

## Confirmation runs

| # | Check | Command | Result |
|---|---|---|---|
| 1 | no stale token left anywhere live | `grep -rn "feature-map\|kit:features\b" . --exclude-dir=.git` (with historical files excluded) | every remaining `feature-map` hit is the correct NEW command name `/kit:feature-map`; every remaining `kit:features` hit is inside the dated naming-reconciliation research note (history, not code) |
| 2 | full suite green post-rename | `bash tests/test-meta.sh` and `bash tests/test-audit-scanner-contract.sh` | Command: `bash tests/test-meta.sh` -> 805/805 PASS, Exit: 0. Command: `bash tests/test-audit-scanner-contract.sh` -> 15/15 PASS, Exit: 0 |
| 3 | NEGATIVE CONTROL | `git mv skills/topology-drift skills/feature-map`, re-run `test-audit-scanner-contract.sh`, restore via `git mv skills/feature-map skills/topology-drift` | reverted: 13/15, two AC2 dispatched-by-wiring assertions FAIL (RED). Restored: 15/15 PASS, Exit: 0 |

## Run detail

Run 1: `/kit:features` (new, generic per-target-project feature-inventory command, PR #338) and the existing maintainer-only `feature-map` skill (audits the kit's own registry against its path index, SPEC-218) read as the same word to a human typing a command, despite each already carrying a cross-referencing NOT-clause. Operator decision: rename the older skill (cheaper direction was actually the command at 16 occ/9 files vs the skill's 70 occ/27 files including test pins, but the operator chose to keep the shorter/more natural `/kit:feature-map` name on the newer, generic command and move the older, narrower maintainer-only skill instead). Renamed `skills/feature-map/` -> `skills/topology-drift/` (matches the existing `doc-drift` naming pattern for audit-loop instances that check two artifacts for drift) and `commands/features.md` -> `commands/feature-map.md`.

Run 2: `docs/FEATURES.md` regenerated via `lib/registry/feature-registry.sh generate` after the rename; `tests/test-meta.sh`'s freshness pin and the skill-dispatcher derivation pin (which literally asserted the string `feature-map (skill)`) both needed updating to `topology-drift (skill)` in the same commit, since the generator reads live file names.

Run 3: the AC2 block in `test-audit-scanner-contract.sh` reads `skills/topology-drift/SKILL.md` by path and greps its body for `kit:audit-scanner`/`general-purpose`, plus greps `agents/audit-scanner.md`'s body for the literal token `topology-drift`. Reverting the skill directory to its old name makes both path-dependent assertions fail (13/15), confirming the pin is load-bearing rather than a rename that quietly stopped being checked.

## Reproduce

```
grep -rn "feature-map\|kit:features\b" . --exclude-dir=.git
bash tests/test-meta.sh
bash tests/test-audit-scanner-contract.sh
git mv skills/topology-drift skills/feature-map
bash tests/test-audit-scanner-contract.sh   # expect 13/15, AC2 dispatched-by assertions FAIL
git mv skills/feature-map skills/topology-drift
bash tests/test-audit-scanner-contract.sh   # expect 15/15 again
```
