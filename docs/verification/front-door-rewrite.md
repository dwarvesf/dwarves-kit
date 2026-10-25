# Proof of done: front door rewrite (README, QUICKSTART, MANUAL reference)

## What changed

The README is now a routing page and `docs/QUICKSTART.md` is the one walkthrough. The README's long reference moved into `docs/MANUAL.md` (the command, agent and hook rosters already lived there and in `docs/hooks.md`, so they were not copied). The suites that pinned README rows now pin those homes; the claims they check did not weaken, and the dispatcher-claim check now reads the stricter MANUAL agents table.

## Gate table

| Claim | Evidence |
|---|---|
| every roster pin still holds against its new home | run blocks below |
| the gauntlet tier 1 gate stays green | tier1 block below |
| the structural suite stays green | `tests/test-meta.sh` block below |
| a pin is load-bearing | negative control below |

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
    PASS T5-AC2: the ladder states the order is not enforced (open question 1)
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
    PASS MANUAL skills table carries a repo-hygiene row
  100/100 passed, 0 failed
  tests/test-repohygiene.sh: line 673: /var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.WX78Jm/_inbox/forge
  3	FIX	/etc/passwd	co-locate to /tmp/pwned: No such file or directory
Verdict: PASS
```

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Output:
  == T1.5 gauntlet prep scripts lint
  PASS  shellcheck -x tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign
  TIER1: GREEN
  warning: templates not found in /Users/tieubao/.git_template
Verdict: PASS
```

```
Command: bash tests/test-meta.sh
Exit: 0
Output:
  All hard-claim tests passed.
  === Results ===
  Passed: 930 / 930
  All meta tests passed.
Verdict: PASS
```

## Negative control

The vmodel-dispatch suite goes red when a skill row leaves the MANUAL skills table, and green again after the restore.

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

Mutation: sed -i '' '/^| repo-hygiene |/d' docs/MANUAL.md
Changed: docs/MANUAL.md
Exit: 1 (under mutation, RED expected)
Output:
    PASS run legibility wired: plan/progress/trace + AGENTS/assign/grill (SPEC-063)
    PASS stack-merge codified + wired into ship (SPEC-065)
    PASS install-by-copy + stamp + staleness probe (SPEC-066)
    PASS golden-run e2e exists + CI runs it (SPEC-067)
    PASS precedent lookup wired into intake (SPEC-068)
    PASS retro follow-ups wired: escalation + advisory + grill + colors + detectors (SPEC-069)

  === Results ===
  Passed: 74 / 75
  Failed: 1

Restore: git checkout HEAD -- docs/MANUAL.md
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert the four front-door commits. The README returns to its long form and every pin reads it again.

## Not attempted

- A gauntlet onboarding run over the new README and QUICKSTART. That is the lead's step once the figures and guides land.
