docs: fix README usage example flag --uppercase to --upper

## Problem
The README documents `node cli.js --uppercase hello`, but the CLI actually
accepts `--upper`. The documented command fails (exit 1) with a usage error.

## Change
Updated the README Usage example to the real flag: `node cli.js --upper hello`.

## Verification
- `node cli.js --upper hello` prints `HELLO` (exit 0).
- Negative control: `node cli.js --uppercase hello` still errors (this is a
  docs-only change; the CLI is untouched).

## Notes
Routed through the tiny lane (docs-only, one obvious edit). Adoption
leave-behinds (AGENTS.md, .kit.toml, proof marker) committed in a separate
commit. Gate ledger records build/review ran plus an inert proof-of-done marker.
