# Spec: Align design-critique placement to spec-first (devs-team, visual-team)

Generated: 2026-05-21
Status: VALIDATED
Source: maintainer reconciliation 2026-05-21, following the WORKFLOW.md "Artifact placement and concurrency" section (committed `3ae656e`). That section codified the spec-first placement rule (an artifact bound to a spec lives IN the active spec; pre-spec/per-diff artifacts stay worktree-isolated files). A doc-verifier-style dogfood found the rule is honored by the newer lanes (`/user:test-plan`, SPEC-018; `/user:ui-design`, SPEC-020 DEC-008) but violated by the two original SPEC-016 critique lanes: `/user:devs-team` writes its critique brief-first, and `/user:visual-team` writes brief-or-inline with no spec path. The kit thus has four lanes with three placement behaviors; this spec collapses them to one.
Supersedes: SPEC-016's `## Design critique` and `## Visual critique` placement only (brief-first / brief-or-inline -> spec-first). SPEC-016 remains the record of the lanes; this changes only where they write. SPEC-016 is not edited in place (the kit's "do not edit a SHIPPED spec" rule); this mirrors how SPEC-018 superseded SPEC-016 Part B's test-plan placement.
Depends on: SPEC-016 (the two lanes this aligns), SPEC-005 (the shared branch-aware active-spec detection both lanes must use), SPEC-018 + SPEC-020 (the lanes already on spec-first, the target shape), and the WORKFLOW.md placement rule.
Lane: normal. No hook is touched. Bounded surface: edit two commands (`devs-team`, `visual-team`), meta-test wording pins, WORKFLOW.md table simplification, doc updates. Should be dogfooded through `/user:spec-validate`.

## Problem

The WORKFLOW.md placement rule says a spec-bound artifact lives in the active spec, resolved via the one shared SPEC-005 detection, so a writer and a later reader never split across two specs and concurrent specs never collide. Two of the four lanes that produce spec-bound critiques do not follow it:

| Lane | Writes `## ...` | Placement today | Follows rule? |
|---|---|---|---|
| `/user:test-plan` (SPEC-018) | `## Test plan` | active spec | yes |
| `/user:ui-design` (SPEC-020) | `## UI design` + `## Visual critique` | active spec, else brief | yes |
| `/user:devs-team` (SPEC-016) | `## Design critique` | **brief if present, else spec** | no (brief-first) |
| `/user:visual-team` (SPEC-016) | `## Visual critique` | **brief if present, else inline-only** | no (no spec path) |

Concrete consequences:

1. **`devs-team` brief-first.** It reads the design's `## Solution` and writes `## Design critique` to "the brief if present, else the active spec" (`commands/devs-team.md:44`). In its normal pre-spec slot (between `/design` and `/spec`) no spec exists, so it writes to the brief either way and nothing changes. But once a spec exists AND a brief still exists (the brief is not deleted when `/spec` folds it in), it writes the critique to the brief, not the spec it now belongs to. The critique is then not carried by the spec, breaking the multi-spec-safe guarantee.
2. **`visual-team` has no spec path at all.** It writes `## Visual critique` to the brief if one exists, else inline-only (`commands/visual-team.md:43`). There is no branch that writes into the active spec, so a downstream project with a spec gets a critique that lives nowhere durable (inline) or in the pre-spec brief, never in the spec.

The WORKFLOW.md table currently documents this honestly with "predates the rule (follow-up to align)" caveats. This spec is that follow-up: make the rule uniformly true and drop the caveats.

## Solution

### Approaches considered
1. **Flip both lanes to spec-first (CHOSEN).** Change `devs-team` read+write precedence to "active spec if present, else the brief," and add a spec-first write path to `visual-team` ("active spec, else brief, else inline"). Both resolve the active spec via the shared SPEC-005 detection. Minimal, mirrors `test-plan` + `ui-design` + the WORKFLOW rule exactly.
2. **Document the exception permanently.** Keep the two lanes brief-first and leave the WORKFLOW caveats. Rejected: three placement behaviors across four lanes is the inconsistency we are removing; a codified rule that two shipped commands violate is the doc-vs-code gap the kit's `doc-verifier` exists to prevent.
3. **Extract a shared placement helper.** Rejected: these are prose commands with no shared-code mechanism; the rule is one sentence repeated in four places, and a `design-critic`-style shared agent was already deferred (SPEC-016 DEC-007) until a third consumer with real shared logic. Copying one sentence is not the premature-abstraction trigger.

### Chosen approach + why
Approach 1. The placement rule is sound and already proven by two lanes; the two laggards predate it. Flipping their precedence is a small, low-risk change (for `devs-team` it only changes the rare both-brief-and-spec-exist case; its common pre-spec behavior is unchanged), and it makes the WORKFLOW rule true rather than aspirational. After this, any new lane can copy any of the four and the rule holds.

### Extensibility & boundaries
- Load-bearing dimension: the placement precedence HEAD ("active spec if present, else the brief"). After this, all four lanes share that head; `visual-team` alone keeps a third tier ("else inline-only") because it is the only lane that can run with neither a spec nor a brief (a standalone screenshot critique). So the shared invariant is the spec-first head, not the whole string; a new lane copies the head and adds tiers only if its input model needs them. A meta-test pins the spec-first wording in `devs-team` and `visual-team` so neither can silently revert to brief-first.
- Unit boundaries: each lane owns its own read+write; the shared SPEC-005 detection is the common dependency (not duplicated logic, a referenced rule). No command reads these critiques (they are human-facing, verified: only `test-plan.md` even mentions the headings, as comparisons, not reads), so unlike `## Test plan` there is no writer/reader contract to drift-guard, only the placement to pin.
- This alignment makes `visual-team`'s placement MATCH the not-yet-built `/user:ui-design` (SPEC-020). Today they diverge: `visual-team` writes brief-or-inline, `ui-design` (per SPEC-020 DEC-008) writes its `## UI design` + `## Visual critique` spec-else-brief. SPEC-020's design has `ui-design` write `## Visual critique` itself (TASK-1, Outputs); SPEC-023 does NOT change that and does NOT make `visual-team` a "single writer". Instead, both end up writing the same heading to the same spec-first location with replace-not-stack, so a duplicate section is impossible (the later write replaces). Coordination note for the SPEC-020 build: keep `ui-design`'s `## Visual critique` write at the same spec-first location + heading as `visual-team` so replace-not-stack holds (DEC-002). No `ui-design` command exists yet, so nothing changes here now.

### Architecture
```
spec-first placement, uniform across the four lanes:

  resolve the active spec  (shared SPEC-005 branch-aware detection)
        |
        +-- a spec exists?  --yes-->  write the `## ...` section INTO that spec
        |                              (replace-not-stack)
        +-- no spec yet?    --------> write into the pre-spec DECISION-BRIEF.md
                                       (visual-team: else present inline-only)

  devs-team:    read the design `## Solution` from the same spec-first location,
                write `## Design critique` there.
  visual-team:  write `## Visual critique` spec-first (was brief-or-inline).
  test-plan / ui-design: already on this rule (unchanged).
```

## Technical Design

### Interfaces (I/O contract)
- **`devs-team` (changed):** reads the design's `## Solution` from the active spec if a spec exists (resolved via the shared SPEC-005 detection), else from `docs/specs/DECISION-BRIEF.md`; writes `## Design critique` back to the SAME doc it read (active spec if present, else the brief). Replace-not-stack, unchanged. If neither has a `## Solution`, it stops and points to `/user:design` or `/user:spec` (unchanged).
- **`visual-team` (changed):** writes `## Visual critique` to the active spec if one exists, else the brief if one exists, else presents inline-only. Replace-not-stack, unchanged. Input sources (screenshot, URL, description, brief `## Visual`) unchanged; the security data-not-instructions rule unchanged.
- **Invariants:**
  - both lanes resolve "the active spec" through the SAME SPEC-005 detection the other lanes use (so writer/reader/concurrent specs agree). If detection is ambiguous (several specs match on one branch), the lane asks the user which one rather than auto-picking, mirroring `test-plan` (DEC-006).
  - placement is spec-first: active spec if present, else the brief (`visual-team` then falls back to inline-only when neither exists).
  - one critique section per doc (replace, never stack), unchanged. This is what prevents a duplicate `## Visual critique` when both `visual-team` and `ui-design` write it: same heading + same spec-first location + replace-not-stack means the later write replaces, never appends a second (DEC-002).

### Data model changes
None. The critique sections move from brief-first to spec-first placement; no new file or directory. No root file was involved (unlike SPEC-018).

### API / UI / Infrastructure changes
- `commands/devs-team.md` (edit): flip the Step 1 read order and the Step 4 write target to spec-first; update the frontmatter `description:` ("the decision brief if present, else the active spec" -> "the active spec if present, else the decision brief"); name the shared SPEC-005 detection.
- `commands/visual-team.md` (edit): add the spec-first write branch ahead of the brief branch in Step 4 (active spec, else brief, else inline).
- `tests/test-meta.sh` (edit): wording pins (see TASK-3).
- `WORKFLOW.md` (edit): simplify the placement table now that all four lanes are uniform; drop the "predates the rule" caveats and the laggards note.
- `MANUAL.md`, `CHANGELOG.md` (edits): document the placement change + the SPEC-020 coordination note.

## Task Breakdown

**Phase 1: Align the two commands**
- [ ] **TASK-1: `commands/devs-team.md` to spec-first.** Flip Step 1 read order (active spec's `## Solution` if a spec exists via the shared SPEC-005 detection, else the brief's `## Solution`) and Step 4 write target (the active spec if present, else the brief) to spec-first; the read and write MUST resolve to the same doc (read where the design is, write the critique back there). If several specs match detection, ask the user which one (mirror `test-plan`), do not auto-pick. Update the frontmatter `description:` accordingly. Keep replace-not-stack and the no-design-found stop behavior.
  - Acceptance: `commands/devs-team.md` states spec-first placement for BOTH read and write (greppable: reads the spec's `## Solution` if present else the brief, writes the critique to the same doc); the description matches; the ambiguous-match "ask the user" behavior is stated; replace-not-stack preserved; no em-dash introduced.
- [ ] **TASK-2: `commands/visual-team.md` to spec-first.** In Step 4, add a branch that appends `## Visual critique` to the active spec when one exists (resolved via the shared SPEC-005 detection), falling back to the brief, then to inline-only. If several specs match, ask the user which one (mirror `test-plan`). Keep replace-not-stack and the Step-1 data-not-instructions rule (the fenced-quote + named-injection discipline must survive the edit, since the critique now lands in the durable spec).
  - Acceptance: `commands/visual-team.md` writes `## Visual critique` to the active spec if present, else brief, else inline (greppable, in that order); the data-not-instructions rule is still present; replace-not-stack preserved; no em-dash introduced.

**Phase 2: Pin + document**
- [ ] **TASK-3: `tests/test-meta.sh` wording pins.** Assert `commands/devs-team.md` states spec-first for BOTH its read and its write target (two pins, so a future edit that flips only one side fails), and `commands/visual-team.md` states spec-first placement. No behavior harness exists for command prompts (SPEC-016 Known limitation 5); the pins guard the placement wording, the same posture as the other command structural assertions.
  - Acceptance: `bash tests/test-meta.sh` green with the new pins; a revert to brief-first wording on either side (devs-team read or write, or visual-team) fails the suite.
- [ ] **TASK-4: docs.** In `WORKFLOW.md`: simplify the placement table (all four lanes now follow the rule; drop the two "predates the rule" caveats and the laggards note in the prose) AND reconcile the second table, the "The cycle" row for the design-critique lane that still reads "critique appended to the brief or spec," so it no longer implies brief-first. Update the `/user:devs-team` and `/user:visual-team` sections of `MANUAL.md`. Add a `CHANGELOG.md` [Unreleased] entry (Changed: devs-team + visual-team aligned to spec-first placement; supersedes SPEC-016 placement; note the SPEC-020 ui-design coordination).
  - Acceptance: BOTH WORKFLOW.md tables show spec-first placement with no laggard caveat; MANUAL reflects the new placement; CHANGELOG entry present + names the SPEC-020 coordination; `bash tests/test-meta.sh` green.

## Acceptance Criteria (global)
- [ ] `/user:devs-team` reads the design `## Solution` and writes `## Design critique` spec-first (active spec if present, else the brief), via the shared SPEC-005 detection
- [ ] `/user:visual-team` writes `## Visual critique` spec-first (active spec, else brief, else inline-only), matching `ui-design`'s placement; duplicates are prevented by the shared heading + replace-not-stack, not by a single-writer rule
- [ ] All four critique/plan lanes (test-plan, ui-design, devs-team, visual-team) share the spec-first placement head; the WORKFLOW.md placement table AND the "The cycle" table carry no brief-first / "predates the rule" implication
- [ ] Both lanes ask the user on ambiguous active-spec detection (mirroring `test-plan`), never auto-pick (DEC-006)
- [ ] The spec-first wording is pinned in both commands by a meta-test (cannot silently revert); for `devs-team` both the read and write target are pinned
- [ ] The SPEC-020 coordination (keep `ui-design`'s `## Visual critique` at the shared spec-first location + heading so replace-not-stack dedups) is recorded for its future build
- [ ] `bash tests/test-meta.sh` green; `bash tests/test-hooks.sh` unchanged (no hook touched); no em-dash introduced

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh`. Spot-checks: `grep -qi 'active spec if present' commands/devs-team.md && grep -qi 'active spec' commands/visual-team.md`; confirm `commands/devs-team.md` no longer says it writes "the brief if present, else the active spec" (brief-first gone); `! grep -qi 'predates the rule' WORKFLOW.md` (caveats dropped). Dogfood: run `/user:devs-team` with both a brief and an active spec present and confirm the critique lands in the spec.

## Edge Cases
1. **`devs-team` pre-spec (no spec yet).** Spec-first falls through to the brief; unchanged from today's common case (the brief is the only artifact between `/design` and `/spec`).
2. **Both a brief and a spec exist.** `devs-team` now writes to the spec (changed from the brief); this is the case the alignment fixes.
3. **`visual-team` downstream with a spec.** Writes `## Visual critique` into the spec (new path).
4. **`visual-team` with neither spec nor brief.** Inline-only (unchanged fallback).
5. **`/user:ui-design` built later (SPEC-020).** Both `visual-team` and `ui-design` write `## Visual critique` spec-first; because they share the heading + the spec-first location + replace-not-stack, the later write replaces the earlier, so no duplicate section results. SPEC-020 keeps `ui-design` writing the section (its DEC-008); SPEC-023 just makes `visual-team`'s placement match. Coordination note only; no `ui-design` command exists yet.
6. **A spec exists but has no `## Solution`** (devs-team reads the design from there). It falls back to the brief's `## Solution`; if neither has one, it stops and points to `/user:design` or `/user:spec` (unchanged).

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A lane silently reverts to brief-first | a critique lands in the brief though a spec exists | meta-test pins the spec-first wording in both commands; a revert fails the suite |
| `devs-team` read and write target diverge | it reads the spec's `## Solution` but writes the critique to the brief (or vice versa) | TASK-1 ties read and write to the SAME spec-first location; acceptance checks both |
| Duplicate `## Visual critique` once ui-design ships | two `## Visual critique` sections in one doc | both writers use the same heading + spec-first location + replace-not-stack, so the later write replaces, never appends (DEC-002); not a single-writer rule |
| Ambiguous active-spec (several specs match on one branch) | detection returns more than one SPEC-NNN | the lane asks the user which one, mirroring `test-plan`; it does not auto-pick and silently land the critique in the wrong spec (DEC-006) |
| `visual-team` writes inline when a spec exists | the critique is lost (not durable) | spec-first branch is checked before the brief and inline fallbacks; acceptance asserts the order |

## Out of Scope
- Building `/user:ui-design` (SPEC-020 owns it); this spec only records the coordination it must honor.
- Changing `/user:test-plan` or `/user:ui-design` (already spec-first).
- Adding a reader or writer/reader drift-guard for the critiques (no command reads them; they are human-facing, unlike `## Test plan` which `/user:execute` consumes).
- Editing the SHIPPED SPEC-016 in place (superseded via this spec + CHANGELOG).
- A shared `design-critic` placement helper/agent (deferred per SPEC-016 DEC-007 until a real third consumer).

## Decision Log
- **DEC-001**: Flip both lanes to spec-first; do not document the exception permanently. Rationale: the WORKFLOW rule should hold uniformly, not be true for two lanes and waived for two; a codified rule that shipped commands violate is the doc-vs-code gap `doc-verifier` guards against. Maintainer decision 2026-05-21.
- **DEC-002 (corrected after validation)**: NOT "visual-team is the single writer." SPEC-020's VALIDATED design has `/user:ui-design` write `## Visual critique` itself (its TASK-1 + DEC-008), so a single-writer rule would contradict it. The real mechanism: `visual-team` and `ui-design` both write `## Visual critique` to the SAME spec-first location with the SAME heading and replace-not-stack, so the later write replaces the earlier and no duplicate section can occur. SPEC-023's only job here is to align `visual-team`'s placement (brief-or-inline -> spec-first) so it matches `ui-design`'s; replace-not-stack does the dedup. Coordination note for the SPEC-020 build: keep its `## Visual critique` write at the spec-first location + heading. (The first draft of this DEC misread SPEC-020 as having ui-design delegate the write; the spec-validate assumption-destroyer lens caught it.)
- **DEC-003**: Supersede SPEC-016's placement for these two lanes via this new spec; do not edit the SHIPPED SPEC-016 in place. Rationale: the kit's "do not edit a SHIPPED spec" rule; mirrors SPEC-018 superseding SPEC-016 Part B's test-plan placement.
- **DEC-004**: No writer/reader drift-guard (unlike SPEC-018's `## Test plan`). Rationale: no command reads the critiques (verified), so the only regression risk is silent placement reversion, which a wording pin in the meta-suite covers.
- **DEC-005**: `devs-team`'s common pre-spec behavior is unchanged (no spec -> brief). Only the both-brief-and-spec-exist case flips to the spec. Rationale: keeps the change low-risk; the alignment matters precisely in the case the old precedence got wrong.
- **DEC-006 (validation)**: On ambiguous active-spec detection (several specs match on one branch), both lanes ask the user which one, mirroring `test-plan`; they never auto-pick. Rationale: the spec leaned on "the shared SPEC-005 detection" as if it always returns one spec, but the non-worktree multi-match case is real, and an auto-pick would silently land the critique in the wrong spec, the exact failure the placement rule exists to prevent. Found by the failure-mode lens.

## Source citations
- The placement rule this enforces: `WORKFLOW.md` "Artifact placement and concurrency" (commit `3ae656e`).
- The lanes being aligned: `commands/devs-team.md` + `commands/visual-team.md` (SPEC-016).
- The lanes already on spec-first (the target shape): SPEC-018 (`## Test plan` in the spec) + SPEC-020 DEC-008 (`## UI design` / `## Visual critique` spec-else-brief).
- The supersede-via-new-spec precedent: SPEC-018 (superseded SPEC-016 Part B placement).
- The shared detection: SPEC-005 (branch-aware active-spec).
- Philosophy bars: "No phantom features" (a rule the code violates), "Replace, don't deprecate" (update the commands fully), "every file justifies its existence".

## Validation
`/user:spec-validate` dogfooded on this spec 2026-05-21 (5 lenses dispatched in parallel as isolated subagents). Pre-fix verdict: **NEEDS REVISION** (no critical; 2 medium + several low). Scores: Security 9, Failure-mode 8, Assumption-destroyer 7, Scope 9, Solution-design 8. All folded; see DEC-002 (corrected) + DEC-006.
- **Medium (Assumption-destroyer + Solution-design):** the first draft's DEC-002 misread SPEC-020 as having `ui-design` delegate the `## Visual critique` write to `visual-team`, and prescribed a "single writer" rule that contradicts SPEC-020's VALIDATED design (ui-design writes the section itself). Corrected: both write spec-first to the same heading + location; replace-not-stack prevents duplicates; SPEC-023 only aligns visual-team's placement (DEC-002 rewritten). This was the load-bearing fix.
- **Medium (Failure-mode):** ambiguous active-spec resolution was unspecified; both lanes now ask the user on a multi-match, mirroring `test-plan` (DEC-006).
- **Medium (Solution-design):** "copy any of the four lanes" oversold; the shared invariant is the spec-first head, and visual-team keeps an inline tail the others lack (Extensibility softened).
- **Low:** TASK-4 now also reconciles WORKFLOW.md's "The cycle" table row; TASK-3 pins both devs-team's read and write target; TASK-2 carries the data-not-instructions discipline through the edit (security lens).
- **Passed:** alignment is genuinely needed (verified `/spec` does not delete the brief, so the both-exist case is real); "no command reads the critiques" is true (so no drift-guard, only a wording pin); supersede-not-edit mirrors SPEC-018.
Status flipped to VALIDATED after the mediums were folded into Invariants / DEC-002 / DEC-006 / Tasks / Failure modes.
