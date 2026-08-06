# fix: correct README CLI flag from --uppercase to --upper

## What

`README.md`'s usage example documented `node cli.js --uppercase hello`, but
`cli.js` only recognizes the `--upper` flag. Running the documented command
fails (`usage: cli.js --upper <text>`, exit 1) instead of printing `HELLO`.
This change corrects the README example to use the actual flag.

## Why

A README example that doesn't work as documented is the first thing a new
user hits and immediately breaks trust in the docs. Tiny, docs-only fix
(`lane: tiny`, classified via `lib/classify/lane-classify.sh`).

## Review

Self-review (tiny lane, run-lite): confirmed `cli.js` only implements
`--upper`, confirmed the old README command fails, confirmed the corrected
command matches the CLI's actual behavior.

## Testing

Ran the corrected documented command directly:

```
$ node cli.js --upper hello
HELLO
```

Ran the old (incorrect) documented command to confirm it was in fact broken:

```
$ node cli.js --uppercase hello
usage: cli.js --upper <text>
(exit 1)
```

## Checklist

- [x] Documented command now matches actual CLI behavior
- [x] Docs updated (README.md is the change itself)
- [x] Review: self-review (tiny lane), SHIP
- [x] No regressions (single-line docs change, no code touched)
