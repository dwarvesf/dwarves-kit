# Proof of done: output-style-config (SPEC-252)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | Kit-root default `style = ""` leaves a fresh project's `settings.json` and `output-styles/` untouched | PASS | "kit-root default style="" leaves the project's outputStyle and output-styles/ untouched" |
| AC2 | Project `.kit.toml` `[output] style = "adhd"` copies the kit style in byte-for-byte and sets `outputStyle` | PASS | "project .kit.toml [output] style=adhd copies the kit style in and sets outputStyle" |
| AC3 | Re-running adopt `--refresh` with an unchanged key is a clean git no-op | PASS | "re-running adopt --refresh with an unchanged output.style is a clean no-op" |
| AC4 | A name the kit does not ship sets the key and copies nothing | PASS | "a style the kit does not ship sets the key only (nothing copied)" |
| AC5 | The settings write preserves the hook-module wiring | PASS | "setting outputStyle preserves the hook-module wiring in settings.json" |
| AC5b | A style name with `/` or `..` is refused: key unchanged, nothing written | PASS | "output.style with a path component is refused (key unchanged, nothing written)" |
| AC6 | Negative control | PASS | `.outputStyle` renamed to `.outputStyleX` in the adopt jq merge: `tests/test-adopt.sh` reports 2 NOT ok (AC2, AC4); restored, 0 NOT ok |
| AC7 | No regression | PASS | `test-install-modules.sh` 37/37, `test-install-contract.sh` 4/4, `shellcheck -S warning install.sh lib/adopt.sh` rc 1 with the same 5 warnings as origin/master (SC2034/SC2088/SC2155 at pre-existing lines, none new), `test-meta.sh` 843/843 after `feature-registry.sh generate` (the new test file mention moved one FEATURES.md row) |
| AC8 | `install.sh` step 7b: operator-level `outputStyle` default, path-shaped refusal, idempotent | PASS | `test-install-modules.sh` 42/42 (4 new cases; see run-table below) |

**Total: 27/27 PASS in `tests/test-adopt.sh` (21 pre-existing + 6 new). Regression suites unchanged.**

## Operator-level install.sh step (AC8, added 2026-09-10)

| Case | Result | Evidence |
|---|---|---|
| Operator `kit.toml` `[output] style = "adhd"` sets `outputStyle` in a scratch `$CLAUDE_DIR/settings.json` | PASS | `tests/test-install-modules.sh`: "operator kit.toml [output] style=adhd sets outputStyle in settings.json" |
| No `[output] style` anywhere in operator/kit-root scope | PASS | "no operator/kit-root output.style -> outputStyle key absent" |
| Re-run with the same operator style | PASS | "re-run with the same operator style is byte-identical" (settled past install.sh's own pre-existing first-run-vs-merge-path hook/permission reordering, unrelated to this step, before the byte comparison) |
| `[output] style = "../evil"` (path-shaped) | PASS | "path-shaped output.style is refused (outputStyle key absent)" + "path-shaped output.style prints a warning" |

```
$ bash tests/test-install-modules.sh 2>&1 | tail -10
== NC output-style operator-level (SPEC-252 install gap): install.sh sets outputStyle from operator kit.toml ==
  PASS  operator kit.toml [output] style=adhd sets outputStyle in settings.json
== NC output-style empty: no [output] style leaves outputStyle unset ==
  PASS  no operator/kit-root output.style -> outputStyle key absent
== NC output-style idempotent re-run: byte-identical settings.json ==
  PASS  re-run with the same operator style is byte-identical
== NC output-style path-shaped name refused ==
  PASS  path-shaped output.style is refused (outputStyle key absent)
  PASS  path-shaped output.style prints a warning

== 42 passed, 0 failed ==
```

Negative control: renamed the jq write target from `.outputStyle` to `.outputStyleX` in `install.sh` step 7b; `test-install-modules.sh` dropped to 41/42, failing exactly "operator kit.toml [output] style=adhd sets outputStyle in settings.json"; reverted, back to 42/42.

Regression, same run: `bash tests/test-adopt.sh` 27/27 PASS (unaffected; adopt's own path is untouched), `bash tests/test-meta.sh` 843/843 (no `docs/FEATURES.md` drift), `shellcheck -S warning install.sh` rc 1 with the same 5 warnings as `origin/master:install.sh` (3x SC2034, 2x SC2155 at pre-existing lines), none new.

`tests/test-no-personal-paths.sh` is red on master before this branch (`_meta/megagoals/learning-boundary/POINTER_PROMPT.md:9`); this branch adds no personal path (`output-styles/` and the spec are tenant-free).

## Reproduce

```
bash tests/test-adopt.sh
sed -i.nc 's/\.outputStyle = \$s/.outputStyleX = $s/' lib/adopt.sh && bash tests/test-adopt.sh | grep -c "NOT ok"   # expect 2
mv -f lib/adopt.sh.nc lib/adopt.sh
```

Independent arm: `kit:task-verifier` (fresh context) re-executed the suite and the negative control, probed invalid-JSON settings, a traversal-shaped name, `--dry-run`, and missing `jq`, and drove `install.sh` / `--uninstall` against a scratch `CLAUDE_DIR` (link created, real file preserved, only the kit link removed). Verdict PASS 7/7; its two findings (this shellcheck line, the path guard) are fixed in the same branch.

## What this closes

The kit can now ship a Claude Code output style and say which one an adopted project uses, from the same `.kit.toml` chain that already drives hook-module wiring. The first style is `adhd`. Which style a person sees on their own machine still follows the harness's precedence: their `settings.local.json` pick outranks the project file.
