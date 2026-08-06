## What

Adds a `--repeat N` flag to the `shout` CLI. `shout --upper --repeat 3 hello`
now prints `HELLO` three times; `--repeat` and `--upper` can appear in either
order. With no `--repeat`, behavior is unchanged (prints once).

`N` must be a positive integer: 0, negative, or non-numeric `N` is a usage
error on stderr with exit code 1.

## Why

Team ask: "`shout --upper hello` works; we want `--repeat N`". See
`docs/specs/SPEC-001-repeat-flag.md` for the full spec (problem, approaches
considered, decision log).

## Review

`docs/specs/SPEC-001-repeat-flag.md` `## Review`: **Verdict: SHIP**, 0
findings, 0 open TODOs.

## Testing

- `npm test` (`node --test`): 8/8 passing -- N=1, N=3, flag-order swap, N=0,
  N=-2, N=banana, no-`--repeat` (default), no-`--upper` (unchanged error path).
- Proof-of-done with a negative control: `docs/verification/repeat-flag.md`
  (green run + the same command re-run against the pre-feature `cli.js`,
  confirmed RED, restored).

## Checklist

- [x] Tests pass (`npm test`, 8/8)
- [x] Docs updated (`README.md`, spec's `## Verification` / `## Test plan`)
- [x] Review: SHIP
- [x] No regressions (`--upper`-only path covered by test 1 and test 8)
