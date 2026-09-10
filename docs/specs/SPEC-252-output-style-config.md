# SPEC-252: configurable Claude Code output style (`[output] style`)

Status: SHIPPED (test + run-table confirmed)
Lane: normal
Backlog: kit ID-826
Branch: feat/output-style-config
Relates-to: SPEC-192 (adopt-time wiring of `.kit.toml` into project settings, the pattern this
extends), `lib/config/kit-config.sh` (the resolver), `output-styles/README.md` (the operator
door), ops-toolkit `research/2026-09-10-i-have-adhd-absorption.md` (where the first style
and the "style, not mode" decision come from)

## Problem

An output style is how a Claude Code session talks: the harness's own "how you respond"
surface, a markdown file the harness puts in the system prompt. The kit had no way to
ship one or to say which one an adopted project uses. The alternative, a kit "mode" made
of hooks, was rejected in the absorption record: an output-shape overlay touches no
lifecycle phase, adds a Stop-hook nudge to a turn that already carries four, and can be
compacted away, which a system-prompt style cannot.

## Design

One config key, one adopt step, one install step, one shipped directory.

| Piece | Contract |
|---|---|
| `kit.toml` `[output] style = ""` | Resolves through `kit_config_get output.style` (project `.kit.toml` > operator `kit.toml` > kit root). Empty means "the kit has no opinion". |
| `output-styles/<name>.md` | Kit-shipped styles. The directory name is the plugin-native one, so a plugin install serves them with no extra step. Frontmatter: `name`, `description`, `keep-coding-instructions`. No tenant content (kit contract). |
| `lib/adopt.sh` step 6b | When the resolved style is non-empty: copy `output-styles/<name>.md` to `<project>/.claude/output-styles/<name>.md` if the kit ships it (byte-compare first, so an unchanged re-run is a no-op), then set `.outputStyle` in `<project>/.claude/settings.json` by a targeted jq merge (every other key, the hook wiring included, is preserved). A name the kit does not ship sets the key only. A name carrying `/` or `..` is refused with a warning and nothing is written. Runs on every adopt invocation, so editing the key and re-running adopt reconfigures the project. Empty never writes and never removes. |
| `install.sh` step 4a | Symlink every kit style into `~/.claude/output-styles/` so `/output-style <name>` works user-wide. A real file already there is left alone. `--uninstall` removes only links that point at the kit. |
| `install.sh` step 7b | Operator-level default (closes the gap adopt.sh step 6b left: adopt writes a per-PROJECT style, nothing wrote an OPERATOR's own default). Resolves `output.style` operator > kit-root only (`KIT_PROJECT_ROOT` points at an empty scratch dir, so no nearby repo's `.kit.toml` leaks in); a non-empty, bare (`/`, `..` refused) name sets `.outputStyle` in `$CLAUDE_DIR/settings.json` by a targeted jq merge when it differs from the current value. Empty never writes. Not run on `--uninstall`: a person's chosen style is their own setting, never stripped back out. |

Precedence is the harness's own: `settings.local.json` (what the `/output-style` and
`/config` pickers write) outranks the project `settings.json` the kit writes, which
outranks the user file. The kit sets the shared project default; a person's pick on
their machine still wins. Subagents run their own system prompt and are not styled;
that is a harness property, not a kit choice.

## Not

- No runtime hook reads the key (same rule as SPEC-192: adopt-time only).
- No module gate. It is a key, not a hook; `cosmetic=false` does not disable it.
- No removal path. `style = ""` hands control back by not writing; deleting a project's
  style file or key is the operator's edit.
- No `force-for-plugin`. A kit style never overrides a person's `outputStyle`.

## Acceptance

| # | Criterion | Test |
|---|---|---|
| AC1 | Kit-root default `""` leaves a fresh project's `settings.json` and `output-styles/` untouched | `tests/test-adopt.sh` "kit-root default style="" leaves ..." |
| AC2 | Project `.kit.toml` `[output] style = "adhd"` copies the kit style in byte-for-byte and sets `outputStyle` | "... copies the kit style in and sets outputStyle" |
| AC3 | Re-running adopt with an unchanged key is a clean git no-op | "... unchanged output.style is a clean no-op" |
| AC4 | A name the kit does not ship sets the key and copies nothing | "a style the kit does not ship sets the key only" |
| AC5 | The settings write preserves the hook-module wiring | "setting outputStyle preserves the hook-module wiring" |
| AC5b | A name with `/` or `..` is refused, key unchanged, nothing written | "output.style with a path component is refused" |
| AC6 | Negative control: breaking the settings write fails AC2 and AC4 | run-table in the proof |
| AC7 | No regression: install module suite, install contract, meta, shellcheck | proof |
| AC8 | `install.sh` sets an operator-level default `outputStyle` from operator/kit-root `[output] style`, refuses a path-shaped name, and is idempotent | `tests/test-install-modules.sh` "NC output-style operator-level" block |

## Verification

```
bash tests/test-adopt.sh
bash tests/test-install-modules.sh
bash tests/test-install-contract.sh
bash tests/test-meta.sh
shellcheck -S warning install.sh lib/adopt.sh
```

Proof: `docs/verification/output-style-config/proof-of-done.md`.

## Shipped styles

| Style | What | Source |
|---|---|---|
| `adhd` | Concise superset: next action first, numbered steps, step N of M restated per turn, wins visible, five per group, evidence-gated causes, one next action at the end | ayghri/i-have-adhd (MIT), trimmed to the rules a Concise-style operator lacks |
