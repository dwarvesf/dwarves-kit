# Spec: a depth line in the spec header
Generated: 2026-09-29
Status: DRAFT
Lane: full
References: `docs/research/2026-09-29-openrig-absorption.md:107-112` (design D2); `lib/gate/gate-policy.sh` for the shape of a small single-purpose reader with an exit-code contract; SPEC-368 (lanes as data), from which this spec was split.

## Problem

Deeper planning runs by topic or by default, not because a spec needs it.

| Symptom | Evidence |
|---|---|
| Every brownfield spec sends 4 research agents | `commands/spec.md:21-34` ("If modifying existing code, run codebase research"); only greenfield skips (`:64`) |
| The research agents read the repo, never outside docs | `commands/spec.md:31-34`: stack, features, architecture, pitfalls, all of this codebase |
| The test-plan review team gates in practice | `/kit:test-write` stops without a fresh SOLID critique (`commands/test-write.md:15-31`); the review team runs 6 lenses for up to 3 rounds (`commands/test-plan-review-team.md:45-60`) |
| The full lane maps the test-plan review to "always runs" | `docs/WORKFLOW.md:339` |
| Full-lane planning phases get overridden more than run | think / reflect / design overridden 17 / 11 / 11 / 10 times across about 108 ledgers (`docs/research/2026-09-29-openrig-absorption.md:64`); 21 / 14 / 15 / 14 across 149 ledgers today (recount command in SPEC-368 `## Grounding`) |
| No join key ties a dispatched agent to its run | SPEC-367 (ceremony lens) joins dispatches to runs through a `rid=<rid>` token in the Agent description (`SPEC-367-ceremony-lens.md:85`); `commands/spec.md` step 5 dispatches carry none today (`commands/spec.md:292-300`) |

The test the research record proposes: deeper planning is earned only by (a) an unknown that only research can close, or (b) a failure mode the author expects not to see alone. "Importance is not the test." The fresh spec validator is not in question: it caught a problem in 19 of 35 runs (`docs/research/2026-09-29-openrig-absorption.md:57`), and it stays on every spec.

## Solution

### Approaches considered

| # | Approach | Tradeoff |
|---|---|---|
| A | Tie research and the test-plan review team to the lane (full gets both, normal gets neither) | One less field, but lanes are keyed on topic, which is exactly the "importance" test D2 rejects |
| B | A one-line `Depth:` header with a named reason, read by a small helper, checked by the validator | One new header line per spec; the reason is free text a lens must judge |
| C | A numeric dial (P0 to P4) as in the source design | Compact, but the numbers mean nothing to a new reader (plain-words rule) |

### Chosen approach + why

B. The discriminator is the reason, not the topic, so it has to live next to the spec it describes. Plain level names (`standard`, `research`, `blind-spot`) read without a legend. The helper makes the format check mechanical; the validator lens judges whether the reason is real.

### Extensibility & boundaries

- Load-bearing dimension: the number of optional planning steps. A new one is one more level name in the helper and one routing line in the command that runs it.
- Units: (1) `lib/spec/spec-depth.sh` parses and checks the line; (2) `commands/spec.md` step 1 decides the level, step 2 routes research by it, step 5 tags dispatches; (3) `commands/spec-validate.md` Reviewer 4 rejects a bad line; (4) `commands/test-plan.md`, `test-plan-review-team.md`, `test-write.md` gate the review team by it.

## Picture

```
 /kit:spec step 1 ---> decide Depth, write it under Lane: in the spec header
                            |
                            v
                 lib/spec/spec-depth.sh level|wants|check
            /               |                  \
  standard           research (repo: X)      research (outside: X)
  0 research         4 brownfield agents     /kit:get-api-docs + one web pass
  agents             (step 2, Mode A/B)      (step 2)
            \               |                  /
             ledger: | ACTION | depth=<levels> research_agents=<N>
                            |
 /kit:spec step 5 ---> validator reviewers, each Agent description carries rid=<rid>
                            |
             spec-validate Reviewer 4: `spec-depth.sh check` exit 1 -> CRITICAL
                                       missing Depth -> warning
                                       reason is only importance -> CRITICAL
                            |
 /kit:test-plan ---> blind-spot (failure: Y)? --yes--> /kit:test-plan-review-team
                            | no                          |
                            v                             v
                     /kit:test-write proceeds      /kit:test-write needs SOLID
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Data model (the header line)

Written directly under `Lane:`:

```
Depth: standard (<why nothing deeper is needed>)
Depth: research (repo: <the unknown>)
Depth: research (outside: <the unknown>)
Depth: blind-spot (failure: <the failure mode>)
Depth: research (outside: <the unknown>) + blind-spot (failure: <the failure mode>)
```

- `research (repo: ...)`: a fact about this codebase the author cannot settle by reading the files in front of them or running one command. Turns on the 4 brownfield research agents.
- `research (outside: ...)`: a fact outside the repo (a provider's behavior, a library contract). Turns on `/kit:get-api-docs` for each named API plus one web research pass; it does not send the brownfield agents, which read only the repo.
- `blind-spot (failure: ...)`: a failure mode the author expects not to see alone. Turns on `/kit:test-plan-review-team` after `/kit:test-plan`.
- A reason that only says the work matters (important, critical, risky, core, complex, sensitive, big) earns nothing deeper.
- No `Depth:` line counts as `standard`.

### Diagram

See `## Picture`.

### ADR link(s)

No lasting architecture decision beyond SPEC-368's ADR for the lighter default. The depth levels are listed in `docs/WORKFLOW.md` next to the lane table.

### Boundaries & failure modes

Out of bounds: lanes and the lane-to-phase data (SPEC-368); the validator itself, which runs on every spec whatever the depth. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

`lib/spec/spec-depth.sh` (plus a `depth` forwarder in `lib/spec/spec.sh`, whose job is forwarding only, `lib/spec/spec.sh:1-5`):

| Verb | Output | Exit |
|---|---|---|
| `level <spec>` | the level set, space-separated, in order: `standard`, or any of `research-repo`, `research-outside`, `blind-spot` | 0; a missing line prints `standard` plus one stderr note |
| `wants <spec> <research-repo\|research-outside\|blind-spot>` | nothing | 0 when the spec's levels include it, 1 when not |
| `check <spec>` | one line per problem | 0 clean; 1 on: two `Depth:` lines, an unknown level, a missing `repo:` / `outside:` / `failure:` prefix, an empty reason, or a reason made only of importance words (after dropping stop words, every remaining word is in the list above) |

`commands/spec.md` records one ledger line after step 2: `bash lib/gate/gate-ledger.sh action <rid> "depth=<levels> research_agents=<N>"`.

Every Agent dispatch `commands/spec.md` makes (step 2 research agents, the step 4 full-lane design pass, step 5 validator reviewers and the fallback validator) puts `rid=<rid>` in the Agent `description`, for example `description: "validate R6 rid=lanes-as-data"`. This is SPEC-367's join key.

Invariants:

- The fresh-context validator runs on every spec at every depth.
- `wants` never returns 0 for a spec with no `Depth:` line, so an old spec dispatches no research.
- A manual `/kit:test-plan-review-team` run is always allowed; depth only decides the default and what `/kit:test-write` requires.

### Data model changes

None outside the spec header line.

### API changes

None.

### UI changes

`/kit:spec` step 1 asks one question when the level is not obvious: "Is there a fact you cannot settle from the code or one command, or a failure you expect not to see alone? If neither, depth is standard."

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: `lib/spec/spec-depth.sh` with `level`, `wants`, `check`, and the `depth` forwarder in `lib/spec/spec.sh`. `tests/test-spec-depth.sh` covers every verb. AC: `bash tests/test-spec-depth.sh` passes.

### Phase 2: Core

- [ ] TASK-2: `commands/spec.md`. Template: `Depth:` line under `Lane:` (`:84-86`). Step 1: decide the level with the one question. Step 2 (`:21-66`): route by `spec-depth.sh wants`: `research-repo` sends Mode A/B; `research-outside` runs `/kit:get-api-docs` per named API plus one web research subagent writing `docs/research/<date>-<slug>-outside.md`; neither sends nothing. Record the `depth=` action line. Step 4 design pass (`:274-281`): runs when `bash lib/gate/gate-ledger.sh plan <lane>` lists `design-critique`, instead of naming the full lane (moved here from SPEC-368, since this spec owns `commands/spec.md`). Step 5 (`:290-316`): `rid=<rid>` in every dispatch description. AC: `bash tests/test-spec-depth.sh spec-md-wiring` passes.
- [ ] TASK-3: `commands/spec-validate.md` Reviewer 4 (`:44-56`): run `bash lib/spec/spec-depth.sh check <spec>`; exit 1 is CRITICAL; a missing `Depth:` line is a warning; a reason that names no real unknown or failure (lens judgment) is CRITICAL. AC: `grep -c 'spec-depth.sh check' commands/spec-validate.md` is at least 1, and a validation of the fixture in the test plan returns the CRITICAL.
- [ ] TASK-4: Review-team gating. `commands/test-plan.md` step 4 (`:183-185`): name `/kit:test-plan-review-team` as next only when `wants ... blind-spot`, else `/kit:execute`. `commands/test-plan-review-team.md`: one line saying it runs by default only for `blind-spot` and stays available on request. `commands/test-write.md` step 2 (`:15-31`): the SOLID requirement applies when the spec wants `blind-spot` or a `## Test plan critique` exists; otherwise proceed and say "no test-plan review: depth <levels>". AC: `bash tests/test-spec-depth.sh test-write-gate` passes.

### Phase 3: Polish

- [ ] TASK-5: `docs/WORKFLOW.md`: a short "Depth" paragraph after the lane table; the cycle row (`:145`), the full-lane review map row (`:339`), and the command table row (`:1307`) say "when Depth includes blind-spot". `docs/MANUAL.md` and `docs/architecture.md` rows the doc-projection check asks for; regenerate `docs/FEATURES.md`. AC: `bash lib/gate/doc-projection-check.sh .` and `bash lib/registry/feature-registry.sh check docs/FEATURES.md` pass.

## After state

- [ ] A new spec from `/kit:spec` carries a `Depth:` line under `Lane:`. (Today: no such line.)
- [ ] A brownfield spec with `Depth: standard` dispatches zero research agents, and its ledger has `depth=standard research_agents=0`. (Today: 4 agents on every brownfield spec.)
- [ ] `/kit:test-write` runs on a spec without a critique when depth has no `blind-spot`. (Today: it stops.)
- [ ] `bash lib/spec/spec-depth.sh check` exits 1 on `Depth: research (this is important)`.
- [ ] Every Agent dispatch from `/kit:spec` carries `rid=<rid>` in its description.

## Acceptance Criteria (global)

| # | Criterion | Command | Pass |
|---|---|---|---|
| AC1 | `level` parses every form | `bash tests/test-spec-depth.sh level` | each fixture prints its expected level set; missing line prints `standard` |
| AC2 | `check` rejects bad lines | `bash tests/test-spec-depth.sh check` | exit 1 for: empty reason, `research (this is important)`, `research (critical core change)`, missing prefix, unknown level, two lines; exit 0 for `research (outside: the provider's retry schedule is not documented anywhere we have)` |
| AC3 | `wants` never fires on a spec with no Depth line | `bash lib/spec/spec-depth.sh wants tests/fixtures/spec-depth/no-depth.md research-repo; echo $?` | `1` |
| AC4 | spec.md routes by depth and tags dispatches | `bash tests/test-spec-depth.sh spec-md-wiring` | step 2 names `spec-depth.sh wants`, both research routes, and the `depth=` action; step 5 dispatch text contains `rid=<rid>`; step 4 asks `plan <lane>` for `design-critique` |
| AC5 | Reviewer 4 runs the check | `grep -c 'spec-depth.sh check' commands/spec-validate.md` | `1` or more |
| AC6 | test-write gate follows depth | `bash tests/test-spec-depth.sh test-write-gate` | test-write.md step 2 names `wants ... blind-spot` and the critique-exists case |
| AC7 | Default depth dispatches zero research agents (live run) | `/kit:spec` on a small brownfield task in this repo, then `bash lib/gate/gate-ledger.sh show <rid> \| grep 'depth=standard research_agents=0'` and `ls docs/research/ \| grep -c <slug>` | one match; `0` |
| AC8 | No regressions | `bash tests/test-meta.sh && bash tests/test-hooks.sh && bash tests/test-spec-depth.sh` | all exit 0 |

## Verification

```bash
bash tests/test-spec-depth.sh
bash tests/test-meta.sh && bash tests/test-hooks.sh
```

Plus the one live `/kit:spec` run in AC7, recorded in `docs/verification/spec-depth-line/`.

## Test plan

Date: 2026-09-29

| Case | Kind | Covers | Proof |
|---|---|---|---|
| Brownfield spec with `Depth: standard` through `/kit:spec` | negative control (must send zero research agents) | AC7 | ledger `depth=standard research_agents=0`; no `docs/research/*-<slug>-*.md` |
| Same task with `Depth: research (repo: how the ledger substrate locks)` | positive | AC7 | ledger `depth=research-repo research_agents=4`; 4 research files |
| `Depth: research (outside: ...)` | positive | AC4 | route text names `/kit:get-api-docs` and the web pass, not the brownfield agents |
| `Depth: research (this is important)` | negative control (importance is not the test) | AC2 | `check` exit 1 |
| `Depth: research ()` | negative control | AC2 | `check` exit 1 |
| Spec with no `Depth:` line | negative control (old specs dispatch nothing) | AC3 | `wants` exit 1; `level` prints `standard` |
| Two `Depth:` lines | negative control | AC2 | `check` exit 1 |
| Validator run on the `research (this is important)` fixture | negative control (validator rejects) | AC5 | Reviewer 4 returns CRITICAL; merged verdict NEEDS REVISION |
| `/kit:test-write` on a `standard` spec with no critique | positive (no longer stops) | AC6 | proceeds and prints "no test-plan review: depth standard" |
| `/kit:test-write` on a `blind-spot` spec with no critique | negative control (still stops) | AC6 | stops naming the missing critique |
| Step 5 dispatch descriptions | positive | AC4 | each contains `rid=` |

Dry trace for the key negative control (AC7): `/kit:spec` step 1 writes `Depth: standard (...)`; step 2 calls `spec-depth.sh wants <spec> research-repo` (exit 1) and `wants ... research-outside` (exit 1), so no Agent call is made; the step records `depth=standard research_agents=0`. Reverting step 2 to the unconditional brownfield rule makes the ledger read `research_agents=4` and 4 files appear, which turns the check red.

## Edge Cases

1. The writer does not know the depth until research would have told it: the one question in step 1 decides; an honest "I cannot tell how X works here" is a `research (repo: ...)` reason.
2. A greenfield spec with `research (repo: ...)`: nothing to research in the repo; step 2 skips as today (`commands/spec.md:64`) and records `research_agents=0`.
3. The research agents are not installed: Mode B inline prompts, unchanged (`commands/spec.md:36-58`).
4. `/kit:get-api-docs` has no entry for the named API: the web pass alone runs, and the research file says so.
5. A spec already validated before this change has no `Depth:` line: counts as `standard`; `/kit:test-write` then needs no critique unless one exists.
6. A reason mixing importance words with a real unknown ("critical: provider retry schedule undocumented"): passes `check`; Reviewer 4's lens judges it.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Authors write `standard` on work that needed research | SPEC-367 escape records with `gap: context` | Tune the step 1 question on measured misses, not taste |
| Authors write a fake reason to get deeper planning | Reviewer 4 lens; the ceremony share in SPEC-367 | The reason is visible in the header; a reviewer can challenge it |
| Test-plan gaps a review team would have caught ship | Escapes tagged `gap: judgment` | `blind-spot` on the next similar spec; the validator and code review still run |
| Dispatches without `rid=` | SPEC-367 `rid_source=none` count | The step 5 text carries the token; a missing one is counted, never guessed |

## Migration notes (existing adopted repos)

- Old specs have no `Depth:` line and count as `standard`: no research dispatch on re-run, and `/kit:test-write` proceeds without a critique unless one exists. The validator warns on the missing line; it does not block.
- Repos that relied on the automatic 4-agent brownfield research now get it only with `research (repo: ...)`.

## Out of Scope

- Lanes, lane data, the light default, and the diff floor (SPEC-368).
- Changing the validator (still one fresh-context pass per spec, every depth).
- `commands/execute.md` and its per-task dispatches (SPEC-369), including their `rid=` tags.
- `commands/assign.md`: no change needed; the depth is decided in `/kit:spec`.

## Touches

Single files (serialized by the dispatch gate against any sibling that lists them): `commands/spec.md`, `commands/spec-validate.md`, `commands/test-plan.md`, `commands/test-plan-review-team.md`, `commands/test-write.md`, `docs/WORKFLOW.md`, `docs/MANUAL.md`, `docs/architecture.md`, `docs/FEATURES.md`, `tests/test-spec-depth.sh`.

- lib/spec/**
- tests/fixtures/spec-depth/**
- docs/verification/spec-depth-line/**

## Siblings

| Spec | Relation |
|---|---|
| SPEC-368 lanes-as-data | Split from it. Both edit `docs/WORKFLOW.md`, `docs/MANUAL.md`, `docs/architecture.md`, `docs/FEATURES.md`: land SPEC-368 first, then rebase this. The step 4 design-pass line (`commands/spec.md:274`) reads `gate-ledger.sh plan`, which works before and after SPEC-368 |
| SPEC-367 ceremony-lens | Reads the `depth=... research_agents=` action lines and the `rid=<rid>` dispatch tags this spec emits. SPEC-367 names a separate `feat/dispatch-rid-tag` change for the tag in `commands/spec.md` (`SPEC-367-ceremony-lens.md:85`); this spec carries the `commands/spec.md` half, so that change keeps only `commands/execute.md` |
| SPEC-369 whole-spec-dispatch | Owns `commands/execute.md`; no shared files. Its dispatches need the same `rid=` tag |
| SPEC-366 execution-view, SPEC-370 orca-mega-backend | No shared files |
| SPEC-371 adopt-pointer-onboarding | No shared files. Its first-run tour may name depth as an opt-in idea |

## Decision Log

- DEC-1: Plain level names, not P0 to P4 (plain-words rule).
- DEC-2: `research` splits into `repo:` and `outside:` (operator decision): the brownfield agents read only the repo, so an outside unknown routes to `/kit:get-api-docs` plus a web pass.
- DEC-3: A missing `Depth:` line is a warning, not a critical, so old specs never block.
- DEC-4: The importance-word check is mechanical only for reasons made of nothing else; mixed reasons go to the lens. Rejected: a longer banned-word list (it would reject honest reasons).
- DEC-5: `rid=<rid>` goes in every `/kit:spec` dispatch description, not only the validator's, since research counts are what this spec changes and SPEC-367 measures.

## Grounding

- `commands/spec.md` step 2 today dispatches all 4 research agents on any brownfield spec: `sed -n 21,34p commands/spec.md` ("If modifying existing code, run codebase research before generating the spec ... dispatch all 4").
- `commands/test-write.md` step 2 today stops without a SOLID critique: `sed -n 15,31p commands/test-write.md` ("Missing either -> stop").
- Step 5 dispatch text today has no `rid=`: `grep -c 'rid=' commands/spec.md` returns `0` in this worktree; `<rid>` there appears only as a `gate-ledger.sh` argument.
- Lane of this spec: `bash lib/classify/lane-classify.sh explain --files "lib/spec/spec-depth.sh lib/spec/spec.sh commands/spec.md commands/test-write.md" "<summary>"` returns `full`, flag `kit-machinery`. Text alone returns `normal`. It also removes a default gate (the review team before test-write), so `full` stands.

## Open questions

(none; the operator decided research routing, the review-team trigger, and the rid tag)
