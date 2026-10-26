# Proof of done: MANUAL split into reference docs

## What changed

`docs/MANUAL.md` is the command reference again. The blocks that the README rewrite moved into it now live in `docs/reference/`: `lifecycle.md`, `install.md`, `skills.md`, `project-structure.md`, `operations.md`, `roadmap.md` and `credits.md`, plus merges into `architecture.md`, `PHILOSOPHY.md` and `hooks.md`. Living references, `install.sh` messages and the test pins that read the moved sections point at the new homes. The pin edits are source, so this change is behavioral and needs this proof.

## Gate table

| Claim | Evidence |
|---|---|
| every pin reads its new home and still holds | run blocks below |
| the structural suite stays green | `tests/test-meta.sh` block |
| the gauntlet tier 1 gate stays green | `tests/gauntlet/tier1.sh` block |
| no new dead reference versus origin/master | refcheck block |
| the generated feature registry is fresh | `lib/registry/feature-registry.sh check` block |
| no old MANUAL anchor survives in a living file | anchor sweep block |
| a moved pin is load-bearing | two negative controls below |

## Run blocks

```
Command: bash tests/test-meta-vmodel-dispatch.sh
Exit: 0
Output:
  PASS retro follow-ups wired: escalation + advisory + grill + colors + detectors (SPEC-069)
  === Results ===
  Passed: 75 / 75
  All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
  PASS proof-gate skeleton with no task arg defaults to behavioral (no Rollback)
  === Results ===
  Passed: 120 / 120
  All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/test-understanding-wiring.sh
Exit: 0
Output:
  PASS NEGATIVE CONTROL: the sweep flags the fabricated over-claim as a SILENT ORPHAN (rc=1), not a false PASS
  === Results ===
  Passed: 19 / 19
  All understanding-wiring tests passed.
Verdict: PASS
```

```
Command: bash tests/test-break-it.sh
Exit: 0
Output:
  --- SG-01 effectiveness gate ---
  PASS T4-AC5: break-it passes the SG-01 agent-effectiveness gate
  === 67/67 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-kit-contract.sh
Exit: 0
Output:
  PASS C8 catches the unquoted colon-space step name (the real incident)
  PASS C9 catches an agent claiming a dispatcher that ignores it
  PASS C10 catches an executable that does not declare its interpreter
  === kit-contract: 25 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-repohygiene.sh
Exit: 0
Output:
  PASS audit-scanner names repo-hygiene as a dispatching instance
  PASS the pattern doc lists repo-hygiene under Known instances
  PASS skills reference table carries a repo-hygiene row
  100/100 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Output:
  PASS  tests/test-adopt.sh
  == T1.5 gauntlet prep scripts lint
  PASS  shellcheck -x tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign
  TIER1: GREEN
Verdict: PASS
```

```
Command: bash tests/test-meta.sh
Exit: 0
Output:
  Passed: 25 / 25
  All hard-claim tests passed.
  === Results ===
  Passed: 930 / 930
  All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/test-docdrift-refcheck.sh
Exit: 0
Output:
  -- the shipped skill points at the scanner --
  PASS SKILL.md step 3 names refcheck.sh
  Passed: 16 / 16
  All doc-drift refcheck tests passed.
Verdict: PASS
```

## Reference checks

```
Command: bash lib/docdrift/refcheck.sh scan --repo . (this branch) against the same scan of an export of origin/master
Exit: 0
Output:
  origin/master  SUMMARY  44 docs  820 refs checked  30 dead
  this branch    SUMMARY  51 docs  868 refs checked  28 dead
  dead-set diff  none added by this change; two `.claude/rules/` ticks on a MANUAL line that stayed resolve only here, where a test run left an ignored directory of that name
Verdict: PASS
```

```
Command: bash lib/registry/feature-registry.sh check
Exit: 0
Output:
  feature-registry: docs/reference/FEATURES.md is fresh
Verdict: PASS
```

```
Command: rg -n -i '#(install-options|skills-claude|who-this|project-structure|the-five-stages|operational-reference|credits|requirements|workflow-at-a-glance|verification-pipeline|why-a-closed|the-lifecycle|v2-roadmap|option-[123]|pick-one)' over every living file (records excluded)
Exit: 0
Output:
  (no matches)
Verdict: PASS
```

## Diff-scoped run

```
Command: bash tests/run-all.sh --changed origin/master
Result: 69 suites selected, 68 ok, 1 failed
Output:
  run-all: FAILED -> test-codex-hooks
  run-all: 69 suites run, 0 skipped for missing tooling
```

`test-codex-hooks` fails two assertions that this change cannot reach: it fails the same way on a clean export of origin/master.

```
Command: bash tests/test-codex-hooks.sh (run inside a clean export of origin/master)
Result: the same two assertions fail without this branch
Output:
  FAIL commit-format.sh trust command pins its content hash: expected 1, got 0
  FAIL repin check passes on a fresh fixture: expected 0, got 1
  92 passed, 2 failed
```

## Negative controls

The first control restores the old pin file, which reads the old MANUAL anchors. It goes red because those sections are gone from MANUAL. The second removes a skill row from its new home and the moved pin catches it.

```
Command: bash tests/test-meta-vmodel-dispatch.sh
Exit: 0 (green before mutation)
Output:
    PASS run legibility wired: plan/progress/trace + AGENTS/assign/grill (SPEC-063)
    PASS stack-merge codified + wired into ship (SPEC-065)
    PASS install-by-copy + stamp + staleness probe (SPEC-066)
    PASS golden-run e2e exists + CI runs it (SPEC-067)
    PASS precedent lookup wired into intake (SPEC-068)
    PASS retro follow-ups wired: escalation + advisory + grill + colors + detectors (SPEC-069)
  
  === Results ===
  Passed: 75 / 75
  All meta tests passed.

Mutation: git show 00dda2f5:tests/test-meta-vmodel-dispatch.sh > tests/test-meta-vmodel-dispatch.sh
Changed: tests/test-meta-vmodel-dispatch.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS run legibility wired: plan/progress/trace + AGENTS/assign/grill (SPEC-063)
    PASS stack-merge codified + wired into ship (SPEC-065)
    PASS install-by-copy + stamp + staleness probe (SPEC-066)
    PASS golden-run e2e exists + CI runs it (SPEC-067)
    PASS precedent lookup wired into intake (SPEC-068)
    PASS retro follow-ups wired: escalation + advisory + grill + colors + detectors (SPEC-069)
  
  === Results ===
  Passed: 70 / 75
  Failed: 5

Restore: git checkout HEAD -- tests/test-meta-vmodel-dispatch.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash tests/test-repohygiene.sh
Exit: 0 (green before mutation)
Output:
    PASS a non-numeric threshold is rejected at parse time
  -- wiring: registration surfaces --
    PASS SKILL.md dispatches kit:audit-scanner for Tier 2
    PASS SKILL.md states the mega-goal completion precedence
    PASS SKILL.md names the general-purpose fallback
    PASS audit-scanner names repo-hygiene as a dispatching instance
    PASS the pattern doc lists repo-hygiene under Known instances
    PASS skills reference table carries a repo-hygiene row
  
  100/100 passed, 0 failed

Mutation: sed -i '' '/^| repo-hygiene |/d' docs/reference/skills.md
Changed: docs/reference/skills.md
Exit: 1 (under mutation, RED expected)
Output:
    PASS a non-numeric threshold is rejected at parse time
  -- wiring: registration surfaces --
    PASS SKILL.md dispatches kit:audit-scanner for Tier 2
    PASS SKILL.md states the mega-goal completion precedence
    PASS SKILL.md names the general-purpose fallback
    PASS audit-scanner names repo-hygiene as a dispatching instance
    PASS the pattern doc lists repo-hygiene under Known instances
    FAIL skills reference table carries a repo-hygiene row 
  
  99/100 passed, 1 failed

Restore: git checkout HEAD -- docs/reference/skills.md
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert the branch commits. MANUAL returns to its long form and every pin reads it again. Only documentation, test pins, two command prompts and `install.sh` message text change, so no runtime behavior moves.

## Not attempted

- `tests/run-all.sh --all`. The diff-scoped run plus `test-meta` and tier 1 cover the touched surface.
- A gauntlet onboarding run. The README and QUICKSTART body did not change, only link targets.
