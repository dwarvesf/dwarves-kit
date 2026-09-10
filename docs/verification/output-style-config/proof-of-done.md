# Proof of done: output-style-config (SPEC-252)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | Kit-root default `style = ""` leaves a fresh project's `settings.json` and `output-styles/` untouched | PASS | "kit-root default style="" leaves the project's outputStyle and output-styles/ untouched" |
| AC2 | Project `.kit.toml` `[output] style = "adhd"` copies the kit style in byte-for-byte and sets `outputStyle` | PASS | "project .kit.toml [output] style=adhd copies the kit style in and sets outputStyle" |
| AC3 | Re-running adopt `--refresh` with an unchanged key is a clean git no-op | PASS | "re-running adopt --refresh with an unchanged output.style is a clean no-op" |
| AC4 | A name the kit does not ship sets the key and copies nothing | PASS | "a style the kit does not ship sets the key only (nothing copied)" |
| AC5 | The settings write preserves the hook-module wiring | PASS | "setting outputStyle preserves the hook-module wiring in settings.json" |
| AC6 | Negative control | PASS | `.outputStyle` renamed to `.outputStyleX` in the adopt jq merge: `tests/test-adopt.sh` reports 2 NOT ok (AC2, AC4); restored, 0 NOT ok |
| AC7 | No regression | PASS | `test-install-modules.sh` 37/37, `test-install-contract.sh` 4/4, `shellcheck -S warning install.sh lib/adopt.sh` rc 0, `test-meta.sh` 843/843 after `feature-registry.sh generate` (the new test file mention moved one FEATURES.md row) |

**Total: 26/26 PASS in `tests/test-adopt.sh` (21 pre-existing + 5 new). Regression suites unchanged.**

`tests/test-no-personal-paths.sh` is red on master before this branch (`_meta/megagoals/learning-boundary/POINTER_PROMPT.md:9`); this branch adds no personal path (`output-styles/` and the spec are tenant-free).

## Reproduce

```
bash tests/test-adopt.sh
sed -i.nc 's/\.outputStyle = \$s/.outputStyleX = $s/' lib/adopt.sh && bash tests/test-adopt.sh | grep -c "NOT ok"   # expect 2
mv -f lib/adopt.sh.nc lib/adopt.sh
```

## What this closes

The kit can now ship a Claude Code output style and say which one an adopted project uses, from the same `.kit.toml` chain that already drives hook-module wiring. The first style is `adhd`. Which style a person sees on their own machine still follows the harness's precedence: their `settings.local.json` pick outranks the project file.
