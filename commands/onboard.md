---
description: "Guided first-run as six verified exercises: detect the install mode, adopt this repo, wire modules and their knobs, register the board, disclose the plugin-path gaps honestly, and graduate into /kit:start. Every exercise ends with a mechanical check the user can SEE pass; every write is previewed and confirmed; a decline is a no-op."
---

You are running `/kit:onboard`: the kit introducing itself. This is a guided first-run structured as
EXERCISES, not a form: each one does a real piece of setup and ends with a **✓ Passed when** check
whose evidence is command output the user can see, never your assertion. Your job is to ORCHESTRATE
the surfaces that already exist, never to reimplement them (ADR-0034 decision 4): you CALL
`lib/onboard-detect.sh`, `lib/adopt.sh`, and `bin/config`; you never re-detect, re-inject, or
re-parse config yourself.

**Three rules that hold for the whole run:**
- **Every write is previewed then confirmed.** The only thing that writes is `lib/adopt.sh`, always
  after a `--dry-run` preview (or a shown `.kit.toml` plan) and an explicit yes.
- **A decline is a strict no-op.** At any prompt, declining skips the exercise and changes nothing on
  disk. Never punish a decline; the next exercise just continues. Skipping an exercise is not
  failing it.
- **A driven surface's failure never crashes the run.** If any `bash "$KIT/..."` call exits
  non-zero (a missing/corrupt registry, a failed adopt write), print its error, mark that exercise
  "not passed, no partial write", and continue. A failure is reported; a decline is silent. They are
  different.

Run the ✓ check yourself and SHOW its output after each exercise, so the user watches their setup
prove itself step by step. Carry a recommended default on every question so `Enter`-`Enter`-`Enter`
produces a sane setup, and an expert finishes in under two minutes. Keep your prose short and
welcoming.

Resolve the kit root once at the top: `KIT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}"`. Use
`$KIT/lib/...` and `$KIT/bin/...` for every call below. Resolve the current repo once:
`REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.

---

## Exercise 0 · where am I? (install-mode detect)

**Do:** `bash "$KIT/lib/onboard-detect.sh" explain`

It prints one of four modes plus a one-line explanation. Show the user the mode and what it means,
in one or two sentences, then branch:

- **`plugin`** -- "Installed as a Claude Code plugin; the runtime loads from the plugin. The
  bash-only extras (the statusLine HUD, and `install.sh --with` for module selection) aren't wired
  on this path, but I'll bridge the module choice below through `/kit:adopt`." Continue.
- **`bash`** -- "Installed via `bash install.sh`; your `settings.json` registers the kit hooks
  directly." Continue.
- **`both`** -- Disclose the hazard, do NOT try to fix it (that is a settings decision, an
  AGENTS.md Pause-if): "Heads up: BOTH a plugin and a bash install are present, so the kit hooks are
  double-registered and will fire twice. Keep exactly one path. To keep the plugin, remove the
  `dwarves-kit/hooks/*` entries from `~/.claude/settings.json` (or run `bash install.sh --uninstall`).
  To keep the bash install, `/plugin uninstall dwarves-kit@dwarves-marketplace`. I won't change this
  for you." Then continue (the rest still works; the double-fire is a warning, not a blocker).
- **`none`** -- The kit isn't installed on this machine yet. There is nothing to set up in a repo
  until it is. Tell the user the two install paths and STOP:
  - Recommended: `/plugin marketplace add dwarvesf/dwarves-kit` then `/plugin install dwarves-kit@dwarves-marketplace`
  - Alternative: `git clone` the kit and `bash install.sh`
  - "Re-run `/kit:onboard` once one of those finishes." End the run here.

**✓ Passed when:** the detect line is on screen and names a real mode. (`none` ends the run; the
other three pass with their caveats stated.)

**bash mode only, one extra line:** if `~/.claude/dwarves-kit/INSTALL-STAMP` exists, compare its
`sha=` line to the kit checkout's current HEAD. If they differ, print exactly ONE line: "Your bash
install (sha `<short>`) is behind the checkout (`<short>`); re-run `bash install.sh` to refresh.
Details: `/kit:kit-health`." That is the whole staleness surface -- a pointer, never an upgrade
wizard. If the stamp is absent or current, say nothing.

## Exercise 1 · adopt this repo (or prove it already is)

Adoption is what makes an agent classify + pick a lane here and what makes the ship-gate engage
(`docs/consumer-contract.md`).

**Do:** `bash "$KIT/lib/adopt.sh" --check "$REPO"`

- **Already adopted** -- the exercise is already passed; show the evidence instead of redoing it:
  name what's present (`AGENTS.md`, the `CLAUDE.md` loader block, the `WORKFLOW.md` pointer, the
  `docs/verification/README.md` proof marker) and that `.kit.toml` records its module choices.
  **Write nothing, and do NOT call adopt.** To change modules on an already-adopted repo, the honest
  path (a project's own `.kit.toml` is never overwritten, SPEC-192) is: hand-edit the `[modules]`
  section of `<repo>/.kit.toml`, then re-run `/kit:adopt` (or `bash "$KIT/lib/adopt.sh" --refresh
  "$REPO"`) to re-wire `settings.json` to match. Offer the read surface,
  `KIT_PROJECT_ROOT="$REPO" bash "$KIT/bin/config" list` filtered to the `modules.*` rows
  (PROVENANCE shows which values this repo's `.kit.toml` overrides); never edit anything silently.
  Then skip to Exercise 3 (walk Exercise 2 as read-only guidance only if asked).
- **Not adopted** -- Preview first: `bash "$KIT/lib/adopt.sh" --dry-run "$REPO"` and show exactly
  what it would create. Then ask, with **Y as the recommended default**:
  > Adopt this repo now? It creates AGENTS.md + a CLAUDE.md loader + a WORKFLOW pointer + the proof
  > marker (all non-destructive, never overwritten later). [Y/n]
  - **Y** -- do NOT call adopt yet: Exercise 2 picks modules first, then adopt happens there in ONE
    call (the order matters, see below).
  - **decline** -- skip Exercises 1-2 entirely (no-op) and jump to Exercise 3's offer or the tour.
    Note that the ship-gate won't engage until the repo is adopted; re-run `/kit:onboard` (or
    `/kit:adopt`) later.

**✓ Passed when:** either `--check` already reports the contract present, or the user has seen the
dry-run and answered. The write itself is Exercise 2's check.

## Exercise 2 · pick modules, adopt once, and SEE the contract land

Reached only from Exercise 1's "not adopted -> Y". The module roster and its defaults are GENERATED
from the registry, never hardcoded here.

**Do:** `bash "$KIT/bin/config" list`, keeping the rows whose DISPLAY KEY matches `modules.*` (the
module rows; NOT the MODULE column, which also names non-module subsystems like
`config`/`ledger`/`gate`). For each module's one-line purpose,
`bash "$KIT/bin/config" explain modules.<name>` prints it. A module added to the registry later
appears here automatically; do not maintain a second list.

Present the modules compactly (name -- one-line purpose -- default), grouped so the kit-root
`true` ones read as "the recommended baseline." **Recommended default: accept the kit-root
defaults.** `Enter` takes them as-is.

**Then adopt ONCE, seeding the fresh `.kit.toml` with the picks in the same step.** `adopt --with`
seeds modules only on a FRESH `.kit.toml` (a no-op once the file exists, SPEC-192), so: pick first,
then a single call:

```
bash "$KIT/lib/adopt.sh" --with "<comma,separated,chosen>" "$REPO"
```

This injects the contract AND seeds `<repo>/.kit.toml` with those modules `true` AND wires the
enabled hook-bearing modules into `<repo>/.claude/settings.json`, all idempotent and
non-destructive. Never call adopt a second time. If the call exits non-zero, print its error, mark
the exercise not passed (adopt is atomic per file, no partial state), and continue to Exercise 3.

**✓ Passed when:** adopt's own output reports what it created, and you show the evidence on disk:
`ls "$REPO/AGENTS.md" "$REPO/.kit.toml"` both exist, and the `[modules]` section of `.kit.toml`
contains the picks. The user should see file paths, not a summary sentence.

**Honest caveat about `adopt --with`'s reach.** It seeds only the module set adopt itself knows,
currently NARROWER than the registry roster. Derive that set at runtime, never hardcode it:
`grep '^KIT_KNOWN_MODULES=' "$KIT/lib/adopt.sh"` prints adopt's seedable set. Any picked module in
the registry but NOT in that set (e.g. `prose_rag` today) is silently skipped by `--with`, so after
the adopt call, tell the user the one exact line to add by hand to `<repo>/.kit.toml`'s `[modules]`
section (e.g. `prose_rag = true`) and to re-run `/kit:adopt --refresh "$REPO"` -- exactly the
hand-edit path an already-adopted repo uses. If a later adopt fix widens its set, this caveat heals
on its own because both sides are derived, not copied.

**Then the knobs that make the chosen modules non-inert.** Some modules do nothing until a knob is
set (`prose_rag` is dormant without `PROSE_RAG_INJECT=1`; `money_gate` is inert without
`MONEY_GATE_REPOS`). Surface ONLY the knobs for the modules just chosen, generated from the
registry: for each chosen module `M`, keep the `[impl]` rows of `bash "$KIT/bin/config" list` whose
MODULE column equals `M`; `bash "$KIT/bin/config" explain <key>` shows each knob's current value
and provenance. Then:

- **A knob with a `kit.toml` key** (EXPLAIN shows a `project .kit.toml` level, e.g.
  `ledger.location`) -- offer to write the chosen value into `<repo>/.kit.toml`. Preview the exact
  line and confirm before writing; a decline leaves the file untouched.
- **An env-only knob** (EXPLAIN says "this key has no `kit.toml` backing", e.g. `PROSE_RAG_INJECT`,
  `MONEY_GATE_REPOS`, the `STATS_*` sources) -- no `.kit.toml` sink exists, so print the exact
  shell guidance instead (e.g. `export PROSE_RAG_INJECT=1`) and say which shell profile it belongs
  in. Do not try to edit the user's shell config.
- **A `**no-default-consumer**` knob** (the VALUE column shows that marker, e.g. `stats`'s
  `STATS_TIDE_DB` / `STATS_LEARNED_MD` / `STATS_REPOS` source vars) -- OPTIONAL data sources,
  skip-safe by design: unset means "that source's table renders empty", never an error. Present
  them honestly as "optional, safe to leave unset", with the `export` shape for each. Never call a
  module knob-free when it has such rows; "nothing you MUST set" and "nothing to configure" are
  different sentences, use the first.

If the chosen modules genuinely have no `[impl]` knob rows, say so in one line and move on.
Recommended default at each knob: leave it at its current value (skip); the kit-root defaults are a
working baseline.

## Exercise 3 · register the board, and watch a row appear

Adoption wires modules; it does not create the board. If `<repo>/_meta/BACKLOG.md` is missing,
offer this sequence, calling the real surfaces (`bin/board`, the sync installer), never
reimplementing them:

**Do, in order (each step optional, each previewed):**

1. `board init` -- scaffolds `_meta/BACKLOG.md` + the `_meta/board` shim, idempotently.
2. **Team surface, one question**: does this repo's team work in GitHub Issues (or Notion / Hermes /
   Reminders)? If yes, preview the `.kit.toml` addition (`[sync]` + `apps = "github"`, plus
   `github_repo` only when origin is not the right target) and confirm before writing, same
   contract as the Exercise-2 knob writes.
3. `board sync --dry-run`, then live. On a repo that already lived in its tracker, intake creates a
   queued `#inbox` row per open item -- history arrives on the board with no manual backfill. Tell
   the user the `#inbox` tag marks rows awaiting first human triage.
4. **Cadence**: manual `board sync` is the default. If they want it ambient, set
   `[sync] mode = "cron"` and run `bash "$KIT/lib/sync/deploy/macos/install" --repo "$REPO" --apply`
   (the per-repo LaunchAgent; the launcher re-checks `mode` every run, so flipping back to
   "manual" in `.kit.toml` stops it without an uninstall). Mention `board capture "<title>"` as the
   from-a-session filing verb while you are here.

**✓ Passed when:** the user SEES it round-trip -- the dry-run plan matched what the live sync then
did, and `_meta/BACKLOG.md` shows the intaken rows (or, on a repo with no tracker history, `board`
renders the empty board without error). If they enrolled the cron:
`launchctl print gui/$(id -u)/board-sync-<slug>` shows `last exit code = 0` after a kickstart --
exit 0 is the pass, not the install banner.

A repo that declines any step stays fully functional; the board is additive.

## Exercise 4 · know your path's limits (plugin / both modes only)

Not a setup step -- a disclosure with evidence. Be honest about what the plugin path cannot do
(ADR-0009), in four short bullets:

- **statusLine HUD:** the v1 plugin schema has no `statusLine` field, so the status-line HUD is
  bash-install-only. If they want it, that is the one reason to run the bash install.
- **Frozen SHA vs `git pull`:** a plugin install is pinned to the version you installed; it moves
  only on `/plugin update`. A bash checkout tracks whatever you `git pull`.
- **Project hook wiring points at the bash path:** adopt's per-repo `settings.json` wiring copies
  hook commands that reference `$HOME/.claude/dwarves-kit/hooks/...`, a path only the bash install
  creates (the plugin compat shim symlinks lib/bin but NOT hooks/). On a plugin-only machine those
  wired project-level hook entries will not fire until a bash install also runs. The PLUGIN's own
  hooks (registered via `hooks/hooks.json` at `${CLAUDE_PLUGIN_ROOT}`) are unaffected and do fire;
  this gap is specifically the adopt-wired per-repo module entries. Say this at adopt time too, not
  only here: on a plugin machine, never claim the module hooks are live after adopt.
- **`KIT_FORCE_FULL=1` escape:** `KIT_FORCE_FULL=1 bash install.sh` forces the full bash install
  even on a plugin machine, but that is exactly what creates the double-hooks hazard from Exercise
  0 -- only do it if you are deliberately switching paths, and remove the plugin first.

**✓ Passed when:** the four bullets have been shown (plugin/both) or the exercise was skipped in one
line (bash mode: "no gap to disclose").

## Exercise 5 · graduate: the loop in five sentences, then the first real command

Close with the five-stage loop, one sentence per stage -- and tie each stage to what the exercises
just wired, so the tour describes THEIR setup, not an abstraction:

1. **Shape** -- you turn an intent into a spec (`/kit:spec`) and a lane, so the work has a written,
   testable contract before any code (the contract Exercise 2 installed is what makes lanes bind
   here).
2. **Build** -- the build runs against that spec (`/kit:execute`), worker then verifier then a
   bounded fix retry, the smallest verifiable increment at a time.
3. **Watch** -- every run leaves an append-only trail that `stats` projects on demand, so you can
   see what actually happened without a second source of truth.
4. **Check** -- the ship-gate blocks a push whose lane skipped a required gate or a stateful change
   with no recorded proof (armed by the proof marker from Exercise 2), so "done" means proven, not
   claimed.
5. **Learn** -- retros and the Learn stage distill each run's lessons back into the backlog
   (Exercise 3's board, if you registered it), closing the loop so the next cycle starts smarter.

**Do:** end with **"Next: run `/kit:start` -- it detects where this repo stands and hands you the
single right command to run first."**

**✓ Passed when:** `/kit:start` is the last thing on screen. Onboarding's exit is the first real
command of the loop, not a summary.

## Do NOT

- Reimplement detection, injection, or config parsing (call the three surfaces above; ADR-0034 fence).
- Change `install.sh` or `adopt.sh`, or add a flag to `bin/config`. onboard is a consumer of them.
- Write anything without a preview + an explicit yes. A decline changes nothing.
- Auto-fix the `both` double-hooks hazard, or edit the user's shell profile. Disclose and point.
- Turn INSTALL-STAMP staleness into a flow. It is one line and a `/kit:kit-health` pointer.
- Claim an exercise passed without showing the check's output. The evidence is the command output
  the user can see, never your summary of it.
