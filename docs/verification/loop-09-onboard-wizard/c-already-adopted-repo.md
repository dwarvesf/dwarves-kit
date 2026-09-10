# Transcript (c): already-adopted repo -> healthy report, zero write

**Scenario:** the wizard is run inside a repo that is ALREADY adopted. Proves the "adopted" branch:
report healthy, call adopt NEVER, write nothing, go straight to the tour. Verified by a byte-identical
tree hash before/after the wizard run.

**Setup note (honest deviation):** the goal names "this repo" as the already-adopted case, but the kit's
own repo is not self-adopted via the `<!-- kit:adopt -->` marker (`adopt --check` on this worktree returns
`not adopted`, verified). So this transcript uses a fixture repo that is pre-adopted in a SETUP step
BEFORE the wizard runs , the honest substitute that proves the exact property the goal wants (already
adopted -> the wizard writes nothing).

## Setup (before the wizard): pre-adopt the fixture

```
setup: adopt: project hook-module wiring for .../repo-c -> modules: board session advisor
setup: adopt: .../repo-c (updated)
```

---

## The wizard run begins (on the already-adopted repo)

### A. Detect the install mode

```
bash	installed via bash install.sh; $CLAUDE_DIR/settings.json registers the kit hooks directly, and $CLAUDE_DIR/dwarves-kit holds the engine copies.
```

### B. Offer to adopt , but it's already adopted

`adopt.sh --check "$REPO"`:

```
adopted: .../repo-c
```

The wizard reports what's present (a read-only health check , no adopt call):

```
  present: AGENTS.md
  present: WORKFLOW.md
  present: docs/verification/README.md
  present: .kit.toml
  present: CLAUDE.md @AGENTS.md loader block
```

> **Wizard:** This repo is already adopted, everything is in place: AGENTS.md, the CLAUDE.md loader
> block, the WORKFLOW pointer, the proof marker, and `.kit.toml` recording your module choices. I won't
> write anything. To change modules later, hand-edit `.kit.toml`'s `[modules]` and re-run
> `/kit:adopt --refresh`. Straight to the tour.

### Zero-write proof , tree hash before/after the wizard run

```
### C.tree-before
PORCELAIN_LINES=6  FILESET_SHA=df2ea4a2d4577791d7e7f982917bdf7f7431be11
### C.wizard takes the 'already adopted' branch: reports healthy, NO adopt call, moves to the tour.
### C.tree-after (wizard wrote nothing)
PORCELAIN_LINES=6  FILESET_SHA=df2ea4a2d4577791d7e7f982917bdf7f7431be11
IDENTICAL: the already-adopted health tour wrote nothing
```

The 6 porcelain lines are the SETUP adopt's files (they predate the wizard run); the wizard adds nothing.
The file-set hash is byte-identical before and after , the "adopted" branch wrote zero bytes.

### G. The welcome tour

Same five-leg loop + `/kit:start` pointer as transcripts (a)/(b).

---

## Outcome

On an already-adopted repo the wizard is a read-only health tour: it reports the four contract files +
`.kit.toml` present, calls adopt zero times, and leaves the tree byte-identical. This is the
"already-adopted -> no write" property, proven by the matching before/after file-set hash.
