# Spec: skills/loop-engineering/SKILL.md contract (backfill)
Generated: 2026-07-31
Status: DRAFT (reverse-engineered)

Backfill item 2/6 of the ID-452 campaign. The feature is a prompt-file skill; its observable behavior IS its body. The acceptance criteria below pin the load-bearing claims of `skills/loop-engineering/SKILL.md` as it exists today, cross-checked against its design record `docs/research/2026-07-30-loop-engine-prior-art.md`. Process deviation, stated honestly: the `/kit:test-plan` Step 0 `kit:research-features` dispatch was skipped, per the item-1 (SPEC-208) precedent; the surface is one file, read directly, and a researcher dispatch adds no observation the file does not already contain.

## Acceptance Criteria
- [ ] AC-1: Frontmatter names the skill `loop-engineering`, keeps model invocation enabled (`disable-model-invocation: false`), carries the Karpathy/autoresearch/hill-climb/search-and-select trigger phrases, and the description scopes OUT one-off Stop-hook goals (goal-craft), the debug loop (/kit:debug), and building the loop's actual code.
- [ ] AC-2: Step 1 gates on four criteria, each present as its own bolded rule: bounded-in-session only, serves 2+ lifecycle phases, explainable in one sentence, has a source citation; failing any means the idea is not a loop and falls back to a one-shot side-flow.
- [ ] AC-3: Step 2 offers exactly three shapes (bounded-revise engine, campaign/worklist, bounded search-select) and routes by the ONE-thing / MANY-things / BEST-VARIANT question.
- [ ] AC-4: The engine parameterizes three things (artifact, N scanners, reviser) and the reviser must be distinct from every scanner.
- [ ] AC-5: The convergence rule is severity-aware: it tracks severity, not raw count, and a flat K still counts as progress if the worst severity dropped.
- [ ] AC-6: The engine's scan step is two-tier: Tier 1 deterministic (grep/bash, zero model cost) runs every round and decides on its own; Tier 2 model critique dispatches only for the residual Tier 1 cannot reduce, skipping lenses Tier 1 already cleared; the stop condition requires Tier 1 all clean.
- [ ] AC-7: The campaign shape is not a new engine: it wraps an existing loop over a worklist of untreated items, stops when the worklist runs out or a budget or blocker hits, reuses the Goal loop's own shape, and forbids building a second convergence mechanic; the audit flavor points to `docs/patterns/audit-loop.md`.
- [ ] AC-8: Search-select requires all three preconditions (cheap unambiguous numeric metric; evaluation fast enough for many shots, with the Karpathy budget math; losers carry no information the next attempt needs) and mandates two adaptations: a fixed iteration budget and an honest-halt report.
- [ ] AC-9: The lineage section cites Evaluator-Optimizer for the shape, explicitly does not claim the shape is new, concedes artifact-agnostic parameterization is inherited, and names the three kit-added deltas (severity-aware convergence; distinct reviser, never a scorer; hard cap with honest-halt) as the real contribution.

## Test plan
Date: 2026-07-31 (revised once after the round-1 critique)
Source: this spec's ## Acceptance Criteria. Dialect: doc/prompt-file contract (the standard's doc dialect: pin the claims with grep assertions, prove falsifiability with a negative control). All proofs run from the repo root; `S=skills/loop-engineering/SKILL.md`. The SKILL body is hard-wrapped at ~100 columns, so several pins target single-physical-line fragments of a wrapped sentence; where one claim spans two lines, the row pins both fragments with `&&`. Rows 1-27 are deterministic reads (grep on the tracked file, or on a mktemp scratch copy that is never the tracked file): no network, no clock, no ordering. Row 28 is the one deliberate exception, a one-time recorded mutation with a byte-identity restore.

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | frontmatter name pinned | happy-path | AC-1 | first frontmatter block contains `name: loop-engineering` | `awk '/^---$/{c++;next} c==1' $S \| grep -qx 'name: loop-engineering'` |
| 2 | goal-craft scope-out | boundary | AC-1 | `NOT for a one-off in-session Stop-hook goal (use goal-craft)` | `grep -qF 'NOT for a one-off in-session Stop-hook goal (use goal-craft)' $S` |
| 3 | debug-loop scope-out | boundary | AC-1 | `NOT for the debug loop (already exists, use /kit:debug)` | `grep -qF 'NOT for the debug loop (already exists, use /kit:debug)' $S` |
| 4 | build-the-code scope-out | boundary | AC-1 | `NOT for building the loop's actual code` | `grep -qF "NOT for building the loop's actual code" $S` |
| 5 | gate: bounded-in-session | happy-path | AC-2 | bolded rule `**Bounded-in-session only.**` present | `grep -qF '**Bounded-in-session only.**' $S` |
| 6 | gate: serves 2+ phases | happy-path | AC-2 | bolded rule `**Serves 2+ lifecycle phases.**` present | `grep -qF '**Serves 2+ lifecycle phases.**' $S` |
| 7 | gate: one sentence | happy-path | AC-2 | bolded rule `**Explainable in one sentence.**` present | `grep -qF '**Explainable in one sentence.**' $S` |
| 8 | gate: source citation | happy-path | AC-2 | bolded rule `**Has a source citation.**` present | `grep -qF '**Has a source citation.**' $S` |
| 9 | gate fail path | boundary | AC-2 | fail means not-a-loop, side-flow fallback | `grep -qF 'If any of these fail, the idea is not a loop.' $S && grep -qF 'A side-flow is simpler and does not need this skill.' $S` |
| 10 | three shape headings | happy-path | AC-3 | all three bolded shape names present | `grep -qF '**Bounded-revise engine.**' $S && grep -qF '**Campaign / worklist iteration.**' $S && grep -qF '**Bounded search-select.**' $S` |
| 11 | routing question | happy-path | AC-3 | ONE / MANY / BEST-VARIANT routing fragments (wrapped sentence, three line-fragments) | `grep -qF 'does the loop make ONE thing' $S && grep -qF 'check MANY existing things (campaign' $S && grep -qF 'BEST VARIANT of one thing (search-select)?' $S` |
| 12 | engine parameterization | happy-path | AC-4 | `Parameterize three things: the artifact, who scans it (N lenses), and who revises it.` | `grep -qF 'Parameterize three things: the artifact, who scans it (N lenses), and who revises it.' $S` |
| 13 | distinct reviser | security/safety | AC-4 | `reviser must be distinct from every scanner` | `grep -qF 'reviser must be distinct from every scanner' $S` |
| 14 | severity-aware rule (Step 2 wording) | happy-path | AC-5 | tracks severity not raw count, flat K = progress if worst severity dropped (wrapped, two fragments) | `grep -qF 'convergence rule tracks severity, not raw' $S && grep -qF 'A flat K still counts as progress if the worst severity dropped.' $S` |
| 15 | honest-halt in the engine diagram | boundary | AC-5 | diagram carries `halt honestly`, the hard cap value `(cap 3)`, and the three-way verdict | `grep -qF 'halt honestly' $S && grep -qF 'round += 1 (cap 3)' $S && grep -qF 'verdict: SOLID / REVISE / RECONSIDER' $S` |
| 16 | two-tier declaration | happy-path | AC-6 | `The scan step runs in two tiers. It does not dispatch all N lenses every round.` | `grep -qF 'The scan step runs in two tiers. It does not dispatch all N lenses every round.' $S` |
| 17 | Tier 1 contract | happy-path | AC-6 | deterministic, zero model cost, every round, decides alone | `grep -qF 'Tier 1 runs a deterministic check: grep or bash, zero model cost.' $S && grep -qF 'Tier 1 runs every round and decides on its own.' $S` |
| 18 | Tier 2 residual-only | boundary | AC-6 | dispatch only for what Tier 1 cannot reduce; skip cleared lenses (wrapped, two fragments) | `grep -qF 'Dispatch it only for the criteria Tier 1 cannot reduce' $S && grep -qF 'finding-space Tier 1 already cleared.' $S` |
| 19 | two-tier stop condition | boundary | AC-6 | the full wrapped stop-condition sentence, both physical lines, including the round-cap clause | `grep -qF 'The stop condition becomes: Tier 1 is all clean, and Tier 2 hits K=0, or its severity drops,' $S && grep -qF 'or the round cap hits.' $S` |
| 20 | campaign wraps, never a second engine | security/safety | AC-7 | not-a-new-engine + Goal-loop reuse + no second convergence mechanic (wrapped fragments) | `grep -qF 'It is not a new engine. It wraps an existing one.' $S && grep -qF "This reuses the Goal loop's own shape" $S && grep -qF 'Do not build a second convergence' $S && grep -qF 'mechanic. Reuse the Goal loop.' $S` |
| 21 | audit flavor pointer | boundary | AC-7 | campaign's audit flavor points at the audit-loop pattern doc | `grep -qF 'docs/patterns/audit-loop.md' $S` |
| 22 | search-select preconditions | happy-path | AC-8 | the all-three-must-hold clause plus each named precondition, with the budget math | `grep -qF 'All three preconditions must hold, or this shape is wrong:' $S && grep -qF 'A cheap, unambiguous numeric metric exists.' $S && grep -qF 'Evaluation is fast enough to afford many shots.' $S && grep -qF 'minutes per experiment, about 100 overnight.' $S && grep -qF 'Losers carry no information the next attempt needs.' $S` |
| 23 | mandatory adaptations | security/safety | AC-8 | fixed budget + honest-halt, stated as mandatory (wrapped, two fragments) | `grep -qF 'Two adaptations are mandatory' $S && grep -qF 'budget (never "loop forever until interrupted"), and an honest-halt report at the end, what' $S` |
| 24 | lineage claim structure | happy-path | AC-9 | cite E-O, no novelty claim, inherited parameterization conceded, three delta bullets named, and the Lineage's own restatement of the severity delta (`A flat finding-count still counts`, deliberately distinct wording from row 14's Step-2 pin) | `grep -qF 'Cite Evaluator-Optimizer for the shape. Do not claim the shape itself is new.' $S && grep -qF 'kit did not invent it.' $S && grep -qF '**Severity-aware convergence.**' $S && grep -qF 'A flat finding-count still counts as progress if the worst' $S && grep -qF '**Distinct reviser, never a scorer.**' $S && grep -qF '**Hard cap with an honest-halt reporting path.**' $S && grep -qF 'above are the real contribution.' $S` |
| 25 | frontmatter invocation contract | boundary | AC-1 | model invocation stays enabled and the Karpathy-family trigger phrases are present | `grep -qx 'disable-model-invocation: false' $S && grep -qF 'Karpathy loop / autoresearch / hill-climb / search-and-select' $S` |
| 26 | campaign worklist mechanics | happy-path | AC-7 | worklist shape + its stop condition (wrapped, two fragments) | `grep -qF 'Shape: build a worklist of untreated items.' $S && grep -qF 'Stop when the worklist runs out, or a budget or blocker hits.' $S` |
| 27 | in-suite negative control (permanent, scratch copy) | falsifiability | AC-5 | on a mktemp COPY of `$S` with the sentence `A flat K still counts as progress if the worst severity dropped.` stripped (substring removal, tracked file untouched), row 14's second fragment FAILS while row 14's first fragment (previous physical line), row 13's pin (same physical line as row 14's first fragment), and row 24's `A flat finding-count` pin (different wording) all still PASS on the copy: proves the pins discriminate at sub-line and sub-wording granularity; EXIT-trap cleanup | inside the test script: mktemp scratch copy + sed substring strip + `! grep -qF` on the stripped fragment + `grep -qF` on the three surviving neighbors |
| 28 | live negative control (one-time, recorded) | falsifiability | AC-5 | strip ONLY that sentence (substring removal) from the tracked `$S`, run `bash tests/test-loop-engineering-contract.sh`, expect EXACTLY this flip set: row 14 RED (its second fragment gone) plus the in-suite NC setup assertion RED (nothing left to strip on the copy it derives, a named, predicted side effect); row 14's first fragment, row 13, and row 24 (now pinning the differently-worded `A flat finding-count` restatement, so its survival is a real discrimination, not a vacuous non-test) all stay GREEN; restore, prove byte-identity via truncated sha256 + re-derive command, re-run green | recorded with both transcripts in `docs/verification/backfill-loop-engineering.md` |

### Coverage notes
- Every AC maps to at least one row and every row back to an AC; no orphans. Failure-injection is honestly thin: the subject is a static prompt file, so the only injectable failure is content drift, which IS rows 27-28.
- Skill registration in the plugin manifest is NOT re-pinned here; `tests/test-meta.sh` owns skill/frontmatter structural sweeps.
- Exact-string pins are by design: the tested contract is the prose itself. A legitimate rewording is EXPECTED to break the matching row; the failure is the prompt to re-verify the contract survived the rewording (same stance as SPEC-208 and `tests/test-test-writer-contract.sh`). Because the body hard-wraps, every multi-word pin is wrap-fragile in principle: rows 11, 14, 18, 19, 20, 23, 26 are split across lines TODAY, and the round-1 critique proved by reflow simulation that a narrower re-wrap (85 columns) also breaks rows 9, 12, 17. The list is a snapshot, not exhaustive; frontmatter pins (rows 1-4, 25) assume the frontmatter is never re-flowed. Accepted; the re-verify cost is one grep fix per broken row.
- Adjacency hazard, named per the SPEC-208 precedent: row 13's pin and row 14's first fragment share one physical line of the SKILL body. Any future line-deletion-style negative control on AC-4 or AC-5 must strip a substring, never the whole line, or it flips both rows.
- Step 3 (where a shaped loop lands), the "How it fires" convenience note, and the Reference section are deliberately unpinned: routing conveniences by this spec's own judgment (the design record does not discuss them). The search-select base mutate/score/keep/discard sentence is also unpinned: the three preconditions of row 22 gate the same behavior; accepted LOW trade-off.

## Test plan critique
Date: 2026-07-31
Spec: SPEC-209
Lenses run: Coverage completeness, Oracle & falsifiability, Determinism & maintainability (3 of the standard 6, dispatched as parallel read-only subagents). Skipped, honestly: Feasibility & reproducibility (every proof is a pasteable one-liner), Test-ladder & boundary depth (the ladder collapses for a static-file subject), Tiering & floor (N/A: no Tier column, no model call in scope). Same ID-452 calibrated-cost triage as SPEC-208, stated rather than hidden.

Rounds:
- [[QL-VERDICT round=1 clean=false findings=13]]
- [[QL-VERDICT round=2 clean=false findings=3]]

Round 1 (full 3-lens dispatch) returned 13 deduplicated findings: 0 CRITICAL, 3 HIGH, 4 MEDIUM, 6 LOW. One revision was applied (the matrix above). Round 2 was NOT a fresh lens dispatch: it was a narrow mechanical re-check by the coordinator, every new grep run live against the real file with occurrence counts (all 1), and the negative-control blast radius re-simulated on a scratch copy with the new row-24 pin in place. Recorded as the confirmation path used, per this lane's narrow-re-check allowance. K fell 13 to 3 and max severity fell HIGH to LOW; the 3 remaining are accepted LOW trade-offs, so the loop stops.

### High findings
1. The intro prose mislabeled the exception row ("Rows 1-24 ... Row 25 is the one deliberate exception") while the matrix's live-mutation row is the last one; a suite author following the prose could misplace the mutation logic (determinism lens) -- fix: prose renumbered to rows 1-27 deterministic, row 28 the exception -- resolved in round 1.
2. Row 28's Expected overclaimed discrimination: it cited row 24 staying green on the `A flat finding-count` restatement, but row 24 never pinned that sentence, so its survival was vacuous, not discriminating (oracle lens) -- fix: row 24 now pins the restatement fragment; the in-suite NC (row 27) asserts its survival too -- resolved in round 1.
3. The frontmatter's invocation mechanism was unpinned: neither `disable-model-invocation: false` nor the Karpathy-family trigger phrases had a row, so the one boolean that decides whether the body ever runs unprompted could flip silently (coverage lens) -- fix: AC-1 extended + row 25 -- resolved in round 1.

### Medium findings
1. The hard round-cap value 3 was never pinned as a number, and row 19 dropped the wrapped stop-condition's round-cap clause -- fix: row 15 pins `round += 1 (cap 3)`, row 19 pins both fragments -- resolved in round 1.
2. Campaign mechanics (worklist shape, its stop condition) were entirely unpinned while the engine's equivalents had 8 rows -- fix: AC-7 extended + row 26 -- resolved in round 1.
3. The wrap-fragility list was a snapshot presented as closed; reflow simulation at 85 columns also broke rows 9, 12, 17 -- fix: coverage note reworded to non-exhaustive, with the simulated extra breakage named -- resolved in round 1.
4. Rows 27-28's artifacts (`tests/test-loop-engineering-contract.sh`, the verification doc) did not exist at critique time -- true by pipeline position (critique precedes materialization in SPEC-203); resolved at the materialization + verification steps.

### Low findings
1. Row-13/row-14 physical-line adjacency (the SPEC-208 CRITICAL class) was undocumented -- fix: named in coverage notes -- resolved in round 1.
2. The escaped-pipe boilerplate sentence never fired (no proof cell contains a literal pipe) -- fix: sentence removed -- resolved in round 1.
3. The Step-3 exclusion was misattributed to the design record, which never discusses Step 3 -- fix: reworded to this spec's own judgment -- resolved in round 1.
4. Search-select's base mutate/score/keep/discard sentence and the autoresearch citation link are unpinned -- accepted: row 22's preconditions gate the same behavior; documented in coverage notes -- OPEN as accepted.
5. "How it fires" (no-slash-command invocation) is unpinned -- accepted routing convenience, documented -- OPEN as accepted.
6. Frontmatter pins assume the frontmatter is never re-flowed -- accepted, one clause added to coverage notes -- OPEN as accepted.

### Scores (final round)
- Coverage completeness: 9/10
- Oracle & falsifiability: 9/10
- Determinism & maintainability: 9/10

### Verdict: SOLID
