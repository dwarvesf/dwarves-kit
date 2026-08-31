# docs: fix README usage example to match CLI --upper flag

## Summary

The README usage example documented `node cli.js --uppercase hello`, but the CLI's
`cli.js` accepts `--upper` (not `--uppercase`). Running the documented command against
the real CLI exited 1 with a usage error. This change corrects the example so the
documented command matches the actual flag and works as described.

## Change

- `README.md`: `--uppercase` -> `--upper` in the usage example.
- `package.json`: patch bump 1.0.0 -> 1.0.1 (docs change).
- `CHANGELOG.md`: added 1.0.1 entry.

## Verification

- `node cli.js --upper hello` now prints `HELLO` (exit 0), matching the corrected example.

## Lane

Tiny lane (one obvious doc edit). No spec required. Gate records for this run
(`readme-example-flag`) are in the kit's run ledger: build + review + ship recorded.
