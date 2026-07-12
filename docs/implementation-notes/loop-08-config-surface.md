# Implementation notes: SPEC-198 config-surface (harness-loop sub-goal 08)

Running log of decisions/changes not pinned in the spec (delta only; see
`docs/specs/SPEC-198-config-surface.md` for what shipped).

## 2026-07-12 `prose_rag` has no leg in ADR-0034's decision-3 table

ADR-0034's module -> primary-leg table (decision 3) does not include `prose_rag` (verified:
`grep -n prose_rag docs/decisions/0034-harness-loop-taxonomy.md` has zero hits inside the leg
table). Since `prose_rag` IS a `KIT_KNOWN_MODULES` entry and this sub-goal's own completeness
rule requires every one of the 12 to have a row, this is a genuine gap in an already-Proposed
ADR, not something I could silently skip. Assigned `Learn` by my own judgment (prose-rag is a
recall/retrieval read over the user's accumulated corpus -- til/research/learned-ledger --
the same read-side shape as the Learn leg's other members: `weekend_batch`, `learn`, session
harvest, board staging/promote; it is not an Observe-class run-telemetry capture). Recorded as
an explicit, flagged deviation in the registry's Module-legs row (not silently absorbed), so
Han can amend ADR-0034 if he disagrees. Reported in the PR/handoff for DECISIONS.md.

## 2026-07-12 `bin/config list`'s scope widened past "env<->key" to "every declared key"

The goal's Outcome paragraph says two things that are in tension if read narrowly: the registry
is "one checked-in table mapping every user-facing env var to its kit.toml key," but
`bin/config list` must render "every declared key" with status tag + owning module. A
`kit.toml`-only key (e.g. `modules.board`, `gate.understanding_gate`, all 7 `team.*` keys) has
no env var, so an env-var-keyed table alone can't drive that render. Resolved by making the
registry's Env<->key table a superset: every row has AT LEAST ONE of {env var, kit.toml key}
populated (`-` for the other). This stays "one checked-in table" (ADR-0034 decision 3's own
phrasing) and does not add a second TOML reader -- the toml-only rows' VALUES still resolve
through `kit_config_get`/`_kit_toml_get`, only the row's EXISTENCE is checked-in text, not
derived from a runtime re-parse of `kit.toml`'s structure.

## 2026-07-12 STATS_* completeness pulled from `lib/stats/README.md`, not just the seed regex

The seed regex is bash-`$VAR`-shaped; it cannot see a Python `os.environ.get("STATS_...")` call
with no `$` sigil. It DID catch 5 STATS_* vars (via bash test-fixture files that `export`/read
them with `$` syntax), but `lib/stats/README.md` already documents 5 MORE
(`STATS_GIT_REPO_DIR`, `STATS_MEMORY_REPO_DIR`, `STATS_SESSIONS_DIR`,
`STATS_SECRET_GUARD_LOG`, `STATS_MEMORY_PROJECTS_ROOT`) that the seed sweep missed entirely.
The goal explicitly calls out "every STATS_* source var with its no-default-consumer marking"
by name, so I registered all 10 (verified each against `lib/stats/src/stats/config.py`
directly, not just the README's claim), not only the 5 the seed regex happened to catch. The
drift LINT itself still only enforces the seed-regex-catchable subset (documented as a known
gap, see below) -- the extra 5 rows are registered for completeness but are not lint-enforced.

## 2026-07-12 Drift lint caught 4 real gaps during authoring (AC1 failed on first run)

First `tests/test-config-registry.sh` run: AC1 (drift lint) failed with 4 orphans --
`DWARVES_KIT`, `DWARVES_KIT_DEBUG`, `KIT_CONFIG_ROOT`, `KIT_PROJECT_ROOT`. These are real,
already-researched vars (the resolver's own bootstrap knobs + the kit install root) that I had
researched but never actually written into the registry table. Added a `### config` subsection
with all 4 rows; AC1 went green. Kept as a concrete demonstration that the lint does real work,
not just on a planted fixture -- it caught a gap in THIS SAME PR's own authoring.

## 2026-07-12 `ledger.telemetry` retagged `[design]`, `kit.toml`'s own comment says `[impl]`

`kit.toml` line 50 tags `telemetry = true` `[impl]` ("write run-tracking streams or not"), but
grepping `ledger.telemetry` and `kit_config_get ledger` across `lib/`+`hooks/` finds only the
`kit-config.sh` selftest, no real consumer. The registry retags this row `[design]` and notes
the discrepancy inline, rather than silently trusting `kit.toml`'s comment or silently "fixing"
it (out of scope: no `kit.toml` schema changes). Flagged for the lead as a pre-existing
`kit.toml` status-tag drift, unrelated to this sub-goal's own work.

## 2026-07-12 Two-env `ledger.location` (`KIT_LEDGER_DIR`/`DWARVES_KIT_LOG_DIR`) resolves per-row, not bit-for-bit against `kit_resolve_log_dir`

`lib/telemetry/kit-log-dir.sh::kit_resolve_log_dir` has a bespoke 2-env tie-break (canonical
wins over back-compat alias, both win over the toml key, set-but-empty is fatal). Replaying
that exact function inside `config.sh` would mean re-implementing resolver-specific logic
outside the resolver (or a second, subtly-different reader). Instead: each env var gets its own
registry row and resolves independently under the GENERIC 4-level model. This is accurate per-row
("if you set `$KIT_LEDGER_DIR`, THIS specific row/knob is env-sourced" -- true) but does not
reproduce the authoritative end-to-end precedence when BOTH vars are set simultaneously in
different directions. Documented in both rows' Doc cells, pointing back at the real function.
Accepted trade-off: keeps `config.sh` generic and simple (no per-key special-casing), matches
"no resolver changes" more cleanly (no bespoke logic duplicated outside the resolver file).

## 2026-07-12 Drift lint's prefix-family scope is deliberately bounded to the goal's seed regex

During research, real user-facing env vars were found OUTSIDE the seed regex's fixed prefix
family (`LANE_DEESCALATE_FLOOR`, `MUTATION_SMOKE_*`, `WATCHDOG_*`, `SPEC_RESERVE_*`,
`MONEY_GATE_STRICT`, etc. -- ~18 more tokens, listed in the registry's "Known gaps" section).
The goal names an EXACT, reproducible sweep command as "the source material"; widening the
prefix family unilaterally would mean the registry no longer traces to a single reproducible
command, and would balloon this sub-goal's scope well past "config surface for the already-named
family." Decision: registered/documented the gap honestly (Known gaps section) rather than
silently expanding scope OR silently ignoring the finding. A future sub-goal can either widen
the prefix family or switch the lint's detection to the structural `${VAR:-`/`[ -n "${VAR:-}"]`
pattern (which would need no allowlist maintenance at all, but is a bigger rewrite).

## 2026-07-12 `manifest_diff_flat` added to `tests/lib/contract-lint.sh` (not a second bespoke grep)

SG-02's `manifest_diff_by_phase` pairs a site with its coverage IN THE SAME FILE (per-file
phase pairing). SG-08's need is a flat SET diff across MANY files against ONE external manifest
file -- a different shape, not a parameterization of the existing function. Added a sibling
function (`manifest_diff_flat`) in the same shared library file, reusing `_regex_escape` and
matching the existing `ORPHAN:`-line + return-count contract, rather than writing a bespoke
grep loop inside `tests/test-config-registry.sh` itself. This satisfies the goal's explicit
"do not write a second bespoke grep" instruction while fitting the actual (different) shape of
the problem. Used a WORD-BOUNDED coverage check (`(^|[^A-Za-z0-9_])TOKEN([^A-Za-z0-9_]|$)`, not
GNU `\b`, for macOS/BSD grep portability per the file's own portability contract) rather than a
bare substring match, so a short token (e.g. `KIT`) cannot be spuriously "covered" by a longer
registered token's text (`KIT_LEDGER_DIR`) appearing anywhere in the manifest.

## 2026-07-12 The "resolver untouched" check is a one-time proof, not a standing test assertion

Drafted an AC6 in `tests/test-config-registry.sh` asserting `git diff` against the branch point
is empty for `lib/config/kit-config.sh`. Removed it before shipping: a FUTURE PR may legitimately
edit the resolver for its own valid reason, and a permanent test pinned to "this file has zero
diff against commit X" would fail forever after, for reasons unrelated to config-surface. Kept
the check as a one-off `git diff --stat` command, captured once in the proof-of-done
(`docs/verification/loop-08-config-surface.md` #9), not as a durable regression invariant.

## 2026-07-12 CI wiring

`tests/test-config-registry.sh` was NOT auto-discovered by any runner (this repo's CI lists
each test file explicitly in `.github/workflows/test.yml`; confirmed even `tests/test-config.sh`,
the resolver's own pre-existing selftest wrapper, is not wired into CI today -- an existing gap,
not introduced here, and out of this sub-goal's scope to fix). Added one new step so the drift
lint's "an unregistered var can no longer merge" claim (PR body) is actually true in CI, not
just true when run locally.

## 2026-07-12 Review round: 2 MAJOR + 2 MINOR, all fixed pre-push

A fresh-context review pass (multi-lens, per the AGENTS.md enforcement-surface escalation rule
for lib/-touching runs) verified all five hard fences hold and spot-checked 7 registry rows
against their cited sources (all accurate), then found four real defects, all fixed:

1. **MAJOR, machine-dirty `get` output.** `config get QUEUE_POLL_SECS` printed the registry
   cell's human markdown verbatim (backticks + annotations: `` `15` ``, `` `1` (truthy)``),
   breaking its own "for scripting" contract -- and the test suite had encoded the bug as the
   expectation. Fix: `_default_value()` extracts the first backtick-quoted literal and strips
   one double-quote layer (mirroring `_kit_toml_get`'s unquote); annotation-only cells
   ((none), **no-default-consumer**) pass through as-is, honestly. Tests updated to assert the
   clean scalar.
2. **MAJOR, set-but-empty env treated as a win.** `_resolve()` used `declare -p` (existence),
   so `WAVE_CAP="" config explain` reported an empty env win that the real consumer
   (`${WAVE_CAP:-...}` in orchestrate.sh) would never see. Fix: non-empty test
   (`[ -n "${!envvar:-}" ]`), consistent with the TOML levels' own `[ -n ... ]` checks; new
   test asserts empty env falls through to the default.
3. **MINOR, allowlist header leak.** The test's `_allow_regex` awk included the Allowlist
   table's header word "Token" in the derived allow-regex (harmless today, a silent
   over-allowlist if the prefix family widens toward T-). Fix: explicit header-row skip,
   mirroring `_registry_rows`.
4. **MINOR, silent success on a missing registry.** `cmd_list`'s `< <(_registry_rows)` process
   substitution swallowed the missing-file error, rendering a header-only list with exit 0.
   Fix: an up-front registry-file existence guard in `main()` for all three read verbs (a
   separate guard `case`, not `;;&` fall-through, which is bash-4-only and macOS ships 3.2);
   new test asserts the hard failure.

Also added from the review's coverage-gap list: a test for the `ledger.location` multi-env-row
registry-order tie-break (KIT_LEDGER_DIR's canonical row wins a bare-key lookup). Plus one
display nicety the fix surfaced: a machine-EMPTY default (TIER4_CORPUS, CC_SI_MEMORY_LEDGER)
renders `(empty)` in `list` (display only; `get` still emits the honest empty string). Suite
after the round: 19/19 (was 14/14); full regression re-run green (meta 683, hooks 453).

## 2026-07-12 No deviations from the goal's scope fences

`config set` was not built. `lib/config/kit-config.sh` has zero diff against the branch point.
No hook file was touched. `kit.toml`'s schema (keys/sections) is unchanged -- only its
INLINE COMMENT accuracy was flagged (`ledger.telemetry`), not edited.
