# Transcript (b): bash-install machine, unadopted repo (module toggle + registry-only add-on)

**Scenario:** a machine where the kit is installed via `bash install.sh` (its hooks registered in
`settings.json`), run inside a fresh unadopted repo. Proves: detect -> `bash`, the `--with` bridge
actually seeding a toggled module, AND the honest disclosure for a registry-only add-on (`prose_rag`)
that `adopt --with` cannot seed, with its consumer knob (`PROSE_RAG_INJECT`) surfaced from the registry.

**Setup (fixture):**
- `$CLAUDE_DIR` = a temp HOME `.claude` with a `settings.json` registering a `dwarves-kit/hooks/*.sh`
  command (the full bash install signal), plus a `dwarves-kit/` dir.
- `$REPO` = a fresh unadopted `git init` repo.

---

## A. Detect the install mode

```
bash	installed via bash install.sh; $CLAUDE_DIR/settings.json registers the kit hooks directly, and $CLAUDE_DIR/dwarves-kit holds the engine copies.
```

> **Wizard:** You're on the bash install: your `settings.json` drives the kit hooks directly. Let's set
> up this repo.

## B. Offer to adopt this repo

`adopt.sh --check "$REPO"` -> `not adopted: .../repo-b`. The wizard previews with `--dry-run`:

```
adopt: would create AGENTS.md (from .../AGENTS.md)
adopt: would write WORKFLOW.md pointer
adopt: would append the CLAUDE.md @AGENTS.md loader block
adopt: would create docs/verification/README.md (proof marker)
adopt: would seed a starter .kit.toml (modules: kit-root defaults)
adopt: would wire .../repo-b/.claude/settings.json for modules: board session advisor (hooks:...)
adopt: --dry-run for .../repo-b (changes above)
```

> **Wizard:** Not adopted yet. Adopt now? [Y/n]  **User:** `y`

## C. Pick the modules, then adopt in ONE call

Roster generated from the registry (same 12 module rows as transcript (a)). This user wants the baseline
PLUS `bridge` (the Hermes cockpit mirror, default off). The wizard shows its purpose
(`bin/config explain modules.bridge`):

```
modules.bridge (module=bridge, status=[impl])
  Hookless; Hermes cockpit mirror.
  ...
  4. default          = `false`
Effective: false   (source: kit-root kit.toml)
```

> **Wizard:** Baseline + `bridge`? [Enter = baseline; naming toggles]  **User:** `bridge`

`bridge` is in `adopt --with`'s seedable set, so the wizard adopts in ONE call
(`adopt.sh --with "board,session,advisor,queue,stats,bridge" "$REPO"`):

```
adopt: project hook-module wiring for .../repo-b -> modules: board session advisor
adopt: .../repo-b (updated)
```

The seeded `<repo>/.kit.toml` , `bridge = true`, picked via `--with`:

```
[modules]
board = true
session = true
advisor = true
cosmetic = false
queue = true
stats = true
quiz_gate = false
weekend_batch = false
bridge = true
```

**Honest caveat surfaced by the wizard:** this user ALSO asked for `prose_rag`. `adopt --with` seeds only
the install-recorded module set and does NOT reach the three add-ons `worktree`/`money_gate`/`prose_rag`,
so the wizard does not pretend `--with` handled it. It shows the module's purpose
(`bin/config explain modules.prose_rag`):

```
modules.prose_rag (module=prose_rag, status=[impl])
  `prose-rag.sh` recall inject + CLI; dormant without `PROSE_RAG_INJECT=1`.
  ...
  4. default          = `false`
Effective: false   (source: kit-root kit.toml)
```

## D. Consumer knobs (generated from the registry, filtered to the chosen module)

For `prose_rag` the wizard filters `bin/config list` to the rows whose MODULE column is `prose_rag`:

```
KEY                            STATUS     VALUE                 PROVENANCE   MODULE
PROSE_RAG_INJECT               [impl]     unset (hook inert)    default      prose_rag
modules.prose_rag              [impl]     false                 kit-root kit.toml   prose_rag
```

`PROSE_RAG_INJECT` is env-only (`bin/config explain PROSE_RAG_INJECT`):

```
PROSE_RAG_INJECT (module=prose_rag, status=[impl])
  The engine's own opt-in master switch for the recall-inject hook ...
  1. env             PROSE_RAG_INJECT     = (unset)
  2. project .kit.toml n/a (this key has no kit.toml backing: env-only)
  3. kit-root kit.toml n/a (this key has no kit.toml backing: env-only)
  4. default          = unset (hook inert)
Effective: unset (hook inert)   (source: default)
```

> **Wizard:** `prose_rag` is a registry-only add-on, so `adopt --with` can't seed it. To turn it on:
> 1. add to `$REPO/.kit.toml` `[modules]`: `prose_rag = true`
> 2. re-run `/kit:adopt --refresh "$REPO"` (re-wires `settings.json`)
> 3. it's also dormant until the env switch is set: `export PROSE_RAG_INJECT=1` in your shell profile.
>
> That's the honest reach of the existing mechanic , I won't silently drop your pick.

## E. Plugin-path gaps

Skipped: this is the `bash` path, no plugin gap to disclose.

## F. Install staleness (one line, bash mode only)

The fixture has no `INSTALL-STAMP` (or it matches HEAD), so the wizard prints nothing. Had it been stale,
the entire surface would be ONE line: "Your bash install (sha `<x>`) is behind the checkout (`<y>`);
re-run `bash install.sh` to refresh. Details: `/kit:kit-health`." Never a flow.

## G. The welcome tour

The five-leg loop in five sentences + "Next: run `/kit:start`" (identical to transcript (a)'s section G).

---

## Outcome

Detected `bash`; the `--with` bridge genuinely seeded the toggled `bridge` module into `.kit.toml` in one
adopt call; the registry-only add-on `prose_rag` was disclosed honestly (hand-edit + `--refresh` + the
`PROSE_RAG_INJECT` env guidance), never silently dropped. Every knob shown was generated from the
registry, not a hardcoded list. The only writer driven was `lib/adopt.sh`.

**Note for the maintainer (adjacent defect, out of this sub-goal's scope):** `lib/adopt.sh`'s
`KIT_KNOWN_MODULES` (9 modules) is stale versus `install.sh`'s (12); it omits `worktree money_gate
prose_rag`, which is exactly why `adopt --with` cannot seed them. Fixing adopt.sh is out of scope here
(the goal forbids adopt.sh changes); the wizard is honest about the gap. A follow-up should sync
adopt.sh's list with install.sh.
