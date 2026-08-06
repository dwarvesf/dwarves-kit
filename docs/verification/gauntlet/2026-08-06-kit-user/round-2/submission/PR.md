# fix: correct README example flag from --uppercase to --upper

## What
The README usage example ran `node cli.js --uppercase hello`, but `cli.js` only
recognizes `--upper`. Following the documented example verbatim failed with
`usage: cli.js --upper <text>`. Updated the example to use the actual flag.

## Why
Tiny-lane doc fix (WORKFLOW.md "Size the work first": one obvious edit, no spec
needed). The doc must match the CLI it documents.

## Review
Self-reviewed (tiny lane: build + review gates recorded in the run ledger,
rid `readme-cli-flag`). No behavior change to `cli.js`, so no regression risk.

## Testing
Ran `node cli.js --upper hello` and confirmed it prints `HELLO`, matching the
corrected README example.

## Checklist
- [x] Tests pass (manual verification, no test runner in this fixture repo)
- [x] Docs updated (README.md)
- [x] Review: self-reviewed, tiny lane
- [ ] No regressions (no app code changed)
