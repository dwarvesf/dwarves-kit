# Proof of done: claim-verifier agent (kit-foldin SG-06)

Class: behavioral. Verified 2026-07-05. A new kit subagent `agents/claim-verifier.md`
(an in-harness N-skeptic majority-vote panel over an arbitrary free-text claim). Full
Design block + smoke transcript + agent-effectiveness detail: `docs/proof/kit-foldin-claim-verifier.md`.

## GREEN (real run)

Structural gate (frontmatter, model enum, MANUAL/README/architecture roster parity):

```
Command: bash tests/test-meta.sh
Exit: 0
Output (excerpt): Passed: 679 / 679 -- All meta tests passed.
VERDICT: PASS
```

Behavioral smoke -- a REAL dispatch of the agent's instructions on the committed fixture
claim (`tests/fixtures/claim-verifier/false-claim.json`) returned a well-formed structured
majority-vote verdict:

```
Command: dispatch claim-verifier on "Water boils at 10 degrees Celsius at standard sea-level atmospheric pressure."
Exit: 0 (dispatch returned)
Output (excerpt):
  VERDICT: REFUTED
  Panel: N=3, refuted=3/3, threshold=majority-refute (REFUTED iff refuted*2 > N)
  Skeptics: 1.[Factual] 2.[Logical/scope] 3.[Steelman] all refuted=true
VERDICT: PASS  (well-formed structured block; verdict = fixture's expected REFUTED)
```

Effectiveness gate -- `kit:agent-effectiveness` dispatched over the new def:

```
Command: dispatch kit:agent-effectiveness on agents/claim-verifier.md
Exit: 0 (dispatch returned)
Output (excerpt): VERDICT: PASS -- tools OK, description OK, instructions OK, tier OK
VERDICT: PASS
```

## NEGATIVE CONTROL (revert -> RED -> restore)

Break the MANUAL.md roster row (test-meta requires every agent file to have one), confirm
RED, restore, confirm GREEN:

```
1. baseline:  bash tests/test-meta.sh                       -> Exit 0  (GREEN)
2. break:     sed -i '' '/^| `claim-verifier` |/d' MANUAL.md
              bash tests/test-meta.sh                       -> Exit 1  (RED)
              FAIL: "agent claim-verifier NOT listed in MANUAL.md" (Failed: 1)
3. restore:   git checkout HEAD -- MANUAL.md
              bash tests/test-meta.sh                       -> Exit 0  (GREEN restored)
```

The control is decisive: removing the artifact's roster wiring flips the suite RED on
exactly the claim-verifier assertion, and restoring it returns GREEN. The check genuinely
exercises the change (not a no-op that passes regardless).

## Reproduce

```
cd dwarves-kit && bash tests/test-meta.sh          # 679/679
# smoke: dispatch the agent body (or, once installed, subagent_type claim-verifier) on
#        tests/fixtures/claim-verifier/false-claim.json -> expect a REFUTED structured block
# effectiveness: dispatch kit:agent-effectiveness on agents/claim-verifier.md -> PASS
```
