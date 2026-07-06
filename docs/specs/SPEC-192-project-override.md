# SPEC-192: project-override (per-project `.kit.toml` closed end to end through adopt)

Status: SHIPPED (test + run-table confirmed)
Lane: full
Backlog: harness-ops sub-goal 06 (`_meta/megagoals/harness-ops/goals/06-project-override.md`)
Branch: feat/harness-ops-06-override
Relates-to: SPEC-183 (manifest-reconcile, the `kit.toml` chain), SPEC-188 (reserved-keys
guard, the resolver's read side), `lib/config/kit-config.sh` (the resolver, sub-goal 01),
`lib/adopt.sh` / `commands/adopt.md` (sub-goal 05's `/kit:adopt`)

## Problem

The resolver (`lib/config/kit-config.sh`, sub-goal 01) already merges a per-project
`<project>/.kit.toml` over the kit-root default (project keys win). But nothing closed
the loop for the two things a project actually needs to DO with that: (1) get a starter
`.kit.toml` without hand-authoring one from the full kit-root schema, and (2) have its
per-project `[modules]` choice actually change what is wired -- specifically, a
hook-bearing module (`board`, `session`, `advisor`, `cosmetic`) needs its hook present or
absent in `<project>/.claude/settings.json`, not just readable via `kit_config_get`.
Without this, `[modules] board=false` in a project's `.kit.toml` was a value the
resolver could report, but board's hook (`backlog-stage.sh`) still fired in that
project, because nothing ever translated the config into a settings.json entry.

## Design

**Obvious, reuses existing pieces; no new resolver, no new module registry.**

- **Seed, don't invent.** `lib/adopt.sh` gains a `--with <a,b,c>` flag and, on a run
  where `<project>/.kit.toml` does not yet exist, writes a starter `[modules]` section
  listing every known module (`board session advisor cosmetic queue stats quiz_gate
  weekend_batch bridge`), each defaulting to the current kit-root value unless named in
  `--with`. Never overwritten once it exists (same invariant as `AGENTS.md` / the proof
  marker) -- `--with` on an existing `.kit.toml` is a no-op with a note, not a clobber.
- **Read via the resolver, not a re-implementation.** Enabled-state for each hook-bearing
  module is `kit_config_get "modules.<m>"` with `KIT_PROJECT_ROOT=<project>`
  `KIT_CONFIG_ROOT=<kit-root dir>` -- the exact precedence sub-goal 01 already built
  (project override, else kit-root default). `lib/adopt.sh` sources
  `lib/config/kit-config.sh` inside a function scope (so the resolver's own `${1:-}`
  selftest branch never sees `adopt.sh`'s positional parameters).
- **Wire via a jq MERGE, never a settings.json rewrite.** `kit_module_hooks()` is a small,
  deliberately duplicated copy of `install.sh`'s module->hook-script map (can't source a
  full script as a library; same duplication `tests/test-install-modules.sh` already
  accepts for the same reason). For each currently-enabled hook-bearing module, its hook
  script names are pulled from the kit's own `settings.json` (source of the real hook
  definitions: matcher, timeout, command) and merged into
  `<project>/.claude/settings.json`: any prior `dwarves-kit/hooks/*` entry is stripped
  first, then the currently-enabled set is re-added. Every non-kit-module entry in the
  project's settings.json is preserved untouched (the Scope's "Not: a settings.json
  rewrite" -- this is a targeted merge, not a full-file replace).
- **Wired at adopt time, not read per hook fire.** The wiring step runs on every
  `lib/adopt.sh` invocation (fresh or `--refresh`) -- an explicit, deliberate action --
  recomputing the project's wired set from its CURRENT `.kit.toml`. No hook reads
  `.kit.toml` or `kit.toml` at runtime (this repo's standing anti-drift lint,
  `tests/test-install-modules.sh`, already asserts that for the global install; this
  sub-goal adds no new runtime reader).
- **Deterministic output, not just "the same hook names, any order".** The jq merge
  canonicalizes with `jq -S` and sorts each event's hook-array by its own JSON text, so
  re-running adopt with an unchanged `.kit.toml` reproduces byte-identical
  `settings.json` -- `tests/test-adopt.sh`'s existing idempotency invariant (a clean
  `git diff` after a no-op re-run) held for the pre-existing four artifacts and now
  holds for the two new ones too.

## Scope edges

**In:** `.kit.toml` end-to-end (seed + read via the resolver), `/kit:adopt`'s
`lib/adopt.sh` seeding a starter + wiring enabled hook-modules into the project's
`settings.json`.
**Out:** the resolver merge itself (sub-goal 01, unchanged here), the global
`install.sh` install (sub-goal 04, unchanged here -- this sub-goal never touches
`install.sh`).
**Not:** runtime per-call module toggling (the hybrid model is wired at adopt time, read
once per explicit adopt run, never per hook fire), a wholesale settings.json rewrite (a
targeted jq merge only ever touches `dwarves-kit/hooks/*` entries).

## Verification

1. `bash tests/test-adopt.sh` -- 21 assertions, all green, including 10 new SPEC-192
   assertions: starter `.kit.toml` seeding, `--with` on a fresh vs. an existing project,
   the `board=false` -> hook-not-wired proof, a `[ledger]` override honored by the
   resolver, and idempotent re-wiring.
2. `bash tests/test-install-modules.sh` -- unchanged, still green (regression check;
   this sub-goal never edits `install.sh`).
3. `bash lib/config/kit-config.sh selftest` -- unchanged resolver mechanics, still green.

## After state

- `lib/adopt.sh` seeds `<project>/.kit.toml` (opt-in, `--with`-aware, never overwritten
  after creation) and wires the currently-enabled hook-bearing modules'
  (`board`/`session`/`advisor`/`cosmetic`) hooks into `<project>/.claude/settings.json`
  on every adopt run, via a targeted jq merge.
- The Done= run-table (project override + module-enable): a project `.kit.toml`
  `[modules] board=false` -> `backlog-stage.sh` absent from that project's
  `settings.json`, while an untouched still-enabled module's hooks stay wired; a
  `[ledger] location = "isolated"` override in the project `.kit.toml` resolves via
  `kit_config_get ledger.location` to `"isolated"`.
- Proof: `docs/verification/project-override/proof-of-done.md`.
