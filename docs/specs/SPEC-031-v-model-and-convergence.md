# Spec: V-model lifecycle lens + lead-owned convergence contract (ID-034)
Generated: 2026-05-22
Status: SHIPPED

> Implements backlog **ID-034** (I2 initiative). Build-first half of the
> `docs/specs/DECISION-BRIEF.md` pair; **ID-035** (parallel dispatch) rides on the
> contract this spec defines. Source of record: that brief +
> `docs/research/2026-05-22-concurrent-goal-dispatch.md`. Research backing this
> spec: `docs/research/{features,architecture,pitfalls}.md` (2026-05-22).

## Problem

Two real holes, one frame conflict.

1. **The kit has a lifecycle but no V.** WORKFLOW.md's cycle table lists phases and
   their enforcers, but nothing states the *mirror*: which definition phase each
   verification phase answers. Without the mirror made explicit, gaps hide. Two
   define-phases ship today with **no verification counterpart at all**: the brief
   (`/kit:think`) and the requirement (`/kit:assign`). Nothing checks "does the
   shipped thing actually solve the pain the brief named" except a narrative retro.

2. **Shared-surface writes have no owner.** When work fans out (ID-035) or even when
   the lead runs goals one at a time, the surfaces every change touches (`CHANGELOG`,
   `VERSION`, `plugin.json`, `tool.toml`, `tests/test-meta.sh`, `_meta/BACKLOG.md`)
   are integrated procedurally at `/kit:ship`, but no contract says *workers must not
   touch them* and *the lead integrates them once*. ID-035's disjointness gate needs
   that hands-off list to exist before it can exclude shared surfaces from its check.

3. **The "8 phases" frame is now wrong.** PHILOSOPHY and kit-health hard-code "8
   workflow phases." The V-model phase set is larger, and the feature-rejection
   criterion #2 ("serves fewer than 2 of the 8 phases") will mis-fire against the new
   framing. This is conflict **C2** from the backlog.

## Solution

<!-- Depth pattern forked from superpowers:brainstorming. See docs/specs/SPEC-008. -->

### Approaches considered

1. **Contract + lens overlay (chosen).** Define the V-model as a *lens over the
   existing cycle table* (not a new table), fill the named mirror gaps by mapping
   them to existing affordances, and add a narrowly-scoped convergence contract. Adds
   no commands, no executor. Tradeoff: pure-contract work is easy to under-build into
   prose nobody enforces; mitigated by test-meta.sh assertions.
2. **New per-phase commands (rejected).** Build `/kit:requirement-validate`,
   `/kit:converge`, etc. Tradeoff: violates "every file justifies its existence,"
   adds surface for a frame that already has 20 commands, and the relabel critique
   becomes a build-more critique. Rejected.
3. **Fold everything into ID-035 (rejected).** Skip ID-034, define the contract
   inside the dispatch spec. Tradeoff: couples the trust contract to the execution
   mechanism so neither can be reasoned about alone, and the build-order (contract
   first) is lost. Rejected; the brief is explicit that ID-034 is the moat ID-035
   rides on.

### Chosen approach + why

Approach 1. The kit already owns the lifecycle, the verification pipeline, the ship
gate, and the integration-checker. ID-034's honest job is **structural, not
mechanical**: name the mirror, fill the gaps with existing affordances, enumerate the
hands-off list, and scope convergence so it does NOT re-implement
`/kit:ship` (the shared-surface write) or the `integration-checker` (cross-task
wiring). What is genuinely new and does not exist today: the V-model lens section,
the lane×phase depth matrix, the single enumerated hands-off shared-surface list, the
convergence-scoping contract, and the C2 ADR. Everything else is reference or reword.

### Extensibility & boundaries

- **Load-bearing dimension = number of lifecycle phases / verification mirrors.** When
  a new phase or verifier is added (e.g. a future security-design arm), the V-model
  lens gains one define↔verify row and the inventory table one entry; the test-meta
  parity check forces both to move together. No structural rewrite.
- **Unit boundaries.** Four independent deliverables, each testable alone: (a) the C2
  reword (string absence), (b) the V-model lens (section presence + phase coverage),
  (c) the lane×phase matrix (cell completeness), (d) the convergence contract
  (hands-off list ⊆ doc-impact map). None depends on ID-035 existing; the contract is
  written for a future dispatcher to obey and is already true for the
  one-goal-at-a-time lead.

### Architecture (the V)

```
DEFINE (left arm)                                   VERIFY (right arm)
                                                                        solves the pain?
 Brief / Requirement  ═══════════════════════════  Acceptance         ship gate + retro
 (/kit:think,/kit:assign)        ▲ GAP TODAY ▲      (acceptance criteria trace the brief)
                                                                        parts connect?
   Solution-design  ═══════════════════════════  Integration          integration-checker,
   (/kit:design, devs-team)                       + code review        /kit:review(-team)
                                                                        each task correct?
     Test-design  ═════════════════════════════  Unit / task          task-verifier,
     (/kit:test-plan)                              + test-exec         test execution
                                                                        docs match code?
       (UI-design ══ visual-team, opt-in arm)      Docs                doc-verifier
                                                                  ▲
                          Code  ◄───── bottom of the V ──────────┘
                       (/kit:execute, /kit:next)

CONVERGENCE (lead-owned, once, after all workers): integrate the hands-off shared
surfaces via /kit:ship. Workers never write them. Cross-task wiring stays the
integration-checker's job; the actual write stays /kit:ship's. Convergence only
collates branch-ready/blocker signals and enforces the hands-off list.
```

## Technical Design

### Interfaces (I/O contract)

- **Consumes:** WORKFLOW.md cycle table (the phases this lens overlays); the
  doc-impact map "any shipped change" row + "Version surfaces" note (the source of
  the hands-off list); the live `commands/` and `agents/` inventory (the source of
  the phase-mapping table).
- **Produces:**
  - A `## The V-model lens` section + `## Lead-owned convergence` section + lane×phase
    depth matrix in `WORKFLOW.md`.
  - A command/skill/agent → V-phase inventory table in `docs/architecture.md`.
  - `docs/decisions/0018-v-model-phase-frame.md` (C2).
  - The **hands-off shared-surface list** as a named, enumerated artifact (the
    contract ID-035's disjointness gate imports).
  - test-meta.sh assertions guarding all of the above.
- **Invariants** (what a future change cannot break):
  - The hands-off list is a SUBSET of the doc-impact map's shared-surface rows. If a
    new shared surface is added to the doc-impact map, it must be added to the
    hands-off list (test enforces the direction: every hands-off entry exists in the
    map).
  - Convergence never writes a shared surface itself and never re-checks cross-task
    wiring; it delegates to `/kit:ship` and `integration-checker` respectively.
  - No hard phase gate is introduced; completeness stays warn+log (PHILOSOPHY
    "Detect, don't dictate").
  - The V-model lens references the cycle table's phase names rather than re-listing
    them. Where the lens adds structure the cycle table does not carry (the
    define↔verify mirror, plus any define-arm or opt-in phase not enumerated as a cycle
    row), that is the lens's own contribution, not a competing phase list. "No
    restatement" is enforced by coverage (TASK-007b); there is no absence-of-duplication
    test (DEC-007).

### Data model changes
None. No new state, no new files of record beyond the ADR and the spec. The
hands-off list is a documented enumeration in WORKFLOW.md, not a runtime structure.

### API changes
None. No new commands, no new agents, no new hooks. (If spec-validate or execute
prompts need a one-line pointer to the convergence contract, that is a doc edit, not
a new interface.)

### UI changes
None (the kit has no UI; the downstream-lane carve-out does not apply here).

### Infrastructure changes
None. Bash + markdown only.

## Task Breakdown

### Phase 1: Frame (C2)
- [x] TASK-001: Write `docs/decisions/0018-v-model-phase-frame.md`. Record: the kit's
  lifecycle is now described as a V-model phase set (define arm / verify arm / build),
  the V-model is a *lens over* the existing cycle, not a replacement; reword rationale
  for criterion #2., AC: ADR exists, follows the 0001-0016 format (Context/Decision/
  Consequences), cross-referenced from README + `docs/architecture.md`. **DONE** (commit bce00da, verified).
- [x] TASK-002: Reword every LIVE "8 phases" occurrence in sync, matched by string not
  line number (numbers rot): `docs/PHILOSOPHY.md` ("Shallow and wide" principle, "8
  lifecycle phases"), `docs/PHILOSOPHY.md` (rejection criterion #2, "8 workflow
  phases"), `commands/kit-health.md` (reject-list item 4), and
  `docs/specs/SPEC-007-internal-absorption-lane.md`,
  `docs/specs/SPEC-004-absorption-cadence.md`, and
  `docs/specs/SPEC-003-orchestration-layer.md` (the absorption-gate citation, "2+ of the
  8 phases" / "all 8 phases"). Replace hard counts with count-agnostic / V-model phrasing
  ("fewer than 2 lifecycle phases"). **The `docs/specs/`, `docs/decisions/`, and
  `docs/research/` archive is EXCLUDED from the absence check** (specs quote the old
  frame in problem statements + task text, ADRs record it as the superseded decision,
  research notes catalog it as a dated snapshot; chasing the string there destroys their
  purpose, see AMEND-001). The SPEC-003/004/007 rewords above are consistency edits to
  live citations, not part of the absence grep., AC: no `8 (workflow|lifecycle )?phases`
  string remains in the live OPERATING surfaces (`docs/PHILOSOPHY.md`,
  `docs/architecture.md`, `commands/`, `WORKFLOW.md`, `README.md`, `MANUAL.md`,
  `AGENTS.md`); criterion #2 and kit-health #4 still express the same 2+-phase rule;
  test-meta guards the operating-surface absence. **DONE** (commits cef3dfd + 75e0703, verified; AC amended per AMEND-001).

### Phase 2: The lens
- [x] TASK-003 (DONE 3f3b04d, verified): Add `## The V-model lens` to WORKFLOW.md, directly after the cycle
  table. Each define↔verify pair, the build at the bottom, and each pair's enforcer.
  Explicitly name the two mirror gaps (brief, requirement) and state how they are
  covered TODAY: the ship gate's acceptance criteria must trace the brief's user pain,
  and retro is the narrative mirror. No new command is proposed to fill them., AC:
  section exists; every phase in the cycle table appears in the lens; the section
  references the cycle table rather than restating the phase list.
- [x] TASK-004 (DONE 124b9bc, verified): Add the lane×phase depth matrix to WORKFLOW.md (rows = task types
  update-doc / bug-fix / vague / full mapped onto the existing tiny/normal/full/bug/
  backfill lanes; columns = V-model phases; each cell = measure-twice / run-lite /
  skip)., AC: matrix covers every lane × every define-and-verify phase; every cell
  is one of the three depths; the existing lane table is cross-referenced, not
  duplicated.
- [x] TASK-005 (DONE 46416a9, verified): Add the command/skill/agent → V-phase inventory table to
  `docs/architecture.md` (each entry in `commands/` and `agents/` mapped to its phase
  + arm: define / build / verify)., AC: every current command and agent appears
  exactly once; the table's count matches the live inventory (the parity TEST is added
  by TASK-007d, not here).

### Phase 3: Convergence contract + guards
- [x] TASK-006 (DONE 8df8289, verified): Add `## Lead-owned convergence` to WORKFLOW.md. Define: (a) the
  enumerated **hands-off shared-surface list** (workers must not write:
  `CHANGELOG.md`, `VERSION`, `.claude-plugin/plugin.json`, `tool.toml`,
  `tests/test-meta.sh`, `_meta/BACKLOG.md`, `docs/retro/v*.md`; `marketplace.json`
  inherits, also hands-off); (b) the lead integrates these once via `/kit:ship` after
  all workers finish; (c) the branch-ready / blocker signal each worker emits; (d) the
  explicit non-duplication clause: cross-task wiring stays `integration-checker`'s,
  the shared-surface write stays `/kit:ship`'s, convergence only collates signals +
  enforces the hands-off list; (e) it follows Detect-don't-dictate (warn+log, never a
  hard block)., AC: section exists; the hands-off list is a subset of the doc-impact
  map shared rows; the non-duplication clause names both `integration-checker` and
  `/kit:ship`.
- [x] TASK-007 (DONE 517dd68, verified): Add test-meta.sh assertions: (a) no `8 (workflow|lifecycle )?phases`
  string in the live OPERATING surfaces (`docs/PHILOSOPHY.md`, `docs/architecture.md`,
  `commands/`, `WORKFLOW.md`, `README.md`, `MANUAL.md`, `AGENTS.md`); the `docs/specs/`,
  `docs/decisions/`, `docs/research/` archive is excluded (AMEND-001); (b) WORKFLOW.md
  contains the V-model lens + convergence sections and the
  lens lists all cycle-table phases; (c) every hands-off-list entry appears in the
  doc-impact map (subset invariant); (d) command/agent → phase inventory count parity
  with `ls commands/ agents/` (sole owner of the parity check; TASK-005 only produces
  the table)., AC: `bash tests/test-meta.sh` passes with the new assertions present and
  green.

## After state
- [ ] WORKFLOW.md has a V-model lens that names every define↔verify pair and both
  mirror gaps. (Today: the cycle table lists phases + enforcers but states no mirror.)
- [ ] A single enumerated hands-off shared-surface list exists and is checkable by
  `grep` against the doc-impact map. (Today: the shared surfaces are scattered across
  the doc-impact map, the version-surfaces note, and ship.md; no one list.)
- [ ] No `8 (workflow|lifecycle )?phases` string exists in the live operating surfaces,
  checkable by `! grep -rIn --exclude-dir=specs --exclude-dir=decisions --exclude-dir=research -E "8 (workflow|lifecycle )?phases" docs/ commands/ WORKFLOW.md README.md MANUAL.md AGENTS.md`. (Today: operating surfaces still cite the hard count.)
- [ ] `docs/architecture.md` maps every command and agent to a V-phase, count-parity
  with the live inventory. (Today: no such mapping.)
- [ ] `bash tests/test-meta.sh` passes with the four new assertions. (Today: those
  assertions do not exist.)
- [ ] Zero new commands, agents, or hooks added. (Verifiable by `git diff --stat`:
  no new files under `commands/`, `agents/`, `hooks/`.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `bash tests/test-meta.sh` and `bash tests/test-hooks.sh` pass
- [ ] No new command/agent/hook files (the relabel guard: ID-034 is contract, not surface)
- [ ] The hands-off list is consumable by ID-035 (named, enumerated, subset of the doc-impact map)

## Verification
```bash
bash tests/test-meta.sh && bash tests/test-hooks.sh \
  && ! grep -rIn --exclude-dir=research --exclude-dir=specs --exclude-dir=decisions "8 \(workflow \|lifecycle \)\?phases" docs/ commands/ WORKFLOW.md README.md MANUAL.md AGENTS.md \
  && test -z "$(git diff --name-only --diff-filter=A origin/master...HEAD -- commands/ agents/ hooks/)"
```

## Edge Cases
1. **A new shared surface is added later** (e.g. a new `tool.toml` sibling). The
   subset invariant test (TASK-007c) fails until it is added to the hands-off list,
   forcing the two to stay in sync.
2. **A reword misses one of the 3 "8 phases" sites.** TASK-007a fails on the string
   grep; kit-health does not get a chance to self-fire because the test blocks first.
3. **Someone reads the V-model lens as a second cycle table and edits it instead of
   the canonical one.** Mitigated by the lens referencing (not restating) the phase
   list; the test asserts coverage by reference, so a divergent re-listing would still
   need the canonical phases present.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Convergence contract drifts into re-implementing ship | a convergence step writes `VERSION`/`CHANGELOG` | non-duplication clause + review; convergence has no write authority over shared surfaces, only signal collation |
| Hands-off list and doc-impact map diverge | subset test (TASK-007c) red | add the missing surface to the hands-off list; map is the source, list is the subset |
| A genuinely shared surface is in NEITHER the map nor the hands-off list | not auto-detectable (the subset test only checks list ⊆ map) | inherent limit; surfaces only as a real merge conflict at convergence, which the human resolves at `/kit:ship` |
| C2 reword changes meaning of criterion #2 | kit-health flags a real 2+-phase feature wrongly | ADR records intent; criterion stays "fewer than 2 lifecycle phases", only the count framing changes |

## Out of Scope
- **Worker dispatch / worktree spawning / the disjointness gate itself**, that is
  ID-035 (SPEC-032, to be written). This spec defines the *contract* a worker obeys
  and the hands-off list the gate *imports*; it builds no executor.
- **The C1 boundary ADR** (parallel-execution reverses 4 boundaries), that is
  ID-035's first step, not this spec's. This spec touches only C2.
- **Any new verification command** to fill the brief/requirement mirror gaps, the
  gaps are named and mapped to existing affordances (ship acceptance + retro), not
  filled with new surface.
- **Intra-spec task parallelism**, deferred per the brief's refined NO-list.

## Decision Log
- DEC-001: ID-034 adds **no new commands/agents/hooks**. Rationale: the kit already
  owns the lifecycle, verification pipeline, ship gate, and integration-checker; the
  gap is structural (the mirror, the hands-off list, the frame), not mechanical.
  Rejected: building per-phase commands (violates "every file justifies existence",
  feeds the relabel critique).
- DEC-002: **Convergence is scoped to signal-collation + hands-off enforcement**, not
  shared-surface writing or cross-task wiring. Rationale: research showed `/kit:ship`
  already writes the shared surfaces and `integration-checker` already checks
  cross-task wiring; duplicating either is the relabel trap. Convergence's only new
  job is the contract that workers stay off shared surfaces and the lead integrates
  once.
- DEC-003: **The mirror gaps (brief, requirement) are named and mapped, not filled.**
  Rationale: the acceptance level already exists (ship gate + retro); the fix is to
  require ship's acceptance criteria to trace the brief's user pain, not to add a
  new verify command. Detect-don't-dictate.
- DEC-004: **The V-model is a lens over WORKFLOW.md's cycle table, not a new table.**
  Rationale: one source of truth for the phase list; a second table would drift
  (the relabel trap in doc form).
- DEC-005: **The hands-off list lives in ID-034 (this spec); ID-035's disjointness
  gate imports it.** Rationale: resolves the gate-ownership question; convergence owns
  the shared surfaces, so the gate excludes them by reference. Matches the committed
  brief's placement (gate under ID-035, coupled to ID-034 convergence).
- DEC-006: **The "8 phases" reword targets the live OPERATING surfaces; the
  specs/decisions/research archive is excluded.** Rationale (spec-validate 2026-05-22,
  refined by AMEND-001 at execute): the operating surfaces (PHILOSOPHY, kit-health, and
  any future operating doc) must not state the criterion with a hard count, but the
  planning + decision + research archive legitimately quotes the old frame (a spec's own
  problem statement, an ADR's superseded-decision record, a dated research snapshot) and
  can never be string-empty while this spec exists. The grep is widened to
  `8 (workflow|lifecycle )?phases` (the old regex missed "8 lifecycle phases") and scoped
  `--exclude-dir={specs,decisions,research}`. Live absorption-gate citations
  (SPEC-003/004/007) are reworded for consistency even though they sit in the excluded
  archive. Rejected: blanket "no 8-phases anywhere" (self-defeating: SPEC-031 + ADR-0018
  must quote the string).
- DEC-007: **"Reference, don't restate" is scoped to the cycle table's phase names; the
  lens legitimately adds the define↔verify mirror and non-cycle phases.** Rationale
  (spec-validate 2026-05-22): the lens MUST name the mirror and the brief/requirement/
  opt-in-UI phases to do its job; those are its own contribution, not a duplicate phase
  list. Enforced by coverage (TASK-007b), not by an (impossible) no-duplication test.

## Amendments
- AMEND-001: 2026-05-22 | the "8 phases" absence check narrowed from "all of `docs/ commands/` outside research" to the live OPERATING surfaces only (`docs/PHILOSOPHY.md`, `docs/architecture.md`, `commands/`, `WORKFLOW.md`, `README.md`, `MANUAL.md`, `AGENTS.md`); the `docs/specs/` + `docs/decisions/` archive is now excluded alongside `docs/research/`. why: surfaced at execute (TASK-002) that the original blanket grep is self-defeating, SPEC-031's own problem statement + task text and ADR-0018's decision record legitimately contain "8 phases", so the grep could never be empty. Also added the SPEC-003/004 absorption-gate citations to TASK-002's reword list (consistency with the already-reworded SPEC-007). at TASK-002 checkpoint | tasks touched: TASK-002 (scope + 2 more rewords), TASK-007a, Verification, After state, DEC-006 | re-validated: delta-only (advisory; the disjointness/convergence ACs unchanged).

## Open questions
(none)

## Test plan
Date: 2026-05-22
Source: this spec's ## Acceptance Criteria (AC-1 all task ACs; AC-2 test-meta + test-hooks pass; AC-3 no new command/agent/hook; AC-4 hands-off list named/enumerated/⊆ doc-impact map)

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | ADR `0018-v-model-phase-frame.md` exists, Context/Decision/Consequences format, cross-ref'd from README + architecture.md | happy-path | AC-1 (TASK-001) | file present, 3 sections, 2 cross-refs | `test -f docs/decisions/0018-v-model-phase-frame.md && grep -qE 'Consequences' docs/decisions/0018-v-model-phase-frame.md` |
| 2 | `## The V-model lens` exists in WORKFLOW.md and names every define↔verify pair | happy-path | AC-1 (TASK-003) | section present; lists every cycle-table phase | `bash tests/test-meta.sh` (assertion b) |
| 3 | lane×phase depth matrix present; every lane×phase cell ∈ {measure-twice, run-lite, skip} | happy-path | AC-1 (TASK-004) | matrix covers every lane × define/verify phase | TBD (visual + grep for the matrix header; no cell-value test specified) |
| 4 | command/agent → V-phase inventory table in architecture.md; every command + agent appears once; count parity with live inventory | happy-path | AC-1 (TASK-005, TASK-007d) | row count == `ls commands/ agents/` | `bash tests/test-meta.sh` (assertion d) |
| 5 | `## Lead-owned convergence` section + enumerated hands-off list; non-duplication clause names both `integration-checker` and `/kit:ship` | happy-path | AC-1 (TASK-006) | section present; both names appear | `bash tests/test-meta.sh` (assertion b) + `grep -q integration-checker WORKFLOW.md` |
| 6 | Hands-off list is a subset of the doc-impact map shared rows | happy-path | AC-4 (TASK-007c) | every hands-off entry present in the map | `bash tests/test-meta.sh` (assertion c) |
| 7 | A shared surface added to the doc-impact map but NOT the hands-off list | boundary/edge | AC-4 (Edge 1) | subset test goes red until lists re-sync | `bash tests/test-meta.sh` (assertion c, negative) |
| 8 | Zero `8 (workflow\|lifecycle )?phases` strings in `docs/ commands/ WORKFLOW.md` excluding `docs/research/` | happy-path | AC-1 (TASK-002) | grep finds nothing | `! grep -rIn --exclude-dir=research "8 \(workflow \|lifecycle \)\?phases" docs/ commands/ WORKFLOW.md` |
| 9 | A reword misses a live site (e.g. SPEC-007:57) | boundary/edge | AC-1 (Edge 2) | the scoped grep / test-meta assertion (a) goes red | `bash tests/test-meta.sh` (assertion a, negative) |
| 10 | The widened regex catches the "8 lifecycle phases" variant (PHILOSOPHY:51), not just "8 phases" | boundary/edge | AC-1 (TASK-002, DEC-006) | pre-reword grep matches the lifecycle variant | the assertion-(a) grep run against an un-reworded :51 |
| 11 | `bash tests/test-meta.sh && bash tests/test-hooks.sh` pass with the new assertions | regression | AC-2 | both suites green | `bash tests/test-meta.sh && bash tests/test-hooks.sh` |
| 12 | No new files under `commands/`, `agents/`, `hooks/` (relabel guard) | regression | AC-3 | diff-filter=A is empty | `test -z "$(git diff --name-only --diff-filter=A origin/master...HEAD -- commands/ agents/ hooks/)"` |
| 13 | Criterion #2 + kit-health #4 still express the 2+-phase rule after reword (meaning preserved) | regression | AC-1 (TASK-002) | both still say "fewer than 2 ... phases" | `grep -qE 'fewer than 2 .*phases' docs/PHILOSOPHY.md commands/kit-health.md` |
| 14 | The cycle table stays the only canonical phase list (lens references, does not create a 2nd source) | regression | AC-1 (TASK-003, DEC-007) | lens lists cycle-table phases by reference | TBD ("no restatement" not directly testable; coverage via assertion b is the proxy) |

### Coverage notes
- Categories skipped: **security/abuse**, this is a docs/contract spec with no input, auth, or untrusted-content surface; the hands-off list is a safety control but its *enforcement* (workers must not write it) is SPEC-032's scope, not this spec's. **failure-injection**, limited applicability: no external deps or runtime; the only failure class is documentation drift, covered as boundary cases 7 and 9 (the test-meta assertions are the drift detector).
- TBDs (honest holes, not fabrications): case 3 (no cell-value test is specified for the lane×phase matrix; only structure is asserted), case 14 ("no restatement" has no direct test; coverage by reference is the proxy per DEC-007).
- This is a coverage TARGET across the enumerated categories, not an exhaustive test list. The four test-meta assertions in TASK-007 carry most of the proof weight; cases 1, 8, 12, 13 add greppable checks the suite does not already encode.
