# fix: correct README CLI flag from --uppercase to --upper

## What
The README's usage example called the CLI with `--uppercase`, but the actual
flag implemented in `cli.js` is `--upper`. Running the documented command
failed with the usage error instead of printing the expected output. Updated
the example to `node cli.js --upper hello`.

## Why
Tiny-lane doc fix: the documented command didn't match the actual CLI flag,
so following the README literally did not work.

## Review
Self-reviewed (tiny lane: run-lite review, no `## Review` section since there
is no spec for this lane).

## Testing
Ran `node cli.js --upper hello` and confirmed it prints `HELLO`, matching the
README's documented output.

## Checklist
- [x] Tests pass (manual verification, no test runner in this repo)
- [x] Docs updated (README.md)
- [x] Review: self-reviewed (tiny lane)
- [x] No regressions (one-line doc change, no code touched)
