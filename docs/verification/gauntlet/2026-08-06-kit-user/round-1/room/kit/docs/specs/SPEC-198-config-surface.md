# SPEC-198: config-surface (`bin/config` read/explain + the env<->key module registry)

Status: SHIPPED (test + run-table confirmed)
Lane: full
Backlog: harness-loop sub-goal 08 (`_meta/megagoals/harness-loop/goals/08-config-surface.md`)
Branch: feat/loop-08-config-surface (stacked on `docs/loop-01-taxonomy`, PR base
`docs/loop-01-taxonomy`)
Relates-to: ADR-0034 (`docs/decisions/0034-harness-loop-taxonomy.md`, decisions 3 + 4),
`docs/briefs/DECISION-BRIEF-config-layer.md` (the locked read model), `lib/config/kit-config.sh`
(the resolver, unchanged), `lib/telemetry/kit-log-dir.sh` (the env-over-toml precedence
reference), SPEC-183 (manifest-reconcile), SPEC-192 (project-override, the resolver's other
consumer), `tests/lib/contract-lint.sh` (SG-02's shared grep-diff-against-manifest primitive,
extended here)

## Problem

The kit's runtime knobs are ~70 environment variables plus a 33-key `kit.toml` schema, each
resolved by its own ad-hoc precedence, with no single place to answer "what is this knob's
value right now, and why" (env override vs. project `.kit.toml` vs. kit-root `kit.toml` vs.
hardcoded default) without opening files. There was also no checked-in inventory of which env
vars exist at all -- the ~30-undocumented-vars problem ADR-0034 names, and no enforcement
stopping a new undocumented knob from merging.

## Design

**The registry schema** (ADR-0034 decision 3's machine home, `lib/config/module-registry.md`):
ONE checked-in markdown file, two tables plus two auxiliary tables, all pipe-delimited and
line-oriented (parsed by `awk`/`grep`, never a second TOML reader):

1. **Module legs** -- `| Module | Primary leg | Notes |`. One row per `install.sh`
   `KIT_KNOWN_MODULES` entry (12 of 12; `team_mode` is excluded from that array itself, so it
   is excluded here too). A module with two legs (board, session) is a documented "spanner"
   in its Notes cell, per ADR-0034 decision 3's authoritative table. A completeness lint
   asserts every `KIT_KNOWN_MODULES` entry has a row.
2. **Env <-> key registry** -- `| Env var | kit.toml key | Default | Status | Module | Doc |`,
   split into topical `###` subsections (config, data-plane, STATS_\*, mega, queue, board,
   session, gate, prose_rag/money_gate, modules, features/team) for human scanability. Every
   row has at least one of `Env var` / `kit.toml key` populated (`-` for the other); this is
   deliberately a SUPERSET of "env<->key" -- it also carries every declared `kit.toml`-only
   key (no env override), because `bin/config list`'s contract is "every declared key," not
   just the env-var-shaped subset. `Status` reuses `kit.toml`'s own tags
   (`[impl]/[design]/[reserved]/[consumer]`).
3. **Allowlist** -- `| Token | Why excluded |`. Tokens the seed regex matches that are NOT
   real user-facing env vars (a script-local computed path, a test-fixture-only name, or an
   unrelated false positive like `KITTY_WINDOW_ID`). The drift lint treats a hit against any
   of these as covered without a registry row.
4. **Known gaps** -- prose, not a lint input. Real env vars found outside the seed regex's
   fixed prefix family during verification (e.g. `LANE_DEESCALATE_FLOOR`,
   `MUTATION_SMOKE_*`), named so they are not lost, explicitly out of this sub-goal's scope.

**`bin/config`'s resolution model.** `lib/config/config.sh` sources `lib/config/kit-config.sh`
UNCHANGED and calls its existing accessors (`kit_config_get`, `kit_config_root`,
`kit_config_project`, and the internal `_kit_toml_get`) for every value lookup -- this file
does not parse TOML itself, holding the ADR-0034 decision-4 fence
("`lib/config/kit-config.sh` stays the ONLY reader of TOML"). For each registry row it computes
a 4-level provenance chain, generically, for any key:

```
1. env               (if the row names an env var and it is set)
2. project .kit.toml  (if the row names a kit.toml key, via _kit_toml_get on $KIT_PROJECT_ROOT/.kit.toml)
3. kit-root kit.toml  (via _kit_toml_get on $KIT_CONFIG_ROOT/kit.toml)
4. default            (the registry's own Default cell)
```

The first level with a value wins; `EFFECTIVE`/`PROVENANCE` (plus the per-level values, for
`explain`) are globals set by `_resolve()`, mirroring the small-bash-script house style of
`lib/classify/lane-classify.sh`'s `LANE`/`REASON`/`FIRED` globals rather than a subshell-return
dance. A key backed by TWO env vars (`KIT_LEDGER_DIR` / `DWARVES_KIT_LOG_DIR`, both mapping to
`ledger.location`) gets one row per env var; each row resolves independently under the generic
model -- this is a deliberate simplification, not a replay of
`kit_resolve_log_dir`'s bespoke two-env tie-break (documented in that row's Doc cell, which
points back at the authoritative function).

**Non-`[impl]` keys render visibly inert.** `config list` never shows a `[design]`/
`[reserved]`/`[consumer]` key's resolved value as if it were live; it prints
`(inert: <tag>, no live effect)` instead, so a reader cannot mistake a designed-not-built
key for a working toggle (the goal's quality bar: "an inert key is documented, never a silent
surprise").

**The drift lint reuses `tests/lib/contract-lint.sh`, not a second bespoke grep.** SG-02
shipped `manifest_diff_by_phase` (a per-file phase-pairing sweep: does file X's phase P have
its coverage bracket IN THE SAME FILE X). SG-08's need is a different shape: a token can be
read from ANY of `lib/hooks/bin`, but is registered ONCE in a separate file
(`lib/config/module-registry.md`). This sub-goal adds `manifest_diff_flat` alongside it in the
same shared file -- the flat-SET sibling, reusing the same `_regex_escape` helper, same
`ORPHAN:`-line + return-count contract, same "library, no side effects on source" shape.
`tests/test-config-registry.sh` calls it with the goal's literal seed regex, dynamically
deriving the allowlist regex from the registry's own Allowlist table (no second hand-maintained
copy of that list).

## Scope edges

**In:** `bin/config {list|get|explain}`, the checked-in registry (module legs + env<->key +
allowlist + known-gaps), the drift lint + module-leg completeness lint (both built on
`tests/lib/contract-lint.sh`).
**Out:** `config set` (help text names `.kit.toml` hand-edit as the current path), any
`lib/config/kit-config.sh` change, any hook behavior change, any `kit.toml` schema change.
**Not:** a TUI, editing env for the user, "fixing" an undocumented var by deleting it
(register it instead; retiring a knob is a future decision), replaying every resolver's
bespoke precedence quirk (the two-env `ledger.location` case resolves generically per-row, not
bit-for-bit identically to `kit_resolve_log_dir`).

## Verification

1. `bash tests/test-config-registry.sh` -- 19 assertions: AC1 drift lint (0 orphans on the
   live tree), AC2 negative control (a planted `KIT_TOTALLY_UNREGISTERED_PLANT` IS flagged),
   AC3 module-leg completeness (12/12 `KIT_KNOWN_MODULES` entries have a row), AC4 negative
   control (a fake module name is correctly absent, proving AC3 is not vacuous), AC5 `bin/config`
   functional smoke (`get`/`explain` by both env-var-name and dotted-key lookup; machine-clean
   `get` output for scripting -- backtick literal extracted, annotation stripped, one quote
   layer removed; set-but-empty env treated as unset, matching every consumer's `${VAR:-}`
   semantics; an unknown-key error path; a missing-registry-file hard failure; the multi-env-row
   registry-order tie-break for `ledger.location`; and the env-override + project-override
   fixture visibly winning distinct rows in one `list` render).
2. `bash lib/config/kit-config.sh selftest` (== `bash tests/test-config.sh`) -- unchanged
   resolver mechanics, still green (byte-identical selftest; the resolver file itself has zero
   diff against the branch point).
3. `bash tests/test-meta.sh` -- 683/683 (regression: no structural drift).
4. `bash tests/test-hooks.sh` -- 453/453 (regression: no hook-behavior drift; this sub-goal
   touches no hook).

## After state

- `bin/config list|get|explain` is live: every declared knob (env-only, `kit.toml`-only, or
  both) rendered with effective value, 4-level provenance, status tag, and owning module.
- `lib/config/module-registry.md` is the checked-in single source: 12 module-leg rows (12/12
  `KIT_KNOWN_MODULES` coverage) + 87 env<->key rows (58 real vars from the goal's seed sweep +
  5 additional `STATS_*` source vars named explicitly by the goal's data-plane completeness
  instruction + 4 config-bootstrapping vars the drift lint's own negative-control run caught
  missing during authoring + the remaining rows are the 33 `kit.toml`-only keys) + 17
  allowlisted internal/false-positive tokens + a documented known-gaps list.
- The drift lint (`tests/test-config-registry.sh` AC1/AC2) means an env var matching the seed
  regex's prefix family, read in `lib/`/`hooks/`/`bin/`, and absent from both the registry and
  the allowlist now fails CI (wired into `.github/workflows/test.yml`).
- `lib/config/kit-config.sh` (the resolver) is byte-identical to the branch point; its selftest
  is unchanged and still green.
- Proof: `docs/verification/loop-08-config-surface.md`.
