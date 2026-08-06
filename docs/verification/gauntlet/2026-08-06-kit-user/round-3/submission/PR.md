fix: correct README CLI flag to match cli.js (--upper)

## What
The README's usage example told users to run `node cli.js --uppercase hello`, but
`cli.js` only recognizes `--upper` (anything else prints the usage error and exits
1). Changed the documented command to `node cli.js --upper hello` so the example
actually works as written.

## Why
Lane: tiny (typo/one obvious edit, per WORKFLOW.md "Size the work first"). No spec
needed for this lane.

## Review
tiny-lane run-lite self-review: single-line README diff, no code behavior change.

## Testing
Ran the corrected command directly: `node cli.js --upper hello` -> `HELLO`,
matching the README's documented output.

## Checklist
- [x] Tiny-lane build + review gates recorded (`gate-ledger.sh show readme-cli-flag`)
- [x] Verified against the actual CLI, not just read
- [x] No regressions (docs-only change, no app code touched)
- [ ] Pushed / opened on the remote (no network push expected in this room; branch
      `fix/readme-cli-flag` holds the commit locally)
