# SPEC-213: workshop-tour narrative

Status: APPROVED
Lane: normal
Relates-to: docs/briefs/DECISION-BRIEF-factory-legibility.md §1 (ID-453), ID-307 (grill -> interview,
pending; this spec rides its word, never fights it), docs/glossary.md (ID-293/ID-291 plain-words work)

## Problem

The kit's five stages (Shape, Build, Watch, Check, Learn) are abstract nouns. A new reader can
picture an inspector; a new reader cannot picture a "Watch stage." The Mike's Software Factory
read (operator direction 2026-07-31) named why the factory's own names work: they are one
coherent workplace story with people in it. The kit's plain-words program already fixed
individual jargon words (docs/glossary.md); the stages themselves stayed nameless-as-people.

## Solution

### Approaches considered

1. **Rename the stages.** Rejected outright by the row: internal renames are their own migration
   (ID-293/ID-307 pattern, 300+ files each) and this row is explicitly scoped to NOT touch
   internals.
2. **A narrative layer on human-facing surfaces only, one page.** Add a short story (role +
   artifact per stage) to the README quickstart, `/kit:onboard`, and the MANUAL opening, and a
   story-name-to-real-name lookup table in the glossary. No command, file, or config renamed.
3. **A dedicated new doc page for the story.** Rejected: adds a fourth surface to find and keep in
   sync for a one-page amount of content; the existing three entry points (quickstart, onboard,
   manual) already cover "a reader's first five minutes."

### Chosen approach + why

Approach 2. It is additive, costs one small edit per existing surface, and rides ID-307's planned
grill -> interview rename instead of inventing a competing word for the same step.

### Extensibility & boundaries

- Adding a sixth stage later means adding one row to the glossary table and one sentence to each
  of the three surfaces; the story format does not change shape.
- Unit boundary: each surface's edit is independent and additive. Removing any one leaves the
  other two intact and the glossary table still correct (it does not depend on the prose surfaces
  existing).

### Architecture

See `## Design` below.

## Design

obvious: pure prose additions to four existing markdown files; no new component, no schema, no
control-flow change, no external integration, one obvious approach (narrative-only, ID-307
alignment already decided by the row).

## Technical Design

### Interfaces (I/O contract)

Not applicable; this is prose-only. No code, no config, no data model.

### Data model changes / API changes / UI changes / Infrastructure changes

None.

## Task Breakdown

### Phase 1: the story

- [x] TASK-001: `docs/glossary.md` gets a "workshop story names" section with a two-column
      (story name / real name) table -- acceptance: table present, five rows, no jargon term
      renamed elsewhere in the file.
- [x] TASK-002: `README.md`'s "Your first cycle" quickstart gets one added sentence naming the
      story in miniature (interview / crew / inspector) and pointing at the fuller tour --
      acceptance: existing five numbered steps unchanged, one sentence added.
- [x] TASK-003: `docs/MANUAL.md`'s opening gets one added paragraph, same story, pointing at
      `/kit:onboard` and the glossary -- acceptance: existing Conventions section and everything
      after it unchanged.
- [x] TASK-004: `commands/onboard.md` gets one additive section (an optional fuller retelling of
      the closing five-sentence tour, voiced as role + artifact) appended after the existing
      `## Do NOT` block -- acceptance: no existing line in the file changed, only new lines added
      at the end; no command or file name renamed inside it.

## After state

- [x] A reader of the README quickstart, `/kit:onboard`, or the MANUAL opening meets the same
      one-page story (interview / night shift / logbook / inspector / debrief) mapped honestly to
      Shape/Build/Watch/Check/Learn. (Today: the three surfaces named only the abstract stage
      nouns.)
- [x] `docs/glossary.md` has a story-name column a reader can look up. (Today: the glossary maps
      jargon to plain words only, no story layer.)
- [x] No command, file, or config was renamed; `grep -r` for any of the story words as a `/kit:`
      command or `lib/` path returns nothing (checkable by the Verification commands below).

## Acceptance Criteria (global)

- [x] All four tasks pass their individual acceptance criteria.
- [x] The mechanical greps below all pass.
- [x] No regressions: `tests/test-docs-wiring.sh` and `tests/test-onboard-detect.sh` still pass
      (neither one's file contract touches the lines this spec edited).

## Verification

```bash
# story-name column present in the glossary, five rows
grep -c '^| The ' docs/glossary.md   # expect 5

# tour section present in the fuller (onboard) surface
grep -q '## Optional: tell it as the workshop story' commands/onboard.md && echo present

# tour language present in the short (README) and MANUAL surfaces
grep -q 'an interview turns your ask into a blueprint' README.md && echo present
grep -q 'an interview turns your ask into a blueprint' docs/MANUAL.md && echo present

# no renamed command strings: the story words never appear as a command or lib path
grep -rE '/kit:(interview|night-shift|logbook|inspector|debrief)\b' commands/ README.md docs/MANUAL.md && echo FAIL || echo "no renamed command strings"

# existing doc-contract tests still pass
bash tests/test-docs-wiring.sh
bash tests/test-onboard-detect.sh
```

## Edge Cases

1. A reader who never sees the story (goes straight to `lib/` or `commands/*.md` bodies) is
   unaffected: every internal name is untouched, so nothing they read elsewhere contradicts what
   they see in the story.
2. `/kit:onboard`'s in-flight rewrite (open PR #297, six verified exercises) lands after this
   spec: the new section here was appended after the file's final existing block specifically so
   a merge only has to resolve one small hunk at the tail, not the file's restructured body.

## Out of Scope

- Any internal rename (owned by ID-307, explicitly deferred).
- The other four DECISION-BRIEF directions (ID-454 spec Picture section, ID-455 visual-proof
  dashboard, ID-456 GUIDE.md template, ID-457 manager loop) -- each its own row.
- Retrofitting the story into every other doc that mentions the five stages; three entry points
  (README quickstart, onboard, MANUAL opening) plus the glossary lookup are the smallest
  deliverable the row asks for.

## Decision Log

- DEC-001: rode ID-307's grill -> interview word for the Shape-stage role instead of coining a
  new term, per the row's explicit instruction not to fight that rename.
- DEC-002: appended the onboard.md addition after the file's last existing section rather than
  interleaving it into the exercise/step flow, to keep the diff a pure addition against the
  in-flight restructure PR (#297).
- DEC-003: `## Design` collapsed to `obvious:` -- no new component, schema, or irreversible
  choice; the only real decision (which surfaces, which words) is DEC-001/DEC-002 above.

## Think pass (commands/think.md, self-run per this task's instructions)

- **Q1 real pain:** a new reader cannot picture an abstract stage noun ("Watch"); they can
  picture a role (an inspector). Named, not hand-waved.
- **Q2 10x version:** the whole docs set reads as one continuous story, every page. Rejected as
  the actual scope: the row asks for the smallest deliverable (one page + a glossary table), and
  a repo-wide narrative rewrite is its own (much larger, unscoped) project.
- **Q3 simplest version proving the thesis:** exactly what shipped -- one short story on the three
  entry surfaces plus the glossary lookup. If this doesn't make the stages easier to picture nothing
  bigger will either.
- **Q4 what got cut:** no internal renames, no new command, no fourth doc page, no touch to the
  five-stage table in README's own "The five stages" section (left as-is; the quickstart carries
  the short version instead, per the row's own surface list).
- **Q5 what breaks at scale:** the story words could drift out of sync with the real names as the
  kit evolves (a sixth stage, a renamed stage). Mitigated by the glossary table being the single
  source the other three surfaces point at, never restated in full elsewhere.
- **Q6 exit criteria:** the mechanical greps in `## Verification` all pass and no command/file
  string was renamed. Met at time of writing (see Verification output in the implementation
  notes / PR description).
- **Material change forced:** none. The task's own instructions already fully specified the
  design (from the DECISION BRIEF); the think pass confirmed the scope rather than changing it.

## Review

### Verdict: SHIP

### Findings

None blocking. Docs-only, additive, four small edits, all mechanically verified.

### TODOs

None.

## Open questions

(none)
