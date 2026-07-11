# Spec: OUTCOME emit sweep (harness-loop sub-goal 02)

Generated: 2026-07-12
Status: VALIDATED
Lane: normal (per `bash lib/classify/lane-classify.sh classify`; pure coverage of an
existing emitter, no new marker, no schema change, no gate-decision behavior change).

## Problem

SPEC-129 added the `outcome`/`outcome-read` verbs to `lib/gate/gate-ledger.sh` (an additive
`| OUTCOME |` start/end bracket beside the existing `| GATE |` line) and wired the ONE live
emitter at `hooks/ship-gate.sh`'s ship boundary. SPEC-131's `kit_gates` reader
(`lib/stats/src/stats/adapters.py::read_kit_gates`) already PAIRS a `| GATE | <phase> | ran |
...` line with an `| OUTCOME | <phase> | start/end |` bracket by matching phase name, FIFO
per (rid, phase) in file order, and its own docstring says so plainly: "As of this writing
NO real run ledger emits an OUTCOME bracket yet ... so on the real corpus every row's
caught/start_ts/end_ts is NULL, by design." `stats mega-durations` and `stats digest`
therefore read honest-zero on every real run today, not because the consumer is broken, but
because every phase OTHER than `ship` never emits the bracket the consumer already knows how
to read.

## Inventory (the delta, per goal step 1)

`rg -n 'gate-ledger.sh (record|override)' commands lib | rg -v outcome`, filtered to real
call sites (excludes `lib/stats/docs/**`, which is prose/reference documentation, not
executable command definitions, and excludes `commands/mega.md:372`, which is prose
discussing `gate-ledger.sh override`'s audit-trail role, not a call site).

22 `record <rid> <phase> ran ...` sites across 15 command files had no paired OUTCOME
bracket. `record <rid> <phase> skipped ...` sites (`grill.md:200`) are deliberately left
unbracketed: a skip means the phase did NOT run, so there is no duration to measure, and
bracketing it would fabricate a near-zero-but-meaningless timing row. This mirrors the
"ran-only" contract implicit in `read_kit_gates`'s own docstring (a GATE row with no bracket
just reports NULL, honestly).

| # | File | Phase (exact, as passed to `record`) | `<rid>` form | caught= derivation |
|---|---|---|---|---|
| 1 | `commands/execute.md` | `build` | `<rid>` | `true` if any task escalated or the final test run is `fail`, else `false` |
| 2 | `commands/test-plan.md` | `test-plan` | `<rid>` | omitted (authoring has no pass/fail; defaults `false`) |
| 3 | `commands/review.md` | `review` | `<rid>` | `true` if verdict != `SHIP` |
| 4 | `commands/grill.md` | `grill` (ran only) | `<rid>` | `true` if contradictions `M` > 0 |
| 5 | `commands/pitch.md` | `pitch` | `<rid>` | omitted (assembly, no verdict; defaults `false`) |
| 6 | `commands/test-plan-review-team.md` | `test-plan` | `<rid>` | `true` if verdict != `SOLID` |
| 7 | `commands/spec-validate.md` | `Validate` | `<rid>` | `true` if verdict != `APPROVED` |
| 8 | `commands/spec-validate.md` | `design-record` | `<rid>` | `true` if the row is `critical` |
| 9 | `commands/review-team.md` | `advisor` (Step 2b) | `"$rid"` | `true` if findings `N` > 0 |
| 10 | `commands/review-team.md` | `review` (Step 4) | `<rid>` | `true` if verdict != `SHIP` |
| 11 | `commands/verify.md` | `verify` | `<rid>` | `true` if verdict != `PASS` |
| 12 | `commands/retro.md` | `Reflect` | `<rid>` | `true` if action-items `N` > 0 |
| 13 | `commands/docs.md` | `Docs` | `<rid>` | omitted (descriptive record, no verdict; defaults `false`) |
| 14 | `commands/explain.md` | `explain` | `<rid>` | omitted (no verdict; defaults `false`) |
| 15 | `commands/devs-team.md` | `review` | `<rid>` | `true` if verdict != `SOLID` |
| 16 | `commands/devs-team.md` | `design-critique` | `<rid>` | `true` if verdict != `SOLID` (mirrors #15, same run) |
| 17 | `commands/spec.md` | `Spec` | `<rid>` | omitted (record fires only post-approval; defaults `false`) |
| 18 | `commands/design.md` | `Design` | `<rid>` | omitted (no verdict; defaults `false`) |
| 19 | `commands/mega.md` | `advisor` (mode=P5) | `"$FINAL_RID"` | `true` if findings `N` > 0 |
| 20 | `commands/mega.md` | `advisor` (mode=P6) | `"$FINAL_RID"` | `true` if proposals `N` > 0 |
| 21 | `commands/think.md` | `Think` | `<rid>` | `true` if verdict != `BUILD` |
| 22 | `commands/ui-design.md` | `UI design` | `<rid>` | `true` if verdict != `SOLID` |

Rule for the `caught=` column (uniform across every site, so a reviewer can predict it
without re-deriving): if the phase's own recorded free text already carries a VERDICT enum
(SHIP/FIX-THEN-SHIP/DO-NOT-SHIP, PASS/FAIL/INCONCLUSIVE, APPROVED/NEEDS-REVISION,
SOLID/REVISE/RECONSIDER, BUILD/RETHINK/KILL) or a COUNT of findings/contradictions/action
items, derive `caught=true` from "non-clean verdict" or "count > 0". Otherwise (the record is
purely descriptive: a file list, a ref, an approval note, an assembled doc), omit `caught=`
and let the verb's own documented default (`false`, "a clean pass is the safe default", per
`gate-ledger.sh outcome`'s header comment) stand. This is a scope decision, not a workaround:
inventing a verdict where the command has none would be new gate-decision behavior, out of
scope.

## Solution

**Same one-line-pattern-per-site, twice per site.** At the natural start of each phase's
substantive work (the top of `## Process`, or the specific step where that phase's work
actually begins, when a file owns more than one phase), add one instruction:

```
bash lib/gate/gate-ledger.sh outcome <rid> <Phase> start
```

Immediately adjacent to the existing `record <rid> <phase> ran ...` line, add one instruction
closing the bracket:

```
bash lib/gate/gate-ledger.sh outcome <rid> <Phase> end [caught=<true|false>]
```

`<Phase>` is copied VERBATIM from the site's own existing `record` call (including case and
spacing, e.g. `Think`, `"UI design"`, `design-record`) because `gate-ledger.sh` normalizes
both the `record` and `outcome` phase argument through the SAME `normalize_phase()` (lowercase
+ dash-join + drop parenthetical), so `Think`/`think` and `"UI design"`/`ui-design` land on
the identical normalized key either verb uses -- no new normalization logic needed, and the
GATE/OUTCOME phase strings pair correctly in `read_kit_gates`'s FIFO match.

**Two-phase-same-name sites (`mega.md`'s `advisor` P5 then P6).** `read_kit_gates` pairs GATE
rows to OUTCOME brackets FIFO per phase in file-append order (not by proximity), so two
`start`/`record ran`/`end` triples for the SAME phase name, emitted in sequence, pair
correctly with no new pairing logic: the first bracket to complete pairs with the first GATE
row of that phase, the second with the second.

**Nothing about `gate-ledger.sh` changes.** The `outcome`/`outcome-read` verbs already exist
(SPEC-129); this sweep is markdown-instruction wiring only, plus one new standing test (below).
No new marker, no schema change, no change to `check()`/`override()`/`descent()`/`_rows()`/
`_token_agg()`/the ship-gate boundary -- they all still key on `$2=="GATE"` and ignore `$2==
"OUTCOME"` lines, so a bracketed run and an unbracketed run are byte/row-identical through
every existing reader (SPEC-129's additive-equivalence property, unchanged, re-verified by
the existing `tests/test-gate-outcome.sh`, not re-tested here).

### Standing coverage lint

`tests/lib/contract-lint.sh` -- a small, parameterized, grep-diff-against-manifest helper (no
new file per lint; a shared primitive `tests/test-outcome-emit-sweep.sh` calls, and the one
kit-hardening SG-08's registry lint is expected to reuse per the goal file). It exposes one
function:

```
manifest_diff <dir> <glob> <has_pattern> <site_pattern> <exempt_list>
```

For every file in `<dir>` matching `<glob>` that contains a line matching `<site_pattern>`
(a `record <rid> <phase> ran` call), the file must ALSO contain a line matching
`<has_pattern>` (an `outcome <rid> <same-phase> end` call) for that SAME phase, OR be named in
`<exempt_list>`. Prints one `ORPHAN: <file> (<phase>)` line per gap; return code = orphan
count. This mirrors the no-orphan sweep shape already proven by `tests/test-docs-wiring.sh` /
`tests/test-kri-wiring.sh` / `tests/test-command-emit-sweep.sh`, generalized to a reusable
function instead of a bespoke per-test copy.

`tests/test-outcome-emit-sweep.sh` calls `manifest_diff` over `commands/*.md` (`record ...
ran` -> paired `outcome ... end`) and asserts zero orphans on the real repo, plus the two
required negative controls (goal step "done ="):
1. **A planted unbracketed site fails the lint** -- a fixture command file with a `record ...
   ran` line and NO paired `outcome ... end` line IS flagged.
2. **The 22-site inventory is exactly covered** -- a per-phase assertion that each of the 22
   sites above has both an `outcome ... start` and an `outcome ... end` line for its exact
   phase string.

## Scope

**In:** the OUTCOME bracket pair at all 22 inventoried `ran` sites; the `tests/lib/
contract-lint.sh` shared helper; `tests/test-outcome-emit-sweep.sh` (the standing coverage
lint + its NC); a fixture-run proof-of-done (paired ledger slice + `stats mega-durations`
non-empty row + the honest-empty NC on a legacy/unbracketed ledger).

**Out:** new stats lenses, the dashboard (mega-goal sub-goal 07), any `| OUTCOME |` marker
schema change, `lib/queue/orchestrate.sh` (its `gate-ledger.sh start`/`tokens` calls are a
DIFFERENT tracking concept -- SPEC-101/SPEC-110 dispatch telemetry, not a `record ... ran`
phase call -- so the inventory grep correctly does not match it, and it is out of this
sweep's scope).

**Not:** "while here" refactors of `gate-ledger.sh` (the `outcome` verb already exists and is
untouched); a retention/rotation feature; backfilling old ledgers (pre-sweep runs stay
honest-empty forever, by design -- `read_kit_gates`'s own docstring already documents this as
correct, not a bug).

## Verification

1. `bash tests/test-outcome-emit-sweep.sh` -- zero orphans on the real `commands/*.md`, the
   planted-fixture NC catches an unbracketed site, all 22 sites individually asserted.
2. `bash tests/test-gate-outcome.sh` -- unchanged, still green (proves the additive-equivalence
   property this sweep depends on was not touched).
3. `bash tests/test-command-emit-sweep.sh` -- unchanged, still green (proves the pre-existing
   `record ... ran` coverage sweep is undisturbed by the new `outcome` lines added alongside).
4. Fixture-run proof-of-done: a hand-built ledger (`docs/verification/fixtures/loop-02-
   outcome-emit/runs/*.log`) simulating a `normal`-lane run through `think` -> `spec` ->
   `build` -> `review` -> `docs` -> `ship`, each phase emitting the EXACT `outcome start` /
   `record ran` / `outcome end` sequence this sweep wires into the corresponding command file.
   `uv run stats mega-durations --json` against it returns a non-empty `durations` row with a
   plausible `wall_seconds`.
5. Negative control: `uv run stats mega-durations --json` against a pre-sweep-shaped ledger
   (GATE rows, zero OUTCOME lines) returns `"n_rids_with_complete_timestamps": 0` and
   `"durations": []`, exit 0 -- no fabricated zero row (the existing `lib/stats/tests/
   fixtures/mega-durations-stripped/` fixture already proves this generically; this spec adds
   one fixture rid of its own so the proof-of-done is self-contained to this sub-goal, not
   only a pointer to a pre-existing fixture).

## After state

Every `record <rid> <phase> ran ...` call site in `commands/*.md` has a paired `outcome
<rid> <phase> start` / `outcome <rid> <phase> end [caught=...]` bracket. A NEW real run
through any of these 15 commands populates `kit_gates.start_ts`/`end_ts` for that phase, so
`stats mega-durations` and `stats digest` read a real wall-time number instead of honest-zero
for runs going forward. Pre-sweep ledgers are untouched and continue to read honest-zero
(by design, never backfilled). A new command added later with a `record ... ran` call and no
paired `outcome` bracket fails `tests/test-outcome-emit-sweep.sh` in CI, closing the coverage
gap forever, the same no-orphan contract `tests/test-command-emit-sweep.sh` already proved
for the `record` layer itself.

## Decision Log

- `grill.md`'s `skipped` site (line 200) is deliberately left unbracketed: a skip has no
  duration to measure; bracketing it would fabricate a near-zero row for work that did not
  happen. Only `ran` sites are bracketed.
- `caught=` is omitted (defaults `false`) at 8 of the 22 sites (`test-plan.md`, `pitch.md`,
  `docs.md`, `explain.md`, `spec.md`, `design.md`) because those phases' own recorded free
  text carries no verdict/count to derive it from honestly; inventing one would be new
  gate-decision behavior, out of scope.
- `lib/queue/orchestrate.sh` is out of scope: its `gate-ledger.sh start`/`tokens` calls track
  a different concern (SPEC-101 dispatch telemetry), not a `record ... ran` phase call, so it
  never matched the inventory grep and needed no edit.
