# Verification: advisory decision-capture nudge at /kit:retro (SPEC-051)

Proof class: **inert** (advisory doc/process text in `commands/retro.md`; no code-behavior change).
Per the proof-gate contract an inert change is exempt from a behavioral run; the guard is the meta
assertion below, which pins both that the nudge exists AND that it stays advisory. Last run:
2026-06-10.

## GREEN: the nudge exists and points at the real ADR home

```
$ grep -i 'decision-capture' commands/retro.md
### Step 1c: Decision-capture nudge (advisory)
$ grep -c 'docs/decisions/' commands/retro.md     # >=1 (Step 1c + the existing Step 5 feed-forward)
```

## GREEN: it is framed advisory, never a block (the assertion that prevents drift)

`tests/test-meta.sh` asserts both:
1. `retro.md` contains `decision-capture` and `docs/decisions/`.
2. Within the "Decision-capture nudge" block, the phrase `advisory, never a block` appears.

So a future edit cannot quietly turn the nudge into a hard gate (which would violate PHILOSOPHY's
"rejects hard-gating process completeness") without failing the suite. This is the negative-control
shape for an inert change: the test fails if the advisory framing is removed.

## Review (single lens, normal lane)

Architecture/process review returned 8/10 SHIP. Two LOW findings fixed: assertion 1 was scoped to
the Step 1c block (it could have false-passed on Step 5's existing `docs/decisions/` mention), and
the advisory citation now anchors to PHILOSOPHY's "Detect, don't dictate" rather than a paraphrase
that has no literal home in PHILOSOPHY.md.

## Suite

`bash tests/test-meta.sh` -> 397/397 (was 395; +2 SPEC-051 assertions).

## Verdict: PASS (review-hardened)
