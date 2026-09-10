# Transcript (a): fresh plugin-only machine, unadopted repo

**Scenario:** a machine where the kit is installed ONLY as a Claude Code plugin (no bash install), run
inside a fresh consumer repo that has not been adopted. Proves: detect -> `plugin`, offer adopt with a
previewed dry-run, accept the baseline, one adopt call, plugin-path gap disclosure, five-leg tour.

**Setup (fixture, not part of the wizard):**
- `$CLAUDE_DIR` = a temp HOME `.claude` containing only `plugins/cache/dwarves-marketplace/kit/2.0.0/lib`
  (a plugin cache, the exact glob `install.sh:328` keys on), no `settings.json` hooks.
- `$REPO` = a fresh `git init` repo with a README + package.json, committed, unadopted.

The captures below are the REAL output of the commands `/kit:onboard` drives (`lib/onboard-detect.sh`,
`lib/adopt.sh`, `bin/config`), run against that fixture.

---

## A. Detect the install mode

Wizard runs `bash "$KIT/lib/onboard-detect.sh" explain`:

```
plugin	installed as a Claude Code plugin; runtime loads from the plugin (${CLAUDE_PLUGIN_ROOT}). No kit hooks are registered in settings.json, so nothing double-fires.
```

> **Wizard:** You're on the plugin path: the runtime loads from the plugin. The bash-only extras (the
> statusLine HUD, and `install.sh --with` for module selection) aren't wired here, but I'll bridge the
> module choice through `/kit:adopt` below. Nothing double-fires. Let's set up this repo.

## B. Offer to adopt this repo

Wizard runs `bash "$KIT/lib/adopt.sh" --check "$REPO"`:

```
not adopted: /var/folders/.../repo-a
```

Not adopted, so the wizard previews with `--dry-run` before asking anything:

```
adopt: would create AGENTS.md (from .../AGENTS.md)
adopt: would write WORKFLOW.md pointer
adopt: would append the CLAUDE.md @AGENTS.md loader block
adopt: would create docs/verification/README.md (proof marker)
adopt: would seed a starter .kit.toml (modules: kit-root defaults)
adopt: would wire .../repo-a/.claude/settings.json for modules: board session advisor (hooks:backlog-stage.sh context-readiness.sh output-offload.sh pre-compact-backup.sh post-compact-reinject.sh session-state-save.sh harvest.sh citation-guard.sh context-hints.sh)
adopt: --dry-run for .../repo-a (changes above)
```

> **Wizard:** This repo isn't adopted yet. Adopting creates AGENTS.md + a CLAUDE.md loader + a WORKFLOW
> pointer + the proof marker (all non-destructive, never overwritten later). Adopt this repo now? **[Y/n]**
>
> **User:** `<Enter>` (accepts the recommended default, Y)

## C. Pick the modules, then adopt in ONE call

The roster is generated from the registry (`bin/config list`, rows whose display KEY is `modules.*`):

```
KEY                            STATUS     VALUE      PROVENANCE           MODULE
modules.board                  [impl]     true       kit-root kit.toml    board
modules.session                [impl]     true       kit-root kit.toml    session
modules.advisor                [impl]     true       kit-root kit.toml    advisor
modules.cosmetic               [impl]     false      kit-root kit.toml    cosmetic
modules.queue                  [impl]     true       kit-root kit.toml    queue
modules.stats                  [impl]     true       kit-root kit.toml    stats
modules.quiz_gate              [impl]     false      kit-root kit.toml    quiz_gate
modules.weekend_batch          [impl]     false      kit-root kit.toml    weekend_batch
modules.bridge                 [impl]     false      kit-root kit.toml    bridge
modules.worktree               [impl]     false      kit-root kit.toml    worktree
modules.money_gate             [impl]     false      kit-root kit.toml    money_gate
modules.prose_rag              [impl]     false      kit-root kit.toml    prose_rag
```

> **Wizard:** The recommended baseline is board + session + advisor + queue + stats (on by default);
> cosmetic, quiz_gate, weekend_batch, bridge, worktree, money_gate, prose_rag are off. Accept the
> baseline, or name any to toggle. **[Enter = baseline]**
>
> **User:** `<Enter>` (accepts the baseline)

The baseline equals the kit-root defaults, so the wizard adopts with the defaults in ONE call
(`bash "$KIT/lib/adopt.sh" "$REPO"`):

```
adopt: project hook-module wiring for .../repo-a -> modules: board session advisor
adopt: .../repo-a (updated)
```

The seeded `<repo>/.kit.toml`:

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
bridge = false
```

> **Wizard:** Adopted. `.kit.toml` records your module baseline, and adopt wrote the
> board/session/advisor hook entries into this repo's `settings.json`. One plugin-path honesty note up
> front: those wired entries point at the bash-install hook path, which doesn't exist on this machine,
> so they won't fire yet, details in the gaps section below. (adopt is invoked exactly once; it is
> never called again.)

## D. Consumer knobs (generated from the registry, filtered to the chosen modules)

board, session, advisor, and queue carry no `[impl]` knob row needing attention (their rows all have
working defaults). `stats` does: the wizard filters `bin/config list` to MODULE=stats and finds four
OPTIONAL data-source vars (skip-safe by design):

```
KEY                            STATUS     VALUE                          PROVENANCE   MODULE
STATS_TIDE_DB                  [impl]     **no-default-consumer**        default      stats
STATS_TGCLEANUP_DIR            [impl]     **no-default-consumer**        default      stats
STATS_LEARNED_MD               [impl]     **no-default-consumer**        default      stats
STATS_REPOS                    [impl]     **no-default-consumer**        default      stats
```

> **Wizard:** Nothing you MUST set: your chosen modules all work as adopted. `stats` has four optional
> data-source vars, each safe to leave unset (an unset source just renders its table empty, never an
> error). Set one only if you have that source, e.g. `export STATS_REPOS=/path/a,/path/b` to feed
> `stats review-yield`. Enter to skip them all.
>
> **User:** `<Enter>` (skips; the defaults are a working baseline)

## E. Plugin-path gaps (honest disclosure)

> **Wizard:** Because you're on the plugin path, four honest caveats:
> - **statusLine HUD:** the v1 plugin schema has no `statusLine` field, so the status-line HUD is
>   bash-install-only. That's the one reason to run the bash install instead.
> - **Frozen SHA vs `git pull`:** a plugin install is pinned to the version you installed; it moves only
>   on `/plugin update`. A bash checkout tracks whatever you `git pull`.
> - **Project hook wiring points at the bash path:** the hook entries adopt just wired into this repo's
>   `settings.json` reference `$HOME/.claude/dwarves-kit/hooks/...`, which only the bash install creates
>   (the plugin compat shim symlinks lib/bin but not hooks/). On this plugin-only machine those per-repo
>   module hook entries will not fire until a bash install also runs. The plugin's own hooks (from
>   `hooks/hooks.json` at `${CLAUDE_PLUGIN_ROOT}`) are unaffected and do fire.
> - **`KIT_FORCE_FULL=1` escape:** `KIT_FORCE_FULL=1 bash install.sh` forces the full bash install even
>   on a plugin machine, but that creates the double-hooks hazard, only do it if you're deliberately
>   switching paths, and remove the plugin first.

## F. Install staleness

Skipped: staleness is a `bash`-mode surface only (there is no INSTALL-STAMP on the plugin path).

## G. The welcome tour

> **Wizard:** You're set up. Here's the loop in five sentences:
> 1. **Specify** , turn an intent into a spec (`/kit:spec`) and a lane, so the work has a written,
>    testable contract before any code.
> 2. **Execute** , the build runs against that spec (`/kit:execute`): worker, then verifier, then a
>    bounded fix retry, the smallest verifiable increment at a time.
> 3. **Observe** , every run leaves an append-only trail that `stats` projects on demand, so you can see
>    what happened without a second source of truth.
> 4. **Govern** , the ship-gate blocks a push whose lane skipped a required gate or a stateful change
>    with no recorded proof, so "done" means proven, not claimed.
> 5. **Learn** , retros and the Learn leg distill each run's lessons back into the backlog, closing the
>    loop so the next cycle starts smarter.
>
> **Next: run `/kit:start`** , it detects where this repo stands and hands you the single right command
> to run first.

---

## Outcome

Detected `plugin`; adopted the repo in exactly one call after an accepted baseline; surfaced the
stats source knobs honestly (optional, skip-safe) instead of calling the module knob-free; disclosed
the four plugin-path gaps honestly, including that the adopt-wired per-repo hook entries point at the
bash-only hook path and will not fire on this machine; ended with the tour. Every write (the single adopt) was previewed by
`--dry-run` and confirmed. No `install.sh`/`adopt.sh`/`bin/config` was modified; the wizard only
orchestrated them.
