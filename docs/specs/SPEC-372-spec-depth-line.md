# Spec: a depth line in the spec header
Generated: 2026-09-29
Status: DRAFT
Lane: full
Depth: standard (no outside unknown: every file this spec changes is in this repo and cited below; the one live check is named in AC7)
References: `docs/research/2026-09-29-openrig-absorption.md:107-112` (design D2); `docs/verification/test-plan-review-team.md:37,54-64` (the seeded-gap run where the Coverage and Oracle lenses went RED); SPEC-368 (lanes as data), from which this spec was split.

## Problem

Deeper planning runs by topic or by default, not because a spec needs it.

| Symptom | Evidence |
|---|---|
| Every brownfield spec sends 4 research agents | `commands/spec.md:21-34` ("If modifying existing code, run codebase research"); only greenfield skips (`:64`) |
| The research agents read the repo, never outside docs | `commands/spec.md:31-34`: stack, features, architecture, pitfalls, all of this codebase |
| The test-plan review team is 6 lenses for up to 3 rounds on every spec that wants `/kit:test-write` | `commands/test-plan-review-team.md:27-32,45-60`; `/kit:test-write` stops without a fresh SOLID critique (`commands/test-write.md:15-31`) |
| The full lane maps the test-plan review to "always runs" | `docs/WORKFLOW.md:330-339` |
| Full-lane planning phases get overridden more than run | think / reflect / design overridden 17 / 11 / 11 / 10 times across about 108 ledgers (`docs/research/2026-09-29-openrig-absorption.md:64`); 21 / 14 / 15 / 14 across 149 ledgers today (recount command in SPEC-368 `## Grounding`) |

What must not be cut, with its catch record:

| Stage | Catch record |
|---|---|
| Fresh spec validator | caught a problem in 19 of 35 runs (`docs/research/2026-09-29-openrig-absorption.md:57`). Stays on every spec |
| Test-plan review team | 7 specs carry a `## Test plan critique` (SPEC-052, 204, 208, 209, 210, 211, 212; `grep -l '^## Test plan critique' docs/specs/*.md`). All 7 had round-1 findings; 5 had a CRITICAL (SPEC-052, 208, 210, 211, 212). The Coverage and Oracle lenses alone went RED on a seeded-gap plan (`docs/verification/test-plan-review-team.md:37,54-64`) |

So the review team is not ceremony to drop. The waste is running all 6 lenses with revise rounds on every plan. This spec keeps a cheap floor on every plan and spends the full team only where the author is blind.

The test the research record proposes: deeper planning is earned only by (a) an unknown that only research can close, or (b) a failure mode the author expects not to see alone. "Importance is not the test."

## Solution

### Approaches considered

| # | Approach | Tradeoff |
|---|---|---|
| A | Tie research and the full review team to the lane (full gets both, normal gets neither) | No new field, but lanes are keyed on topic, which is the "importance" test D2 rejects |
| B | A one-line `Depth:` header with a named reason, read by a small helper, checked both ways by the validator; a two-lens floor review on every test plan | One header line per spec; the reason is free text a lens must judge |
| C | A numeric dial (P0 to P4) as in the source design | Compact, but the numbers mean nothing to a new reader (plain-words rule) |

### Chosen approach + why

B. The discriminator is the reason, not the topic, so it lives next to the spec it describes. Plain level names read without a legend. The helper makes the format and the inverse check mechanical; the validator lens judges whether a reason is real. The floor keeps the two lenses with a measured bite on every plan, so `standard` never means "no test-plan review".

### Extensibility & boundaries

- Load-bearing dimension: the number of optional planning steps. A new one is one more level name in the helper and one routing line in the command that runs it.
- Units: (1) `lib/spec/spec-depth.sh` parses and checks the header line; (2) `commands/spec.md` step 1 decides the level, step 2 routes research by it; (3) `commands/spec-validate.md` Reviewer 4 checks the line both ways; (4) `commands/test-plan.md` and `commands/test-plan-review-team.md` pick the floor pass or the full team.

## Picture

```
 /kit:spec step 1 ---> decide Depth, write it under Lane: in the header
                            |
                            v
          lib/spec/spec-depth.sh level|wants|check   (reads the header only,
            /               |                  \      before the first "## ")
  standard           research (repo: X)      research (outside: X)
  0 research         4 brownfield agents     /kit:get-api-docs + one web pass
  agents             (step 2, Mode A/B)      (step 2)
            \               |                  /
             ledger: | ACTION | depth=<levels> research_agents=<N>
                            |
 spec-validate Reviewer 4:  deeper level, no named reason ........... CRITICAL
                            standard, but open questions or an
                            unsampled Grounding claim ............... CRITICAL
                            no Depth line on a new spec ............. CRITICAL
                            no Depth line on an older spec .......... warning
                            |
 /kit:test-plan ---> blind-spot (failure: Y)?
                      | no                               | yes
                      v                                  v
        test-plan-review-team --floor            test-plan-review-team
        Coverage + Oracle, one pass,             6 lenses, revise rounds (max 3)
        no revise rounds
                      \                                  /
                       `## Test plan critique` + verdict
                                   |
                     /kit:test-write needs SOLID (unchanged)
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Data model (the header line)

Written directly under `Lane:`, in the header (before the first `## ` heading):

```
Depth: standard (<why nothing deeper is needed>)
Depth: research (repo: <the unknown>)
Depth: research (outside: <the unknown>)
Depth: blind-spot (failure: <the failure mode>)
Depth: research (outside: <the unknown>) + blind-spot (failure: <the failure mode>)
```

- `research (repo: ...)`: a fact about this codebase the author cannot settle by reading the files in front of them or running one command. Turns on the 4 brownfield research agents.
- `research (outside: ...)`: a fact outside the repo (a provider's behavior, a library contract). Turns on `/kit:get-api-docs` for each named API plus one web research pass; it does not send the brownfield agents, which read only the repo.
- `blind-spot (failure: ...)`: a failure mode the author expects not to see alone. Turns on the full 6-lens test-plan review team with revise rounds. Without it, the test plan still gets the two-lens floor pass.
- A reason that only says the work matters (important, critical, risky, core, complex, sensitive, big) earns nothing deeper.
- A `Depth:` line anywhere after the first `## ` (for example inside a fenced example like the block above) is not the header and is ignored.

### Diagram

See `## Picture`.

### ADR link(s)

No lasting architecture decision beyond SPEC-368's ADR for the lighter default. The levels are described in `docs/WORKFLOW.md` next to the lane table.

### Boundaries & failure modes

Out of bounds: lanes and the lane data (SPEC-368); the validator itself, which runs on every spec at every depth; dispatch run-id tags (`feat/dispatch-rid-tag`). See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

`lib/spec/spec-depth.sh` (plus a one-line `depth` forwarder in `lib/spec/spec.sh`, whose job is forwarding only, `lib/spec/spec.sh:1-5`). All verbs read only the header: lines before the first line that starts with `## `.

| Verb | Output | Exit |
|---|---|---|
| `level <spec>` | the level set, space-separated: `standard`, or any of `research-repo`, `research-outside`, `blind-spot` | 0; no header line prints `standard` plus one stderr note |
| `wants <spec> <research-repo\|research-outside\|blind-spot>` | nothing | 0 when the header's levels include it; 1 otherwise, including when there is no header line |
| `check <spec>` | one line per problem | 0 clean; 1 on any problem below |

`check` problems:

- two `Depth:` lines in the header; an unknown level; a missing `repo:` / `outside:` / `failure:` prefix; an empty reason; a reason made only of importance words (after dropping stop words, every remaining word is in the list above);
- the inverse: level `standard` while the spec has a `## Open questions` section whose body is anything other than empty or a line starting `(none`, or a `## Grounding` section containing `cannot be sampled`;
- no header `Depth:` line on a NEW spec: its `Generated:` date is on or after `DEPTH_REQUIRED_FROM`, a constant in the helper set to the merge date at TASK-1, or it has no `Generated:` line. An older spec with no line gets one stderr warning and exit 0.

`commands/spec.md` records one ledger line after step 2: `bash lib/gate/gate-ledger.sh action <rid> "depth=<levels> research_agents=<N>"`.

`/kit:test-plan-review-team --floor`: one subagent runs lens 1 (Coverage completeness) and lens 2 (Oracle & falsifiability) in one pass, writes `## Test plan critique` with `Scope: floor (coverage + oracle)` and the usual verdict vocabulary, and runs no revise round (`commands/test-plan-review-team.md:27-28` are the lens texts, reused, not copied).

Invariants:

- The fresh-context validator runs on every spec at every depth.
- Every test plan gets a critique: the floor at `standard` and `research`, the full team at `blind-spot`. `/kit:test-write`'s SOLID rule (`commands/test-write.md:15-31`) is unchanged.
- `wants` never returns 0 for a spec with no header line, so an old spec dispatches no research.
- A manual full `/kit:test-plan-review-team` run is always allowed.

### Data model changes

None outside the header line.

### API changes

None.

### UI changes

`/kit:spec` step 1 asks one question when the level is not obvious: "Is there a fact you cannot settle from the code or one command, or a failure you expect not to see alone? If neither, depth is standard."

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: `lib/spec/spec-depth.sh` with `level`, `wants`, `check`, and the `depth` forwarder line in `lib/spec/spec.sh`. Fixtures under `tests/fixtures/spec-depth/`, including one spec whose body holds a fenced `Depth:` example after the first `## `. `tests/test-spec-depth.sh` covers every verb and fixture. AC: `bash tests/test-spec-depth.sh` passes.

### Phase 2: Core

- [ ] TASK-2: `commands/spec.md`. Template: `Depth:` line under `Lane:` (`:84-86`). Step 1: decide the level with the one question. Step 2 (`:21-66`): route by `spec-depth.sh wants`: `research-repo` sends Mode A/B; `research-outside` runs `/kit:get-api-docs` per named API plus one web research subagent writing `docs/research/<date>-<slug>-outside.md`; neither sends nothing. Record the `depth=` action line. Keep every `rid=<rid>` phrase `feat/dispatch-rid-tag` added (its paragraph containing ``include `rid=<rid>` `` and the step 2 dispatch lines). Step 4 design pass (`:274-281`): runs when `bash lib/gate/gate-ledger.sh plan <lane>` lists `design-critique` at either level it prints (`required` or `lite`), instead of naming the full lane; under SPEC-368's shipped data only `full` lists it, as `required`. AC: `bash tests/test-spec-depth.sh spec-md-wiring` passes.
- [ ] TASK-3: `commands/spec-validate.md` Reviewer 4 (`:44-56`): run `bash lib/spec/spec-depth.sh check <spec>`; exit 1 is CRITICAL. Lens questions, each CRITICAL when true: does a deeper level's reason name a real unknown or failure, or only importance? Does a `standard` spec name an unknown or a failure mode it cannot test alone anywhere in its text? AC: `grep -c 'spec-depth.sh check' commands/spec-validate.md` is at least 1, and validating the fixtures in the test plan returns the CRITICALs.
- [ ] TASK-4: Review routing. `commands/test-plan-review-team.md`: add the `--floor` mode (lenses 1 and 2, one pass, `Scope: floor` line, no revise loop). `commands/test-plan.md` step 4 (`:183-185`): next is `/kit:test-plan-review-team` when `wants ... blind-spot`, else `/kit:test-plan-review-team --floor`. AC: `bash tests/test-spec-depth.sh review-routing` passes.

### Phase 3: Polish

- [ ] TASK-5: `docs/WORKFLOW.md`: a short "Depth" paragraph after the lane table; the every-step review paragraph (`:330-333`) and its test-plan row (`:339`) say "the floor pass at every depth, the full team at blind-spot"; the cycle row (`:145`) and the command table row (`:1307`) name both modes. `docs/MANUAL.md` and `docs/architecture.md` rows the doc-projection check asks for; regenerate `docs/FEATURES.md`. AC: `bash lib/gate/doc-projection-check.sh .` and `bash lib/registry/feature-registry.sh check docs/FEATURES.md` pass.

## After state

- [ ] A new spec from `/kit:spec` carries a `Depth:` line under `Lane:`. (Today: no such line.)
- [ ] A brownfield spec with `Depth: standard` dispatches zero research agents, and its ledger has `depth=standard research_agents=0`. (Today: 4 agents on every brownfield spec.)
- [ ] A `standard` test plan gets one two-lens floor pass, not 6 lenses and up to 3 rounds. (Today: the full team is the only mode.)
- [ ] `bash lib/spec/spec-depth.sh check` exits 1 on `Depth: research (this is important)` and on a `standard` spec with open questions.

## Acceptance Criteria (global)

| # | Criterion | Command | Pass |
|---|---|---|---|
| AC1 | `level` parses every form from the header only | `bash tests/test-spec-depth.sh level` | each fixture prints its expected level set; the fenced-example fixture prints its header level, not the example's; no header line prints `standard` |
| AC2 | `check` rejects bad lines | `bash tests/test-spec-depth.sh check` | exit 1 for: empty reason, `research (this is important)`, `research (critical core change)`, missing prefix, unknown level, two header lines; exit 0 for `research (outside: the provider's retry schedule is not documented anywhere we have)` |
| AC3 | Inverse check | `bash tests/test-spec-depth.sh inverse` | exit 1 for `standard` with a non-empty `## Open questions`; exit 1 for `standard` with `cannot be sampled` in `## Grounding`; exit 0 for `standard` with `(none; ...)` |
| AC4 | KEEP: the rid-tag phrases survive the step 2 rewrite | ``grep -cF 'include `rid=<rid>`' commands/spec.md`` and `sed -n '/^### Step 2/,/^### Step 3/p' commands/spec.md \| grep -c 'rid=<rid>'` | `1` or more each (the first is the phrase `tests/test-meta.sh` asserts after `feat/dispatch-rid-tag`) |
| AC5 | Missing line: CRITICAL on new specs, warning on old | `bash tests/test-spec-depth.sh missing-line` | fixture with `Generated:` on or after `DEPTH_REQUIRED_FROM`: exit 1; older fixture: exit 0 plus warning |
| AC6 | Review routing by depth | `bash tests/test-spec-depth.sh review-routing` | test-plan.md step 4 names `--floor` for the default and the full team for `blind-spot`; test-plan-review-team.md documents `--floor` as lenses 1 and 2, one pass |
| AC7 | Default depth dispatches zero research agents (live run) | `/kit:spec` on a small brownfield task in this repo, then `bash lib/gate/gate-ledger.sh show <rid> \| grep 'depth=standard research_agents=0'` and `ls docs/research/ \| grep -c <slug>` | one match; `0` |
| AC8 | `wants` never fires without a header line | `bash lib/spec/spec-depth.sh wants tests/fixtures/spec-depth/no-depth.md research-repo; echo $?` | `1` |
| AC9 | No regressions | `bash tests/test-meta.sh && bash tests/test-hooks.sh && bash tests/test-spec-depth.sh` | all exit 0 |

## Verification

```bash
bash tests/test-spec-depth.sh
bash tests/test-meta.sh && bash tests/test-hooks.sh
```

Plus the one live `/kit:spec` run in AC7 and one floor pass on a seeded-gap plan, both recorded in `docs/verification/spec-depth-line/`.

## Test plan

Date: 2026-09-29

| Case | Kind | Covers | Proof |
|---|---|---|---|
| Brownfield spec with `Depth: standard` through `/kit:spec` | negative control (must send zero research agents) | AC7 | ledger `depth=standard research_agents=0`; no `docs/research/*-<slug>-*.md` |
| Same task with `Depth: research (repo: how the ledger substrate locks)` | positive | AC7 | ledger `depth=research-repo research_agents=4`; 4 research files |
| `--floor` pass on the seeded-gap plan from `docs/verification/test-plan-review-team.md:54-64` | negative control (the floor must still bite) | AC6 | critique carries CRITICAL for the uncovered AC and the missing negative control; verdict not SOLID |
| `--floor` pass on the good plan from the same record | positive | AC6 | no CRITICAL |
| `Depth: research (this is important)` | negative control (importance is not the test) | AC2 | `check` exit 1 |
| `standard` spec with a real open question | negative control (inverse check) | AC3 | `check` exit 1 |
| Spec whose body has a fenced `Depth: blind-spot (...)` example and a header `Depth: standard (...)` | negative control (body must not parse) | AC1 | `level` prints `standard` |
| New spec with no `Depth:` line | negative control | AC5 | `check` exit 1 |
| Older spec with no `Depth:` line | positive (grace period) | AC5 | `check` exit 0 plus warning; `wants` exit 1 |
| Validator run on the `research (this is important)` fixture | negative control (validator rejects) | TASK-3 | Reviewer 4 CRITICAL; merged verdict NEEDS REVISION |
| `commands/spec.md` after the rewrite | KEEP control | AC4 | both greps at least 1; `bash tests/test-meta.sh` green |

Dry trace for the key negative control (AC7): step 1 writes `Depth: standard (...)`; step 2 calls `spec-depth.sh wants <spec> research-repo` (exit 1) and `wants ... research-outside` (exit 1), so no Agent call is made; the step records `depth=standard research_agents=0`. Reverting step 2 to the unconditional brownfield rule makes the ledger read `research_agents=4` and 4 files appear, which turns the check red.

## Edge Cases

1. The writer does not know the depth until research would have told it: that is itself a `research (repo: ...)` reason.
2. A greenfield spec with `research (repo: ...)`: nothing to research in the repo; step 2 skips as today (`commands/spec.md:64`) and records `research_agents=0`.
3. The research agents are not installed: Mode B inline prompts, unchanged (`commands/spec.md:36-58`).
4. `/kit:get-api-docs` has no entry for the named API: the web pass alone runs, and the research file says so.
5. A reason mixing importance words with a real unknown ("critical: provider retry schedule undocumented"): passes `check`; Reviewer 4's lens judges it.
6. A spec validated before this change: the grace period applies (no line = warning); its existing critique, if any, still satisfies `/kit:test-write`.
7. A floor verdict of REVISE: the author fixes the plan and reruns the floor; there is no automatic revise loop at this depth.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Authors write `standard` on work that needed research | SPEC-367 escape records with `gap: context`; the inverse check catches the visible cases | Tune the step 1 question on measured misses |
| Authors write a fake reason to get deeper planning | Reviewer 4 lens; the ceremony share in SPEC-367 | The reason is visible in the header |
| Test-plan gaps only lenses 3 to 6 would catch ship at `standard` | Escapes tagged `gap: judgment` | `blind-spot` on the next similar spec; code review still runs |
| `DEPTH_REQUIRED_FROM` set wrong | Old specs fail `check`, or new ones slip the grace period | One constant, pinned by `tests/test-spec-depth.sh missing-line` |

## Migration notes (existing adopted repos)

- Specs that predate `DEPTH_REQUIRED_FROM` have no `Depth:` line and count as `standard`: no research dispatch on re-run, and the validator warns instead of blocking. New specs need the line.
- Repos that relied on the automatic 4-agent brownfield research now get it only with `research (repo: ...)`.
- Test plans get the two-lens floor by default. A repo that wants the full team on every plan runs it by hand or writes `blind-spot`.

## Out of Scope

- Lanes, lane data, the light default, and the diff floor (SPEC-368).
- Changing the validator (still one fresh-context pass per spec, every depth).
- Run-id tags on dispatch descriptions (`feat/dispatch-rid-tag`); this spec only keeps them intact.
- `commands/test-write.md` and `commands/assign.md`: no change needed.
- `commands/execute.md` (SPEC-369).

## Touches

Single files (serialized by the dispatch gate against any sibling that lists them): `lib/spec/spec-depth.sh` (new), `lib/spec/spec.sh` (one forwarder line), `commands/spec.md`, `commands/spec-validate.md`, `commands/test-plan.md`, `commands/test-plan-review-team.md`, `docs/WORKFLOW.md`, `docs/MANUAL.md`, `docs/architecture.md`, `docs/FEATURES.md`, `tests/test-spec-depth.sh`.

- tests/fixtures/spec-depth/**
- docs/verification/spec-depth-line/**

## Siblings

| Spec or branch | Relation |
|---|---|
| `feat/dispatch-rid-tag` | Lands FIRST. Owns the `rid=<rid>` convention in `commands/spec.md` and `commands/execute.md`, and the `tests/test-meta.sh` assertion on ``include `rid=<rid>` ``. This spec rebases on it and keeps those phrases (AC4) |
| SPEC-368 lanes-as-data | Split from it; lands before this spec. Both edit `docs/WORKFLOW.md`, `docs/MANUAL.md`, `docs/architecture.md`, `docs/FEATURES.md`. The step 4 design-pass line reads `gate-ledger.sh plan`, which works before and after SPEC-368 |
| SPEC-367 ceremony-lens | Reads the `depth=... research_agents=` action lines this spec emits. No shared files |
| SPEC-369 whole-spec-dispatch | Owns `commands/execute.md` and also edits files under `lib/spec/`. This spec touches only `lib/spec/spec-depth.sh` (new) and one forwarder line in `lib/spec/spec.sh`; if SPEC-369 also edits `spec.sh`, the second to land rebases |
| SPEC-366 execution-view, SPEC-370 orca-mega-backend, SPEC-371 adopt-pointer-onboarding | No shared files |

## Decision Log

- DEC-1: Plain level names, not P0 to P4 (plain-words rule).
- DEC-2: `research` splits into `repo:` and `outside:` (operator decision): the brownfield agents read only the repo, so an outside unknown routes to `/kit:get-api-docs` plus a web pass.
- DEC-3: A missing `Depth:` line is CRITICAL on new specs and a warning only on specs that predate the change (operator decision).
- DEC-4: The importance-word check is mechanical only for reasons made of nothing else; mixed reasons go to the lens. Rejected: a longer banned-word list (it would reject honest reasons).
- DEC-5: `standard` keeps a floor review, lenses 1 and 2 in one pass, because those two have a measured bite (operator decision). Rejected: no review at `standard` (5 of 7 critiques found a CRITICAL).
- DEC-6: The inverse check (a `standard` spec that names an unknown or an untestable failure is CRITICAL) runs both mechanically and as a lens (operator decision).
- DEC-7: Parse the header only, before the first `## `, so examples in the body never count.

## Grounding

- `commands/spec.md` step 2 today dispatches all 4 research agents on any brownfield spec: `sed -n 21,34p commands/spec.md` ("If modifying existing code, run codebase research before generating the spec ... dispatch all 4").
- Test-plan critiques in the repo: `grep -l '^## Test plan critique' docs/specs/*.md` lists SPEC-052, 204, 208, 209, 210, 211, 212 (7). Round-1 findings on all 7 and a CRITICAL on 5 (052, 208, 210, 211, 212) is the coordinator's count from the critique sections.
- The floor lenses bite: `docs/verification/test-plan-review-team.md:37` records the R3 negative control "dispatch Coverage + Oracle lenses on a seeded-gap `## Test plan`" as "RED-as-expected (both CRITICAL, 2/10)".
- The rid phrase to keep: the uncommitted diff in the `dispatch-rid-tag` worktree adds `grep -qF 'include `rid=<rid>`' "$KIT_DIR/commands/$F.md"` to `tests/test-meta.sh` for `execute` and `spec`.
- Lane of this spec: `bash lib/classify/lane-classify.sh explain --files "lib/spec/spec-depth.sh lib/spec/spec.sh commands/spec.md" "<summary>"` returns `full`, flag `kit-machinery`. Text alone returns `normal`. It also narrows a default review, so `full` stands.

## Open questions

(none; the operator decided research routing, the floor review, the inverse check, the grace period, and the rid-tag ownership)
