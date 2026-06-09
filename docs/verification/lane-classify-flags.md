# Verification: flag-scoring lane classification (SPEC-050)

Proof class: **behavioral** (changes how `lane-classify.sh classify` maps a description to a lane).
Reproduce: `bash tests/test-hooks.sh && bash tests/test-meta.sh` + the live runs below.
Last run: 2026-06-10.

## GREEN: the 2026-06-10 misclassification is fixed

```
$ bash lib/lane-classify.sh classify "rewrite lib/lane-classify.sh into a flag-scoring classifier"
full
$ bash lib/lane-classify.sh classify "adopt @AGENTS.md import loader plus --dry-run and --refresh flags in lib/adopt.sh"
full
$ bash lib/lane-classify.sh classify "ship AGENTS.md + WORKFLOW.md into the install so adopt + gate-ledger work"
full
```

All three were the descriptions that fell to `normal` this cycle and forced a manual override.

## GREEN: `explain` is auditable (the real absorption win)

```
$ bash lib/lane-classify.sh explain "ship AGENTS.md into the install via install.sh so adopt works"
full
reason: hard-gate flag(s): kit-machinery
flags: kit-machinery
```

The classifier now shows WHICH flag fired, so a lane (and any override) is defensible, not a black box.

## NEGATIVE CONTROL: the OLD classifier on the same descriptions

```
$ git show master:lib/lane-classify.sh > /tmp/lane-old.sh
$ bash /tmp/lane-old.sh classify "rewrite lib/lane-classify.sh into a flag-scoring classifier"
normal     # the bug: a gate-machinery change classified as a routine feature
$ bash /tmp/lane-old.sh classify "adopt @AGENTS.md import loader plus --dry-run and --refresh flags in lib/adopt.sh"
normal
```

The fix is load-bearing: revert `lib/lane-classify.sh` and these two go back to `normal`.

## NO REGRESSION: the 5 pinned classifications still hold

`tests/test-hooks.sh` asserts the pre-existing five (tiny / bug / full / normal / backfill) plus the
new kit-machinery + soft-count + explain cases. backfill is still checked before the kit-machinery
hard-gate, so `review the legacy service and write its AGENTS.md operating-layer docs` stays
`backfill` (the `AGENTS.md` token does not escalate it).

## Review-hardening (3-lens review-team, dogfooded)

Review returned security 9/10 + architecture 8/10 (both SHIP) + test-coverage 5/10 (FIX-THEN-SHIP).
Addressed before merge:
- Arch MEDIUM: `\badopt\b` was too broad ("adopt a convention" wrongly escalated). Scoped to
  `adopt @` / `adopt.sh` / `kit:adopt` / `adopt <near a kit noun>`. Bare "adopt" now stays normal;
  kit adopts still full (verified live).
- Arch LOW (real): `security` had been silently dropped from the hard-gate. Restored (DEC-003).
  "add security middleware" -> full again. `validation` stays deliberately narrowed (add = normal,
  weaken = full).
- Test HIGH x2: pinned the 2-3 soft-flag band (-> normal) and tiny-beats-an-actual-hard-gate
  ("fix a typo in the auth comment" -> tiny). Added empty-desc + `flags` subcommand tests.
- Security LOW: `$(echo $hard)` -> `${hard# }` (no subshell, no glob surface). Plus a load-time
  name/regex array alignment assertion.

## Suite

`bash tests/test-hooks.sh` -> PASS 177/177 (the 5 pre-existing lane assertions unchanged; +12 for
SPEC-050 + the review-driven additions). `bash tests/test-meta.sh` -> 395/395.

## Verdict: PASS (review-hardened)
