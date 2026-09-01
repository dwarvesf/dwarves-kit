# Proof of done: gauntlet-proof-audit skill (SPEC-242)

A new audit-loop SKILL (`/kit:gauntlet-proof-audit`) that audits every committed gauntlet run record against its own committed evidence: markers well-formed, recorded verdict == `checker-output.txt`, findings count reconciles, scrub clean (no resolved credential VALUE), run-dir grammar conforms. Report-first, REMOVE-disallowed (a record is evidence).

## Recorded run (AC-1/AC-2, live Tier-1 pass over the real corpus)

```
Command: git ls-files 'docs/verification/gauntlet/*/ROUNDS.md' 'docs/verification/gauntlet/*/*-ROUNDS.md' 'docs/verification/gauntlet/*/AB-ROUNDS.md'
Exit: 0
Verdict: PASS   # 8 committed records enumerated, zero untracked room-copy ROUNDS files
```

Per-record verdict (Tier-1, under the corrected credential-VALUE scrub axis):

| Record | Verdict | Evidence |
|---|---|---|
| 2026-08-06-kit-user/ROUNDS.md | UNSURE | markers/findings reconcile; no committed checker-output.txt (predates the convention) → checker axis UNTESTABLE |
| 2026-08-06-kit-user/J3-ROUNDS.md | UNSURE | K=0 both rounds confirmed by findings; no checker-output.txt → UNTESTABLE |
| 2026-08-31-onboarding-j1-revised/ROUNDS.md | OK | round-1/2 checker-output GREEN == table; K=0 |
| 2026-08-31-user-J1/ROUNDS.md | OK | checker-output GREEN == table; K=4 == findings.md |
| 2026-08-31-user-J1-nw/ROUNDS.md | OK | checker-output GREEN == table; K=4, 1 excluded named |
| 2026-09-01-ab-doorway-...-vs-... /AB-ROUNDS.md | OK | A 2/2, B 2/2 checker-output all GREEN == AB-VERDICT tally |
| 2026-09-01-onboarding-campaign/ROUNDS.md | OK | all 11 rows checker-output match (J7 RED, rest GREEN); K=2 == F1/F2 |
| 2026-09-01-onboarding-campaign-2/ROUNDS.md | OK | all 11 GREEN == table; K=0 |

Real credential-VALUE sweep across the whole corpus: `git grep -lE 'sk-ant-...|ANTHROPIC_API_KEY=<value>'` → 0 hits. (The `op://Toolkit/anthropic-api-key` pointer appears in some transcripts; it is a reference, not a secret, and is allowed per estate policy, not flagged. This correction, from the audit's own first run flagging its too-strict draft contract, is logged in the implementation notes.)

## NEGATIVE CONTROL (AC-3)

Planted a verdict/evidence contradiction on a scratch copy of `2026-08-31-user-J1`: flipped the ROUNDS table cell GREEN→RED while its committed `checker-output.txt` stays GREEN.

```
Command: <Tier-1 verdict-vs-evidence check on the planted record>
Exit: 0
Output: table=RED evidence=GREEN
        FLAG: recorded verdict (RED) contradicts committed checker-output (GREEN)
Verdict: PASS   # the discrepancy is caught with both sides quoted; restore -> OK
```

## Suite (AC-4)

```
Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS   # 824 / 824, incl. "README skills table rows == live skills (12 == 12)" and FEATURES freshness
```

## AC-5

The SKILL.md apply-mechanics section states REMOVE is never used and a historical claim is never silently rewritten (a discrepancy is reported; a dated correction note lands only on a DANGER record). Verified by reading the skill against this contract.

Rollback: additive (one new skill dir, one README row, a FEATURES regen, one audit-loop pattern row); `git revert` removes the skill and its wiring, no state.

## Reproduce

```
/kit:gauntlet-proof-audit         # or run the item-set + Tier-1 checks by hand per the SKILL.md
bash tests/test-meta.sh
```
