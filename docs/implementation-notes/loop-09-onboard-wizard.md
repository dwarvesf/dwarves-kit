# Implementation notes: loop-09 onboard-wizard (SPEC-199)

Delta from the spec/ADR only (per the impl-notes rule: reference decisions, do not restate them).

## 2026-07-12 Detection helper location: `lib/onboard-detect.sh`, not `lib/onboard/`

Context: the goal allows "possibly a small lib/ helper for detection."
Decision: a single top-level orphan script `lib/onboard-detect.sh`, not a `lib/onboard/` subsystem dir.
Why: there is exactly one helper and it is command-invoked, not an operator CLI. This matches the
existing single-purpose orphans at `lib/` root (`adopt.sh`, `explain.sh`, `pitch.sh`,
`precedent.sh`), which the AGENTS.md "How the kit composes" note names as the pattern for
command-helper bash that is not a multi-verb subsystem. A `lib/onboard/` dir would imply a
subsystem with a `bin/onboard` entry, which ADR-0034 decision 4 does NOT create (onboard is a
command surface, not a bin subsystem).

## 2026-07-12 The `--with` bridge is adopt-seeded `.kit.toml`, not an install.sh change

Context: goal says "bridging the plugin path's missing `--with`, writing the choices via the
existing install/adopt mechanics." The plugin path has no `bash install.sh --with` step.
Decision: onboard bridges it by driving `lib/adopt.sh --with <chosen> <repo>` (which seeds the
per-repo `.kit.toml [modules]` on a fresh adopt) rather than touching install.sh.
Why: `lib/adopt.sh` is reachable on BOTH install paths (`${CLAUDE_PLUGIN_ROOT:-...}/lib/adopt.sh`),
so per-repo module selection through adopt's `.kit.toml` seeding works identically on a plugin
machine and a bash machine. This holds the ADR-0034 decision-4 fence (onboard CALLS adopt, never
reimplements injection) and the scope-edge "no install.sh changes." An already-adopted repo whose
`.kit.toml` exists is never overwritten (SPEC-192 invariant); onboard shows the edit-then-`--refresh`
path instead of forcing `--with`.

## 2026-07-12 Consumer-knob list is filtered `bin/config list` output, not a new flag

Context: goal says the knob list is "GENERATED from SG-08's registry (e.g. `bin/config list
--status consumer` filtered to the chosen modules), never a second hardcoded list."
Decision: onboard runs `bin/config list` and filters its rows by the MODULE column against the
chosen module set (and by STATUS `[impl]` for live knobs). It does NOT add a `--status`/`--module`
flag to `bin/config`.
Why: `bin/config list` (SPEC-198) takes no filter flags; adding one is an SG-08 change, out of this
sub-goal's scope. Filtering the read surface's output is the correct consumer posture (ADR-0034
decision 4: config is the read/explain surface; onboard is a consumer of it). The `--status
consumer` phrasing in the goal is an "e.g." for the intent (surface only the knobs that gate a
chosen module's effect); the registry has few literal `[consumer]`-tagged rows, so the real filter
is MODULE-column membership among the chosen set, which is exactly "generated from the registry."

## 2026-07-12 Count/inventory syncs required by adding one command file

Adding `commands/onboard.md` moved these pinned counts (all designed to be updated when a command
is legitimately added; none is a test weakening):
- `README.md` Commands `<summary>` 30 -> 31 + one `/kit:onboard` row (meta test parity).
- `docs/architecture.md` inventory table: +1 Cross-phase row (meta test row-count parity, 55 -> 56).
- `docs/WORKFLOW.md` "## Command emit coverage" exemption table: +1 `onboard.md` row (10 utility
  commands now). onboard is exempt for the SAME reason as `adopt.md`/`start.md`: it owns no V-model
  phase and runs before any rid/lane exists; it CALLS start/adopt/config, each of which emits or is
  itself exempt.
- `tests/test-command-emit-sweep.sh`: count pin 30 -> 31, EXPECTED_EXEMPT +onboard, label 9 -> 10.

## 2026-07-12 Pre-existing stale prose left untouched (flagged, not fixed)

`docs/architecture.md` line ~81 reads "Total: 25 commands + 15 agents = 40 entries" but the live
counts are 30 (now 31) commands + 25 agents. This prose is NOT test-asserted (the meta test counts
pipe rows only). Per the surgical-changes rule I did not fix a pre-existing, unrelated inaccuracy;
flagged here for a future docs pass.

## 2026-07-12 Review round: 4 verdicts, 5 fixes (detail in SPEC-199's decision log)

Context: rung-3 recheck + advisor P5 + security/architecture lenses ran post-build.
Decision deltas beyond what the spec pinned: (1) the "leg" column was DROPPED from the wizard's
module presentation (the spec had promised it, but `bin/config` cannot emit it without a fence
bypass; option (b), enriching SG-08's registry Doc cells, was rejected as not this sub-goal's
surface). (2) The `adopt --with` honest caveat derives adopt's seedable set at runtime instead of
enumerating names (AC9-clean + self-healing). (3) Two adopt.sh follow-ups flagged for the lead,
NOT fixed here (goal forbids adopt.sh changes): the stale `KIT_KNOWN_MODULES` (9 vs install.sh's
12) and the hook-command path hardcoding that leaves adopt-wired per-repo hooks dead on
plugin-only machines (disclosed honestly in section E instead).
