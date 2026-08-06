# Proof of done: briefs-out (harness-ops sub-goal 10)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | `docs/specs/` holds only `SPEC-NNN-*.md` (+ its own README/legacy notes), no `DECISION-BRIEF*`/`CONTEXT.md` | PASS | `ls docs/specs/ \| grep -Ev '^SPEC-[0-9]+-.*\.md$'` -> only `README.md` + one legacy `cc-hyg-04-stop-tax.md` note (pre-existing, unrelated to this move) |
| AC2 | The 5 briefs live at `docs/briefs/` | PASS | `git mv` of `DECISION-BRIEF.md`, `DECISION-BRIEF-config-layer.md`, `DECISION-BRIEF-dag-wavefront.md`, `DECISION-BRIEF-kit-hardening.md`, `CONTEXT.md` -> `ls docs/briefs/` shows all 5 |
| AC3 | The named readers (`commands/{ui-design,devs-team,visual-team,next}.md`, `lib/goal/goal-drafts.sh`) resolve the new path | PASS | grep shows `docs/briefs/DECISION-BRIEF.md` / `docs/briefs/CONTEXT.md` in all 4 commands; `goal-drafts.sh` inspected -- its `GOAL_SPECS_DIR`/`specs_dir()` resolves `docs/specs/` for **SHIPPED SPEC-NNN** lookups only (`spec_is_shipped()`), never referenced DECISION-BRIEF/CONTEXT, so no change was needed there (see Deviations) |
| AC4 | No dangling functional reference (repo-wide grep, scoped to live/functional docs) | PASS | see "Dangling-reference sweep" below |
| AC5 | Meta test suite still green | PASS | `bash tests/test-meta.sh` -> 679/679 |

## Dangling-reference sweep

```
$ grep -rln 'docs/specs/DECISION-BRIEF\|docs/specs/CONTEXT' --include='*.md' --include='*.sh' --include='*.py' .
./CHANGELOG.md                                              # historical changelog entry, out of scope
./_meta/megagoals/harness-ops/goals/10-briefs-out.md        # this goal's own contract text; conductor-owned, not editable
./_meta/megagoals/harness-ops/ROADMAP.md                    # conductor-owned
./_meta/megagoals/harness-ops/NOTES.md                      # conductor-owned
./_meta/megagoals/_archive/kit-hardening/ROADMAP.md         # archived megagoal, historical
./_meta/megagoals/_archive/cc-elevation-r4/goals/02-skill-reviewer.md  # archived megagoal, historical
./docs/absorption/2026-06-12-gstack-product-skills-analysis.md        # dated research snapshot
./docs/specs/SPEC-*.md (12 files)                           # shipped SPEC-NNN files -- explicitly Out of scope ("the SPEC-NNN files (stay)")
./docs/decisions/0010-unify-spec-convention.md              # historical ADR
./docs/verification/skillspector-report-2026-06-25.md       # dated snapshot report
./docs/implementation-notes/right-arm-parity.md             # historical delta note tied to a shipped SPEC
./docs/retro/RETRO-2026-05-23-concurrency-safe-artifacts.md # historical retro
./lib/stats/docs/verification/defect-correlation.md         # generated, dated run report
./lib/skill-curator/{SPEC.md,docs/decisions/0004-*.md}      # separate nested project, its OWN docs/specs/CONTEXT.md (not the moved file)
```

All remaining hits are either (a) explicitly out-of-scope shipped `SPEC-NNN` files / conductor-owned
`_meta/megagoals/` files, or (b) dated historical records (CHANGELOG, ADRs, retros, absorption
research, verification snapshots) that describe what was true at the time and are not live pointers,
or (c) a separate nested project (`lib/skill-curator/`) with its own unrelated `docs/specs/CONTEXT.md`.

Every **live, functional** reader now resolves at `docs/briefs/`.

## Implementation

- `git mv` the 5 pre-spec artifacts from `docs/specs/` to `docs/briefs/`.
- Repointed the 4 named commands (`ui-design.md`, `devs-team.md`, `visual-team.md`, `next.md`).
- Repointed additional **live functional readers/writers** discovered by the full-repo grep that the
  goal's named list did not enumerate but which actively read/write the brief today: `commands/think.md`
  (writes the brief), `commands/design.md` (reads+appends the brief), `commands/spec.md` (reads the
  brief, writes CONTEXT.md), `commands/execute.md` (reads CONTEXT.md), `agents/brief-reviewer.md`
  (reads the brief). Left unfixed, `/kit:think` would keep recreating `docs/specs/DECISION-BRIEF.md`
  after every run, undoing the move (see Deviations).
- Repointed reference docs describing current behavior: `MANUAL.md`, `WORKFLOW.md`,
  `docs/architecture.md`, `_meta/BACKLOG.md` (ID-084's design-brief pointer), `docs/research/pitfalls.md`.
- `lib/goal/goal-drafts.sh`: inspected, no change needed (see Deviations).

## Deviations from the literal goal text

1. **`lib/goal/goal-drafts.sh` needed no edit.** The goal's parenthetical said "(GOAL_SPECS_DIR /
   brief path)", but `goal-drafts.sh`'s `GOAL_SPECS_DIR`/`specs_dir()` is used solely by
   `spec_is_shipped()` to resolve **SHIPPED `SPEC-NNN-*.md` files** in `docs/specs/` -- it never
   referenced `DECISION-BRIEF`/`CONTEXT.md`. That directory correctly stays `docs/specs/` (Out of
   scope: "the SPEC-NNN files (stay)... unaffected"). No dangling reference exists here.
2. **Expanded the reader set beyond the goal's named 4 commands + goal-drafts.sh.** The Outcome
   section says "every reader is repointed" and the Scope's parenthetical enumeration appears to be
   an incomplete first-pass grep by the goal's author. `commands/think.md`/`design.md`/`spec.md`/
   `execute.md` and `agents/brief-reviewer.md` are live functional readers/writers of the same two
   files; leaving them stale would have broken `/kit:think`+`/kit:design`+`/kit:spec` (they would
   keep operating on the old, now-nonexistent `docs/specs/DECISION-BRIEF.md` path) and defeated the
   goal's purpose. Reference docs (`MANUAL.md`, `WORKFLOW.md`, `docs/architecture.md`) were also
   updated to keep them accurate, since they are current behavior descriptions, not historical
   records. Historical/dated artifacts (SPEC-NNN files, CHANGELOG, ADRs, retros, absorption notes,
   dated verification snapshots) were left untouched per Scope's "Out"/"Not" (they document what was
   true at the time; rewriting them would falsify history).

## Reproduce

```
git mv docs/specs/DECISION-BRIEF.md docs/briefs/DECISION-BRIEF.md
git mv docs/specs/DECISION-BRIEF-config-layer.md docs/briefs/DECISION-BRIEF-config-layer.md
git mv docs/specs/DECISION-BRIEF-dag-wavefront.md docs/briefs/DECISION-BRIEF-dag-wavefront.md
git mv docs/specs/DECISION-BRIEF-kit-hardening.md docs/briefs/DECISION-BRIEF-kit-hardening.md
git mv docs/specs/CONTEXT.md docs/briefs/CONTEXT.md
grep -rln 'docs/specs/DECISION-BRIEF\|docs/specs/CONTEXT' --include='*.md' --include='*.sh' --include='*.py' .
bash tests/test-meta.sh
```
