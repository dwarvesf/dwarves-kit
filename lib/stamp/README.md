# stamp

Writes a kit-free agent harness into a repo as plain files the repo owns. This directory holds the notes; the driver is `lib/stamp.sh` and the templates are `templates/team-stamp/`. The verb knows no file by name: every file comes from a manifest row.

**Entry points**
- `lib/stamp.sh [--check | --dry-run | --refresh | --take <path>] [--only <groups>] [value flags] <target-dir>`. Default writes what is missing, merges `.claude/settings.json`, and updates the lock. Never overwrites a file the repo edited.
- `.claude/team-stamp.lock` in the target: the values used and one `sha256:<hex>` per written file (the marker keeps a secret scan from reading a digest as a key). Plain text, kit-free. Any hash a template carries uses the same marker form: `sha256:<hex>`, `sha256=<hex>` or `sha256: <hex>`, never a bare run of hex.

**Tests**: `bash tests/test-stamp.sh` (engine, against `tests/fixtures/team-stamp/`) and `bash tests/test-stamp-kitfree.sh <group|fixture|all>`.

**Spec and notes**: `docs/specs/SPEC-425-team-stamp.md`, `docs/implementation-notes/team-stamp.md`.

## How a group plugs in

A group is one manifest file plus its templates. Add exactly `templates/team-stamp/manifest.d/NN-<group>.tsv` and files under `templates/team-stamp/files/`. No group edits `lib/stamp.sh`, another group's manifest, or this README.

### Manifest row

Five tab-separated columns. Blank lines and lines starting with `#` are ignored. A column is never empty (write `-` for no keys).

```
action<TAB>source<TAB>target<TAB>mode<TAB>keys
```

| Column | Meaning |
|---|---|
| action | `copy`: render, write when absent, drift-checked after. `seed`: like `copy`, but never drift-checked once it exists (repo-living files such as `OWNERS.md`, `CHANGELOG.md`, `.claude/memory/MEMORY.md`); created again when deleted. `jsonmerge`: merge the rendered JSON object into the target by `hooks` entry (match on `matcher`, then on `command`); other keys of the target are kept, a duplicate is never added, invalid JSON refuses the run. `hook`: run a script, write its stdout as the file, seed-once. |
| source | `copy`, `seed`, `jsonmerge`: a path under `templates/team-stamp/`, normally `files/<target path>`, with a `.tpl` suffix when the file takes a value. `hook`: a script, `lib/stamp/<name>.sh` (relative to the kit root) or a path under the templates root. |
| target | Repo-relative path, no `..`, no spaces. Unique across every group. |
| mode | Octal, `0644` or `0755`. Applied only to a file the stamp creates. |
| keys | Comma list of the `{{KEY}}` names the template uses, or `-`. A template that uses an undeclared key, or declares an unknown key, aborts the run. |

The group name is the manifest file name after `NN-` and before `.tsv`. `NN` orders the files; it carries no other meaning.

A `hook` script runs with the target repo as its working directory and gets `$1` = the target path. It reads `$STAMP_TARGETS_FILE` (every target of the selected groups, one per line), `$STAMP_ALL_TARGETS_FILE` (every target of every group, even under `--only`; use this for a seed built from the merged manifest) and `$STAMP_VALUES_FILE` (`KEY<TAB>value`). It prints the file content to stdout and exits 0.

### Values: `{{KEY}}` names

| Key | From | Example for `--tags app,lib` etc. |
|---|---|---|
| `DEFAULT_BRANCH` | `--default-branch`, else `origin/HEAD`, else refuse | `main` |
| `OWNER` | `--owner` (no default, refuses when a row needs it) | `alice` |
| `TAGS` | `--tags`, default `product,dev`; `dev` is always added | `app,lib,dev` |
| `PRODUCT_PATHS` | `--product-paths`, default `src/` | `src/,lib/` |
| `DOOR_PATHS` | `--door-paths`, default empty | `docs/legal/*,protocol/*` |
| `DOOR_APPROVER` | `--door-approver`, default empty | `carol` |
| `BOARD_FILE` | `--board-file`, default empty | `docs/BOARD.md` |
| `DECISION_TAG` | `--decision-tag`, default `decision` | `decision` |
| `TAGS_ERE` | derived | `app|lib|dev` |
| `TAGS_COLON` | derived | `app: lib: dev:` |
| `TAGS_AWK` | derived | `"app", "lib", "dev"` |
| `PRODUCT_ERE` | derived, dots escaped | `^(src/|lib/)` |
| `PRODUCT_ARRAY` | derived, a bash array body | `"src/" "lib/"` |
| `DOOR_ARRAY` | derived, a bash array body, **empty when no door path is set** (a script must guard an empty array under `set -u` on bash 3.2) | `"docs/legal/*" "protocol/*"` |
| `DOOR_CASE` | derived, a `case` pattern; a never-matching word when empty | `docs/legal/*|protocol/*` |
| `STAMP_VERSION` | the engine | `1` |
| `AGENTS_MARKER` | line 1 of `lib/adopt/AGENTS.pointer.md`, refused unless it starts `<!-- kit:agents-pointer` | the adopt marker |

The engine refuses any flag value that holds a newline, a carriage return or a tab before it reads anything else, then matches the whole value against a narrow character set (no space, no shell quote, no `{{`). A path-like value (`--board-file`, `--product-paths`, `--door-paths`) may not start with `/` or hold a `..` component. Every run prints the values in use and whether each came from a flag, the lock or a default (`using: KEY=value (source)` on stderr), so a value taken silently from a planted lock is seen. Values are remembered in the lock, so a re-run with no flags renders the same bytes.

### What the engine checks on every rendered file

- No `{{KEY}}` is left.
- No kit path (`.claude/dwarves-kit`, `CLAUDE_PLUGIN_ROOT`, `KIT_ROOT`, `lib/gate/`, `/bin/gate|classify|wrap|board`) and no absolute home path. One hit refuses the whole run before any write.
- No write through a symlink, no write outside the target.

A refusal prints two lines: `stamp: <rule>` then `Fix: <command>`. A status line is `<status>: <path>`: `created`, `merged`, `unchanged`, `edited (left alone)`, `older stamp (run --refresh)`, `missing`.

### Test conventions

- A test of a valued script is a `.tpl` too, and reads the stamped values from the repo, never a literal `main` or a fixed tag. The kit-free run uses non-default values.
- A generated test is `scripts/test-<name>.sh`. `tests/test-stamp-kitfree.sh` runs every one of them with the kit absent from `PATH` and `HOME`.

### Group test recipe

Run the group through the harness; it finds the group by file name:

```bash
bash tests/test-stamp-kitfree.sh <group>      # <group> is the name after NN- in manifest.d, e.g. hook
```

That stamps only that group into a fresh temp repo with non-default values (`--default-branch master --owner testowner --tags app,lib --product-paths app/,pkg/ --door-paths 'docs/legal/*' --door-approver reviewer --decision-tag decision --board-file docs/BOARD.md`), greps every file the lock lists for kit paths, and runs each stamped `scripts/test-*.sh` with a stripped `PATH` and an empty `HOME`.

For your own `tests/test-stamp-<group>.sh`, stamp the group yourself:

```bash
T="$(mktemp -d)"; git -C "$T" init -q
bash lib/stamp.sh --only <group> --default-branch main --owner testowner "$T"
# now assert on "$T"; run "$T"/scripts/test-<name>.sh; rerun lib/stamp.sh to prove it is idempotent
```

`bash tests/test-stamp.sh` drives the engine with `STAMP_TEMPLATES=tests/fixtures/team-stamp`, a two-group fixture tree that is the format reference for a manifest.
