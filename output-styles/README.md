# output-styles/

Kit-shipped Claude Code output styles. An output style is a markdown file whose body replaces (or, with `keep-coding-instructions: true`, sits beside) the harness's default response instructions. It shapes how the agent talks, never what it builds, and it lives in the system prompt, so it survives compaction and needs no hook.

## How a style reaches a session

| Path | Mechanism |
|---|---|
| Plugin install | Claude Code reads this directory as-is (`output-styles/` is the plugin-native name). |
| Bash install (`install.sh`) | each `<name>.md` here is symlinked into `~/.claude/output-styles/`; an existing real file there is left alone. |
| Adopted project | `[output] style = "<name>"` in the project's `.kit.toml` (or the operator or kit-root `kit.toml`) makes `lib/adopt.sh` copy `<name>.md` into `<project>/.claude/output-styles/` and set `outputStyle` in `<project>/.claude/settings.json`. |

Precedence follows the harness: `.claude/settings.local.json` (what the `/config` and `/output-style` pickers write) outranks the project `settings.json` the kit writes, so a person's own pick always wins on their machine. An empty `style = ""` leaves the project's setting untouched.

A name the kit does not ship (`Explanatory`, a style the operator installed by hand) still works: adopt sets the key and copies nothing.

## Adding a style

1. `output-styles/<name>.md` with `name`, `description`, and `keep-coding-instructions` frontmatter.
2. No tenant paths, names, or repo-specific rules (the kit contract, `docs/kit-contract.md`).
3. A row in the table of `docs/specs/SPEC-252-output-style-config.md`.

Contract: `docs/specs/SPEC-252-output-style-config.md`.
