# Sub-goal 01: model-routing enforcement (the `Model:` field reaches `--model`)

**Merge policy:** auto
**Time budget:** 2-3 hours (small-medium; read the goal-file field + thread one flag).
**Proof:** run-table: a goal file with `Model: opus` drives the delegate call to `claude -p --model opus` (positive case, the DEFAULT-is-applied assertion, not only an override) · `Model: sonnet` -> `--model sonnet`, `Model: haiku` -> `--model haiku` · confirm `route-suggest.sh`'s Opus-spend heuristic does NOT contradict a goal file's explicit `Model:` (alignment check) · negative control: a goal file with NO `Model:` field falls back to the documented default tier (not a crash, not a silent wrong tier).
**Depends on:** none.
Model: sonnet
Effort: medium
**Branch:** feat/oh-01-model-routing
**PR base:** master

## Outcome

`orchestrate.sh` honors the per-sub-goal `Model:` field on the DELEGATE path: at the point it dispatches a sub-goal to a fresh `claude -p`, it reads the goal file's `Model:` (opus / sonnet / haiku) and passes it through as `--model`. Today the routing is DOCUMENTED (plan-for-mega-goal template + ADR-0032 section 2) but the delegate call does not provably thread it , this sub-goal makes the field LOAD-BEARING, not advisory. It also confirms `route-suggest.sh`'s existing "Opus-spend heuristic" AGREES with an explicit `Model:` (a goal that says `Model: opus` and a heuristic that would pick sonnet must not silently disagree) and resolves open-fork 3 (enforcement site: `orchestrate.sh` vs `route-suggest.sh`). The observed gap it fixes (research section 4): the ledger-observatory worker put a schema-DESIGN sub-goal on sonnet by a "substantial->opus" heuristic; the planning->opus rule + this enforcement would route it opus.

## Quality bar

Enforce, do not re-decide , the routing RULE (planning->opus, execution->sonnet, trivial->haiku) is ADR-0032's; this sub-goal makes the `Model:` field actually reach `--model`. The DEFAULT-applied positive case is the load-bearing assertion (an override-only test would miss a silently-ignored field). The enforcement site (orchestrate vs route-suggest) is picked once in /spec and the two must not contradict.

## How to close the loop

`/spec` + `/spec-validate` first (pin the enforcement site , open-fork 3 , and the fallback-tier default). Then `bash tests/test-model-routing.sh`: a `Model: opus` goal file reaches `--model opus` at the delegate call (default-applied, not override), each tier maps, the route-suggest alignment check holds, and the no-`Model:`-field fallback NC lands on the documented default. Assumptions: ROADMAP 01 + open-fork 3.

**Done =** the delegate call passes `--model` from the goal file's `Model:` field (default-applied positive case proven for opus/sonnet/haiku), `route-suggest.sh`'s heuristic is confirmed non-contradictory, the no-field fallback NC lands on the documented default, tests green.

## Scope edges

**In:** the `Model:`-field read + `--model` threading at the delegate dispatch in `orchestrate.sh` (or `route-suggest.sh` per open-fork 3), the route-suggest alignment confirmation, tests.
**Out:** the token capture (02); the TIER-4 close (03); the panes (04); the docs (05).
**Not:** re-deciding the routing rule (ADR-0032 owns it); a mid-session model switch (a session cannot switch model, route by the DOMINANT work-type per sub-goal); changing `route-suggest.sh`'s heuristic (only confirm it does not contradict an explicit `Model:`).

## Where to look

`lib/orchestrate.sh` (the delegate dispatch , where `--model` must be threaded), `lib/route-suggest.sh` (the Opus-spend heuristic , the alignment check), ADR-0032 section 2 (the routing rule), the plan-for-mega-goal skill template (the `Model:` field + planning->opus convention, dotfiles 50995cc), the research note section 4 (the observed gap this fixes).

## PR body

Model-routing enforcement: `orchestrate.sh` honors the per-sub-goal `Model:` field on the delegate path , the goal file's `Model: opus|sonnet|haiku` reaches `claude -p --model ...` at dispatch (default-applied, not override-only), and `route-suggest.sh`'s Opus-spend heuristic is confirmed non-contradictory. Executes ADR-0032 section 2. Verify: `bash tests/test-model-routing.sh` (per-tier default-applied + route-suggest alignment + no-field fallback NC). Roadmap: ops-toolkit `_meta/megagoals/orchestrate-hardening/ROADMAP.md`.

## Notes

<empty>
