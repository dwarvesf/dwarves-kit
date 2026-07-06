# Decision Brief: kit.toml config layer (runtime config + per-project override)

Status: DRAFT (feeds /kit:spec). Owner: Han. Drafted 2026-07-06.

## Problem

The kit's runtime knobs are scattered environment variables (`KIT_LEDGER_DIR`,
`WAVE_CAP`, `TIER4_CLOSE`, `MULTIPLEXER`, `MEGA_MERGE_POSTURE`,
`KIT_DELIVERY_RATIO_WARN`, ...), each resolved by an ad-hoc precedence helper.
There is no single declarative config surface. As the kit is adopted into MANY
projects and machines (and, later, non-Claude-Code harnesses), the operator needs
one place to say: which modules are on, where the harness stores its operation
record, how mega-goals scaffold, which features are enabled, and (reserved) the
team-collaboration posture , with a kit-wide default that a project can override.

## Verified current state

- A `kit.toml` ALREADY exists but is a **write-only install manifest** at
  `~/.claude/dwarves-kit/kit.toml` (`install.sh` writes `<module> = true|false`).
  A lint (the "no hooks/*.sh reads kit.toml" assertion in `tests/test-install-modules.sh`)
  FAILS if any **hook** reads it at runtime. It forbids hook reads, not command reads.
- Every real runtime knob is an **env var**. The ONLY resolver precedent is
  `lib/telemetry/kit-log-dir.sh` (`kit_resolve_log_dir`, env-precedence, fatal-on-empty),
  plus `lib/mega.sh`'s `_resolve_*` helpers. There is **no** `lib/config/` and **no**
  `kit_config` reader.
- Consumers today reach into `$DWARVES_KIT/lib/...` DEEP paths (e.g. ops-toolkit's
  `_meta/board` shim exec'd `lib/board.sh`). The kit lib-regroup moved that to
  `lib/board/board.sh` with no flat compat shim, silently breaking the consumer
  (fixed pointwise 2026-07-06; the class of bug motivates a stable interface below).
- The adopt contract is 4 files (`AGENTS.md` copy, `CLAUDE.md` kit-block, `WORKFLOW.md`
  pointer, `docs/verification/README.md` marker). `boards.txt`/`BACKLOG.md`/`OPERATE.md`
  are consumer-authored data, NOT adopt artifacts.

## Verdict: BUILD , a runtime config resolver + a forward-looking kit.toml, WITHOUT reversing the hook lint

The hook lint stays. The resolver is read by COMMANDS and feature libs at invocation,
never by the hot spine hooks. That is compatible with the lint as written and preserves
its performance rationale (no TOML parse on every Bash call).

## Design (decisions locked over the 2026-07-05..06 design pass)

1. **One resolver, central mechanics.** `lib/config/kit-config.sh` owns load + merge +
   precedence (mirrors `kit-log-dir.sh`, "one place the default lives"). Exposes
   `kit_config_get <section.key>`. Policy (what to DO with a value) stays per-tool.
2. **Two levels, project wins.** kit-root `kit.toml` = default; `<project>/.kit.toml` =
   override. A project writes only the keys it changes; the rest inherit.
3. **Hybrid read timing.** Commands/feature libs read at invocation (mega scaffold reads
   `[mega]`, ledger init reads `[ledger]`, a feature reads `[features]`). Spine hooks
   never read config. Ledger location keeps flowing through `KIT_LEDGER_DIR` (the resolver
   exports it), so the append substrate stays env-driven and fatal-on-empty.
4. **TOML** (kit already uses it; bash-parseable; no YAML parser dependency).
5. **Comprehensive, status-tagged schema** (Han, 2026-07-06): the config is the SINGLE
   forward-looking control surface, so it carries reserved / designed / consumer-side keys
   too, each STATUS-TAGGED (`[impl] [design] [reserved] [consumer]`) so an inert key is
   documented, never a silent surprise. Full template: `kit.toml.example` at repo root.
6. **default_model / over_test are GLOBAL fallbacks, kept deliberately.** The real controls
   are per-sub-goal goal-file fields (`Model:`, `Done-mode:`). Han keeps global keys so an
   adopter on a DIFFERENT harness/model (not Claude Code) has one default to set. Precedence:
   goal-file field > project `.kit.toml` > kit-root default.

## Explicitly NOT built (boundary)

- The hook lint is NOT reversed; hooks stay config-free.
- No per-stream ledger enable/disable, no retention/rotation (append-only stays; `retention`
  is a reserved placeholder only).
- The team section is reserved (all `false`); `team_mode` stays install-rejected until the
  team-mode mega ships.
- `auto_improvement` stays inert (design-doc only); `learning_ledger` toggle is honored by
  the external consumer skill, not by a new kit code path.

## Open questions for the spec

1. **Manifest reconciliation.** Three artifacts touch config: repo-root `kit.toml` (shipped
   default), install-generated `~/.claude/dwarves-kit/kit.toml` (module manifest), project
   `.kit.toml` (override). Proposed: repo-root ships the default; `install.sh` renders the
   live install config from it + `--with` flags; resolver reads live-install ← project.
   The spec must pin this so the manifest and the runtime config are ONE coherent chain.
2. **Stable consumer interface.** Consumers must stop reaching `$DWARVES_KIT/lib/...` deep
   paths. Expose a stable entrypoint (a `kit <sub> <verb>` dispatcher or installed `board`
   command) so internal reorg never breaks a consumer again. In scope for this spec or a
   tight sibling; it is the durable fix for the board-shim class of bug.
3. **Lint scope confirmation.** Confirm the kit.toml-read lint in `tests/test-install-modules.sh` is hook-scoped;
   if it forbids ALL runtime reads, either scope it to hooks or point the resolver at a
   separate runtime-config file.
4. **Consumer-contract doc.** Produce `docs/consumer-contract.md` (the 4 adopt files +
   `KIT_LEDGER_DIR` + optional `.kit.toml`) so onboarding a new project/machine is one page.

## Exit criteria (negative controls first)

- A command reading `kit_config_get mega.wave_cap` returns the kit default; a project
  `.kit.toml` setting it returns the OVERRIDE; an unset key returns the documented default.
- NC: a spine hook that tries to read the config fails the lint (proves hooks stay out).
- NC: `location = "isolated"` writes the ledger under the project, `"shared"` under XDG;
  a set-but-empty `KIT_LEDGER_DIR` still errors cleanly.
- Every `[impl]`-tagged key demonstrably changes behavior; every non-`[impl]` key is inert
  and documented as such.

## Sequencing

1. `lib/config/kit-config.sh` resolver + tests (the mechanics).
2. Ship `kit.toml.example` -> resolved default; wire `[ledger]` + `[mega]` `[impl]` keys
   through the resolver (env-var back-compat preserved).
3. Stable consumer interface (dispatcher / installed command) + repoint the adopt contract.
4. `docs/consumer-contract.md`.
5. Team + features keys stay reserved until their owning work lands.
