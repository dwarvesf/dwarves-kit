# Verification: orchfin-02-tier4-split (ID-093)

Behavioral change: the TIER-4 mega-close (`lib/queue/orchestrate.sh`, `TIER4_CLOSE`) now dispatches
THREE independent fresh-context verifier sessions and fail-closed aggregates their verdicts, instead
of one combined-prompt verifier. Fuller table-first proof (acceptance criteria, implementation,
reproduce): `_meta/megagoals/orchestrator-finish/proof/02-tier4-split.md`. This file is the kit
ship-gate's proof-of-done record (green run + negative controls).

## Green run

Full pinned suite, run under macOS system bash 3.2.57 (the CI-equivalent shell that first failed):

```
Command: PATH=/bin:/usr/bin /bin/bash tests/test-tier4-close.sh
Exit: 0
Verdict: PASS
```

Output tail:

```
PASS three-verifier split: exactly 3 independent verifier sessions dispatched
PASS aggregate: all-PASS aggregates to PASS
PASS no-corpus e2e: rc 2 -> WARN+skip (not a halt, not mis-reported clean); all 3 sessions ran, gate held
PASS dissent NC: all 3 verifiers dispatched despite one dissenting
PASS dissent NC: the close HALTS nonzero on a single dissent (not held clean)
PASS dissent NC: the aggregator names the DISSENT (not silently dropped)
PASS dissent NC: the gate is NOT held on a dissenting verifier
----
ALL PASS
```

Also green under modern bash (`bash tests/test-tier4-close.sh` -> `ALL PASS`, exit 0) and stable
across 5 repeat runs under bash 3.2.

## NEGATIVE CONTROL 1 -- the feature's fail-closed property (a dissent is not dropped)

Seed one dissenting verifier among the three (`MOCK_DISSENT=2`); the other two PASS clean. If the
aggregate silently dropped the dissent (the failure mode this sub-goal exists to kill), the close
would hold the gate. It does not:

```
Command: orchestrate.sh run <megagoal> with MOCK_DISSENT=2 (test-tier4-close.sh section H)
Exit: 1
Verdict: PASS   (the negative control correctly makes the close FAIL-CLOSED)
```

Observed: `[aggregate] verifier 2: TIER4-VERDICT: DISSENT: ...` -> `[aggregate] DISSENT: at least one
of the 3 verifiers did not PASS -- failing closed.` -> `BLOCKING: the 3-verifier aggregate DISSENTED`,
gate NOT held. Removing the dissent (all-PASS) flips exit back to 0 and holds the gate -> the control
toggles the outcome.

## NEGATIVE CONTROL 2 -- the macOS bash-3.2 regression fix (revert -> RED -> restore)

The first push passed ubuntu CI but failed macOS CI because `_dispatch_tier4_verifiers` used a
`trap 'rm -f "${cleanup[@]}"' RETURN` on a `local` array (fatal `set -u` empty-array unbound under
bash 3.2, which flips the whole run to rc 1). Revert the fix (restore the RETURN trap) and re-run the
clean-close path under bash 3.2 -> RED; restore the inline-cleanup fix -> GREEN.

```
With RETURN trap (reverted):   orchestrate run under /bin/bash 3.2  ->  Exit: 1  (line 1524: cleanup[@]: unbound variable)
With inline cleanup (fix):     orchestrate run under /bin/bash 3.2  ->  Exit: 0  (no unbound variable)
Verdict: PASS   (the control reproduces RED before the fix and GREEN after)
```

## Reproduce

```bash
PATH=/bin:/usr/bin /bin/bash tests/test-tier4-close.sh   # CI-equivalent shell
bash tests/test-tier4-close.sh                            # modern bash
```

Verdict: PASS
