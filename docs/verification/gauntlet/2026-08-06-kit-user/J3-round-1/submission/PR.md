# feat: add --repeat N flag to the shout CLI

## What
Adds a `--repeat N` flag to `shout`/`cli.js`. `shout --upper --repeat 3 hello` now prints `HELLO`
three times instead of once. `--repeat` is optional (omitting it behaves exactly as before) and
works regardless of whether it appears before or after `--upper`. Invalid input (`0`, negative,
non-numeric, non-integer, or a missing value) is rejected with a stderr error and a non-zero
exit code.

## Why
Team ask: "`shout --upper hello` works; we want `--repeat N` so `shout --upper --repeat 3 hello`
prints the result three times." Run through the kit's full lane end to end: spec written and
adversarially validated (`docs/specs/SPEC-001-repeat-flag.md`, Status: SHIPPED) before any
implementation commit landed.

## Review
`## Review` in `docs/specs/SPEC-001-repeat-flag.md`: 3-lens review (security, architecture,
test-coverage). Test-coverage's first pass came back FIX THEN SHIP (missing test for a
trailing-value-less `--repeat`, and rejection tests not asserting stderr content) — both fixed
before this PR. Final verdict: **SHIP**.

## Testing
- `npm test` — 11/11 pass (`test/cli.test.js`), covering N=1, N=3, order-independence,
  duplicate-flag precedence, `--repeat` without `--upper`, and all five invalid-input shapes.
- Manual cross-check: `node cli.js --upper --repeat 3 hi | grep -c HI` → `3`;
  `node cli.js --upper --repeat banana hi` → non-zero exit; `node cli.js --upper hello` → `HELLO`
  (no regression).
- Proof of done with a negative control: `docs/verification/repeat-flag.md` — a green run, then
  `cli.js` reverted to its pre-feature state to confirm the suite actually goes RED (9/11 fail),
  then restored to green.

## Checklist
- [x] Tests pass (`npm test`, 11/11)
- [x] Docs updated (README usage line, spec tasks/ACs checked off, Status: SHIPPED)
- [x] Review: SHIP
- [x] No regressions (`--upper hello` unchanged)
- [x] Proof-of-done recorded with a negative control (`docs/verification/repeat-flag.md`)

## Commits
- `docs: adopt dwarves-kit and validate repeat-flag spec`
- `feat: add --repeat N flag to shout CLI`
- `test: cover missing-value + stderr assertions from review-team`
- `chore: ship --repeat flag (v1.1.0)`
