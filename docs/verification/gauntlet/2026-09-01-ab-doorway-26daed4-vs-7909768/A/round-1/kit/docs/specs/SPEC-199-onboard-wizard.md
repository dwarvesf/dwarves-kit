# SPEC-199: onboard-wizard (`/kit:onboard` guided first-run)

Status: VALIDATED
Lane: full
Backlog: harness-loop sub-goal 09 (`_meta/megagoals/harness-loop/goals/09-onboard-wizard.md`)
Branch: feat/loop-09-onboard-wizard (stacked on `feat/loop-08-config-surface`, PR base
`feat/loop-08-config-surface`)
Relates-to: ADR-0034 (`docs/decisions/0034-harness-loop-taxonomy.md`, decision 4: the four
front-door verb fences), ADR-0009 (`docs/decisions/0009-plugin-packaging-dual-ship.md`: the
dual-ship truths the copy must state honestly), SPEC-198 (`bin/config` read surface + the
`lib/config/module-registry.md` registry the knob list is generated from), SPEC-192 (the per-repo
`.kit.toml` override + `adopt --with` seeding onboard drives), SPEC-066 (the INSTALL-STAMP
staleness probe kit-health owns), `docs/consumer-contract.md` (what "adopted" means),
`commands/start.md` + `lib/adopt.sh` + `install.sh:315-353` (the detection primitives onboard
orchestrates but never reimplements)

## Problem

A first-time consumer of the kit faces a cold start with no guided path. Four separate facts have
to line up before the loop works, and today each is a manual, undocumented step:

1. **Which install mode is live** (plugin / bash / both / none). The bash and plugin paths differ
   (ADR-0009), and running BOTH double-registers every hook so they fire twice, a silent hazard
   the README only warns about in prose.
2. **Whether the current repo is adopted** (`AGENTS.md` + the proof marker + the CLAUDE.md loader).
   An un-adopted repo never engages the ship-gate; the operator has to know to run `/kit:adopt`.
3. **Which modules are on**, and, on the plugin path, there is no `install.sh --with` step at all,
   so per-repo module selection has no obvious front door.
4. **Which consumer knobs make a chosen module non-inert** (e.g. `prose_rag` is dormant without
   `PROSE_RAG_INJECT=1`; `money_gate` is inert without `MONEY_GATE_REPOS`). These ~70 env vars are
   now inventoried in the SPEC-198 registry but nothing walks a newcomer through the handful that
   matter for the modules they just picked.

The plugin path additionally cannot do some things the bash path can (statusLine HUD, a
`git pull`-tracking checkout), and an honest first-run has to say so rather than let the user
discover the gap later.

There is no interactive first-run orchestrator that ties these four together, previews every
write, and ends by pointing at the loop. That is `/kit:onboard`.

## Design

**Fence (ADR-0034 decision 4).** `/kit:onboard` is the interactive first-run ORCHESTRATOR. It
CALLS the fenced surfaces and never reimplements their jobs:

| It needs to | It calls (never reimplements) |
|---|---|
| Detect repo/project state | `commands/start.md`'s detector posture + `lib/onboard-detect.sh` for install-mode |
| Inject the operate-contract | `lib/adopt.sh` (the mechanical injector; `--dry-run` to preview, `--with` to seed modules) |
| Read/explain a knob | `bin/config list` / `bin/config explain` (the SPEC-198 read surface; the ONLY TOML reader stays `lib/config/kit-config.sh`) |

onboard writes NOTHING of its own except by driving `lib/adopt.sh`; every such write is previewed
(`--dry-run` / a shown `.kit.toml` diff) and confirmed, and a decline is a strict no-op.

**The one new mechanical primitive: `lib/onboard-detect.sh`.** A read-only install-mode detector,
the single piece of onboard that is deterministic enough to test as bash rather than prove by
transcript. It inspects install state under `$CLAUDE_DIR` (env-overridable for fixtures, same seam
`install.sh` uses) and emits one mode word + a one-line explanation:

- `plugin` : a plugin cache lib dir exists (`$CLAUDE_DIR/plugins/cache/dwarves-marketplace/kit/*/lib`,
  the exact glob `install.sh:328` uses), OR `installed_plugins.json` names the kit; AND no
  dwarves-kit hook is registered in `$CLAUDE_DIR/settings.json`.
- `bash` : `$CLAUDE_DIR/settings.json` registers >=1 `dwarves-kit/hooks/*.sh` command (the full
  bash install; the plugin compat-symlink deliberately does NOT add these, `install.sh:331`); AND
  no plugin cache.
- `both` : both signals present. Hooks are DOUBLE-registered and fire twice. The hazard case.
- `none` : neither. The kit is not installed on this machine yet.

The detector re-encodes install.sh's two signals (the cache glob + the `dwarves-kit/hooks/` grep)
rather than sharing a symbol, because install.sh is a standalone bootstrap script with no library
it could import from. To keep the two copies from drifting silently, a test (AC8) pins that
install.sh still carries both signal strings; a marketplace/path rename that touches one and not the
other fails CI.

**The flow (state diagram).** Each state carries a recommended default so `Enter`-`Enter`-`Enter`
produces a sane setup; a decline at any prompt skips forward with no write.

```
                         /kit:onboard
                              |
                              v
                  +-----------------------+
                  | A. DETECT INSTALL MODE|   lib/onboard-detect.sh explain
                  +-----------------------+
                    |        |        |        \
              plugin|    bash|    both|         \none
                    |        |        |          \
                    |        |        v           v
                    |        |   [disclose double- [not installed:
                    |        |    hooks hazard,     print /plugin +
                    |        |    point to the      bash install.sh
                    |        |    one-path fix;     paths, STOP --
                    |        |    NO auto-fix]      nothing to set up
                    |        |        |             yet]
                    +--------+--------+
                              |  (plugin | bash | both continue)
                              v
                  +-----------------------+
                  | B. ADOPT THIS REPO    |   adopt.sh --check <repo>
                  +-----------------------+
                    |                   |
              adopted             not adopted
                    |                   |
                    v                   v
             [report healthy;     [preview: adopt.sh --dry-run;
              .kit.toml exists;    ask "Adopt now? [Y/n]"]
              module changes =       |            |
              edit [modules] +   Y (default)   decline
              /kit:adopt              |            |
              --refresh path;         v            v
              NO write here]     [go to C:      [skip adopt;
                    |             pick modules   no write;
                    |             FIRST]          jump to G]
                    |                |
                    |                v
                    |     +-----------------------+
                    |     | C. MODULE SELECTION   |  roster from `config list`
                    |     +-----------------------+  rows whose KEY = modules.*,
                    |       | (per module: purpose + never a hardcoded list
                    |       |  kit-root default; Enter = default)
                    |       v
                    |     [ONE call: adopt.sh --with <chosen> <repo>
                    |      -- seeds the FRESH .kit.toml + wires settings.json
                    |      in a single idempotent step. adopt is invoked
                    |      exactly ONCE for a not-adopted repo, here, never
                    |      again in B. If adopt exits non-zero, print its
                    |      error and stop this step with no partial state.]
                    |                |
                    +----------------+
                              |
                              v
                  +-----------------------+
                  | D. CONSUMER KNOBS     |   for chosen modules only:
                  +-----------------------+   filter `config list` by MODULE
                    | (each knob: current value via `config explain`;
                    |  a kit.toml-keyed knob -> offer to write .kit.toml
                    |  (previewed+confirmed); an env-only knob -> print
                    |  the exact `export ...` guidance. Decline = skip)
                    v
                  +-----------------------+
                  | E. PLUGIN-PATH GAPS   |   only if mode in {plugin, both}
                  +-----------------------+   (ADR-0009 honest disclosure)
                    | (statusLine HUD unavailable; frozen SHA vs git-pull;
                    |  KIT_FORCE_FULL=1 escape + its double-hook caveat)
                    v
                  +-----------------------+
                  | F. STALENESS (1 line) |   bash mode only: INSTALL-STAMP sha
                  +-----------------------+   vs HEAD; if stale, ONE line +
                    |                         "-> /kit:kit-health". Not a flow.
                    v
                  +-----------------------+
                  | G. WELCOME TOUR       |   the five-leg loop in five
                  +-----------------------+   sentences + "Next: /kit:start"
                              |
                              v
                            (end)
```

**Adopt is invoked exactly once for a not-adopted repo (state B -> C).** `adopt --with` only seeds
`.kit.toml` when the file is absent (`lib/adopt.sh` ignores `--with` once `.kit.toml` exists,
SPEC-192). So the sequence is pinned: for a not-adopted repo, onboard collects the module selection
FIRST (state C), then issues ONE `adopt --with <chosen> <repo>` call, which both injects the
contract and seeds the fresh `.kit.toml` with the picks in a single step. adopt is never called a
second time in state B. The "existing `.kit.toml` -> edit `[modules]` + `/kit:adopt --refresh`" path
belongs to the ALREADY-ADOPTED branch only (state B "adopted", scenario c): a project's own config
is never overwritten, so there is no `--with` re-seed for an adopted repo.

**Module list generation (state C).** The module roster is read from the registry via
`bin/config list`, keeping the rows whose DISPLAY KEY matches `modules.*` (the 12 module rows;
NOT the MODULE column, which also names non-module subsystems like `config`/`ledger`/`gate`). Each
module's purpose + kit-root default come from those registry rows, presented as what `bin/config`
actually emits (KEY / VALUE / MODULE + the explain Doc line; the leg column lives in the registry's
Module-legs table, which `bin/config` does not read, so the wizard does not promise it). There is
NO second
hardcoded module list in onboard: a module added to `KIT_KNOWN_MODULES` and the registry appears in
the wizard with zero onboard edits.

**Failure degradation (every driven surface).** onboard never crashes on a driven surface's
non-zero exit. If `bin/config list`/`explain` fails (e.g. a missing/corrupt registry), onboard
prints the surface's own error and skips that read step, continuing the tour. If an `adopt` write
fails, onboard prints the error and stops that write step with no partial state (adopt itself is
atomic per-file), never leaving a half-written repo; the user can re-run. A decline is distinct from
a failure: a decline is an intentional no-op, a failure is reported.

**Consumer-knob generation (state D).** For each chosen module, onboard runs `bin/config list` and
keeps the `[impl]` env-var rows whose MODULE column equals that module, then explains each with
`bin/config explain <key>` (current value + 4-level provenance). A knob with a `kit.toml` key
(e.g. `ledger.location`) can be written into `.kit.toml` (previewed + confirmed); an env-only knob
(e.g. `PROSE_RAG_INJECT`, `MONEY_GATE_REPOS`) yields printed `export` guidance, since there is no
`.kit.toml` sink for it. The list is entirely derived from the registry; onboard hardcodes no knob
names.

**Every write previewed + confirmed; decline = no-op.** The only writer onboard drives is
`lib/adopt.sh`, always preceded by `--dry-run` (fresh repo) or a shown `.kit.toml`/`settings.json`
plan (an existing one), and only run after an explicit `Y`. On the already-adopted repo (state B
"adopted" branch) onboard reports health and exits having written nothing. A decline anywhere
leaves the tree byte-identical (the decline-NC in Verification proves this).

## Scope edges

**In:** `commands/onboard.md` (the interactive orchestrator), `lib/onboard-detect.sh` (the tested
detection primitive), one `docs/MANUAL.md` command-reference section, the count/inventory syncs one
new command file forces (README Commands table, architecture.md inventory row, WORKFLOW emit-coverage
exemption row, the `test-command-emit-sweep.sh` pins).

**Out:** any `install.sh` change (it stays non-interactive by ADR-0034 decision 4 / ADR-0009), any
`lib/adopt.sh` change, any `bin/config` change (no new `--status`/`--module` flag; onboard filters
its output), any new module.

**Not:** an update/upgrade wizard (INSTALL-STAMP staleness is ONE printed line + a `/kit:kit-health`
pointer, never a flow), telemetry/analytics of wizard answers, a TUI framework, auto-fixing the
double-hooks hazard (disclosed + pointed at, never mutated: that is a settings decision, an
AGENTS.md Pause-if).

## Verification

1. `bash tests/test-onboard-detect.sh` -- the detection primitive across all four modes via fixture
   `$CLAUDE_DIR`s: (AC1) a plugin-cache-only fixture -> `plugin`; (AC2) a settings.json-with-kit-hooks
   fixture -> `bash`; (AC3) both signals -> `both`; (AC4) neither -> `none`; (AC5) `explain` prints
   the mode word + a non-empty one-line explanation for each; (AC6) NEGATIVE CONTROL: a fixture with
   an unrelated third-party hook in settings.json (no `dwarves-kit/hooks/`) is NOT misread as `bash`;
   (AC7) read-only: the helper writes nothing under `$CLAUDE_DIR` (tree hash unchanged after a run);
   (AC8) DRIFT PIN: `install.sh` still carries BOTH detection signal strings the helper mirrors (the
   `plugins/cache/dwarves-marketplace/kit/*/lib` glob and the `dwarves-kit/hooks/` grep), so the two
   copies cannot silently diverge after a marketplace/path rename; (AC9) NO HARDCODED ROSTER:
   `commands/onboard.md` drives `bin/config list` for the module roster and does not hardcode a list
   of `KIT_KNOWN_MODULES` names (proves the "zero onboard edits when a module is added" invariant by
   test, not just advisor eyeball).
2. Three recorded walkthrough transcripts, committed under `docs/proof/loop-09-onboard-wizard/`:
   (a) fresh plugin-only machine (temp HOME + fixture repo), (b) bash-install machine with an
   unadopted repo (temp HOME + fixture repo), (c) already-adopted repo (this repo) -> wizard reports
   healthy and exits without writing.
3. Decline-NC: scenario (b) declining every prompt; `git status --porcelain` + tree hash of the
   fixture repo before and after are byte-identical, captured.
4. Rung 3: a fresh-context `kit:recheck-verifier` RE-EXECUTES scenario (b) live and records PASS
   (the interactive transcript is this mega's most fake-able artifact; ADR-0034/kit-foldin precedent
   assigns rung 3 to interactive surfaces).
5. `kit:advisor` critique (P5 mode: misleading copy, fence violations) on the transcripts; CRITICAL/
   MAJOR findings applied, pass recorded.
6. Regression: `bash tests/test-meta.sh`, `bash tests/test-hooks.sh`,
   `bash tests/test-command-emit-sweep.sh`, `bash tests/test-outcome-emit-sweep.sh` all green (the
   count/inventory syncs land without breaking any pin).

## After state

- `/kit:onboard` is live: a guided first-run that detects install mode, offers `/kit:adopt` for the
  cwd repo, walks module selection (bridging the plugin path's missing `--with` via `adopt --with`),
  captures consumer knobs into `.kit.toml` + printed env guidance (generated from the SPEC-198
  registry), discloses the plugin-path gaps honestly (statusLine, frozen SHA, `KIT_FORCE_FULL`), and
  ends with the five-leg tour + `/kit:start`. Every write is previewed and confirmed; decline is a
  no-op.
- `lib/onboard-detect.sh` is a read-only, fixture-tested install-mode detector reusing the exact
  detection signals of `install.sh:315-353`.
- start / adopt / config keep their fenced jobs unchanged (ADR-0034 decision 4); onboard reimplements
  none of them.
- The command/inventory surfaces (README, architecture.md, WORKFLOW emit-coverage, the emit-sweep
  test) count `onboard` as the 31st command / 10th exempt utility, with no test weakened.
- Proof: `docs/verification/loop-09-onboard-wizard.md` + `docs/proof/loop-09-onboard-wizard/`.

## Decision log

- 2026-07-12 DRAFT -> VALIDATED after `/kit:spec-validate` (6 lenses, fresh context). Reviewer 6
  (design-record, BLOCKING) PASSED (design-bearing, non-empty Design block with the state diagram +
  chosen approach). Verdict NEEDS REVISION was driven by one advisory Critical + 4 warnings, all
  applied before the flip:
  - **Critical (R3/R4/R5): adopt-sequencing.** `adopt --with` seeds `.kit.toml` only when absent
    (SPEC-192), so the diagram's two adopt calls (state B and state C) would drop the user's picks.
    Fixed: pinned ONE adopt call for a not-adopted repo, driven from state C after module selection;
    scoped the "existing `.kit.toml` -> edit + `--refresh`" path to the already-adopted branch only.
    Redrew the diagram and the state-B/C command copy.
  - **W1 (R2): failure degradation.** Added the rule that a driven surface's non-zero exit is
    printed + the step skipped (no partial write), never a wizard crash; distinct from a decline.
  - **W2 (R5): detection duplication.** install.sh is a standalone bootstrap with no importable lib,
    so the two signal copies are kept honest by AC8 (a drift pin asserting install.sh still carries
    both signal strings).
  - **W3 (R4/R5): roster phrasing.** Changed "config list MODULE col" to "rows whose DISPLAY KEY
    matches `modules.*`" in the diagram + text (the MODULE column also names non-module subsystems).
  - **W4 (R4): no-hardcoded-roster verification.** Added AC9 (a test asserting `commands/onboard.md`
    drives `bin/config list` and hardcodes no `KIT_KNOWN_MODULES` roster), so the zero-edit
    extensibility invariant is test-backed, not just advisor eyeball.
- 2026-07-12 post-build review round (rung-3 recheck + advisor P5 + security/architecture lenses),
  all findings applied:
  - **Recheck round 1 FAIL (real catch): AC9 red.** A late "honest caveat" edit to
    `commands/onboard.md` hardcoded module names, tripping AC9 and contradicting transcript (b)'s
    "never a hardcoded list" claim. Fixed: the caveat now derives adopt's seedable set at runtime
    (`grep '^KIT_KNOWN_MODULES=' lib/adopt.sh`), so it self-heals when adopt's set widens. Recheck
    round 2: PASS (both harnesses re-executed fresh).
  - **Architecture CRITICAL: the leg promise.** State C promised each module's "owning leg", but
    `bin/config list|explain` does not emit the leg column (it lives in the registry's Module-legs
    table, which config.sh does not read). Fixed by dropping the leg from the wizard's presentation
    (option a); promising it would have forced fabrication or a fence bypass.
  - **Architecture MEDIUM/MINOR:** the already-adopted branch now names its exact read command
    (`KIT_PROJECT_ROOT=... bin/config list` filtered to `modules.*`); onboard-detect help no longer
    leaks `set -euo pipefail` into its own output (sed range 2,29).
  - **Advisor CRITICAL: dead hook paths on plugin machines.** adopt's per-repo `settings.json`
    wiring copies hook commands referencing `$HOME/.claude/dwarves-kit/hooks/...`, which only the
    bash install creates, so on a plugin-only machine the adopt-wired per-repo module hooks never
    fire. Within this sub-goal's fence (no adopt.sh changes) the fix is disclosure: section E gained
    a fourth bullet, the adopt success copy on plugin machines no longer claims live hooks, and
    transcript (a) was re-cut to match. The real path-templating fix is an adopt.sh follow-up for
    the lead (same class as the KIT_KNOWN_MODULES staleness note).
  - **Advisor MAJOR: false "no must-set knob" claim for stats.** `stats` carries four
    `**no-default-consumer**` source vars; section D now defines that knob class (optional,
    skip-safe, present with export shapes, never "knob-free"), and transcript (a)'s D section was
    re-cut to walk them honestly.
  - **Security lens: SHIP** (0 critical/major; detector's read-only contract verified line-by-line
    and by AC7; one pre-existing repo-wide MINOR noted: unguarded `mktemp` convention, left for a
    suite-wide pass).
