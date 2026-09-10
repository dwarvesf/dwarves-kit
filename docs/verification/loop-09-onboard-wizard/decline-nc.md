# Decline negative-control: declining every prompt leaves the tree byte-identical

**Scenario:** scenario (b)'s setup (bash machine, fresh unadopted repo), but the user DECLINES every
prompt , declines adopt, declines modules, declines knobs. Proves the wizard's core invariant: a
decline is a strict no-op. Captured `git status --porcelain` + the git tree hash + the file-set hash
before and after are byte-identical.

**Setup:** `$CLAUDE_DIR` = the bash-install fixture; `$REPO` = a fresh unadopted `git init` repo.

---

## Before (clean, unadopted)

```
### NC.tree-before (porcelain + tree hash)
PORCELAIN_LINES_BEFORE=0
GIT_TREE_BEFORE=d1f694d2bb4c6528827f57d713128d7af0e47ece
FILE_SHA_BEFORE=650791aad11ac188263e9a83bc89f1c84861b343
```

## The wizard run (every prompt declined)

Detect:

```
bash	installed via bash install.sh; $CLAUDE_DIR/settings.json registers the kit hooks directly, and $CLAUDE_DIR/dwarves-kit holds the engine copies.
```

`adopt --check "$REPO"` -> `not adopted`. The wizard shows the `--dry-run` preview (informational only,
writes nothing):

```
adopt: would create AGENTS.md (from .../AGENTS.md)
adopt: would write WORKFLOW.md pointer
adopt: would append the CLAUDE.md @AGENTS.md loader block
adopt: would create docs/verification/README.md (proof marker)
adopt: would seed a starter .kit.toml (modules: kit-root defaults)
adopt: would wire .../repo-nc/.claude/settings.json for modules: board session advisor (hooks:...)
adopt: --dry-run for .../repo-nc (changes above)
```

> **Wizard:** Adopt this repo now? [Y/n]  **User:** `n`
> **Wizard:** (adoption declined , skipping module selection and knobs, jumping to the tour.)

Because adoption was declined, the wizard never reaches C (modules) or the adopt-write, and never touches
`.kit.toml` or `settings.json`. It jumps straight to the tour (G).

## After (unchanged)

```
### NC.tree-after
PORCELAIN_LINES_AFTER=0
GIT_TREE_AFTER=d1f694d2bb4c6528827f57d713128d7af0e47ece
FILE_SHA_AFTER=650791aad11ac188263e9a83bc89f1c84861b343
### NC.verdict
IDENTICAL: tree + file-set byte-identical before/after
```

---

## Outcome

Three independent measures , `git status --porcelain` (0 lines both), the git tree object hash
(`d1f694d2...` both), and the working-tree file-set hash (`650791aa...` both) , are byte-identical
before and after a full wizard run in which every prompt was declined. A decline writes nothing. This is
the negative control for the "every write previewed + confirmed; decline = no-op" invariant.

The `--dry-run` preview the wizard shows is deliberately part of this: previewing what adopt *would* do
writes nothing, which is why the tree is still pristine after the preview + the decline.
