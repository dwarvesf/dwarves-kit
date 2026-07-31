# SPEC-216: GUIDE.md, the end-user owner's manual

Status: APPROVED · 2026-07-31 · Owner: Han
Lane: normal
Relates-to: docs/briefs/DECISION-BRIEF-factory-legibility.md §4 (board row
ID-456), `/kit:explain` (adjacent, not overlapping), ID-434 (plain-language
ledger renderer, adjacent, not overlapping)

## Problem

The kit's docs lane (`commands/docs.md`) documents the code for the next
builder. Nothing is owed to the END USER of the thing that gets built, the
person who runs it and never reads a diff. `/kit:explain` explains a shipped
CHANGE to a human who already knows the product; ID-434 renders the kit's own
ledger in plain language. Neither writes the one-page "what is this, how do I
use it, what do I do when it breaks" manual a non-builder owner needs.

## Solution shape

Three pieces, no renderer, no new command:

1. **The template.** `docs/GUIDE.template.md`: a fill-in skeleton with three
   sections (what this does / how to use it / what to do when it breaks),
   2-3 lines of guidance per section, ELI10 register (plain everyday words,
   no internals, no jargon). A consumer repo copies it to `GUIDE.md` at the
   product root and fills it in. One page.
2. **Ship checklist line.** `commands/ship.md` gains a warn-not-block step
   (same voice as the existing Step 1b / Step 4a): apply the test "does this
   change have an end user who is not the builder?"; if yes, confirm
   `GUIDE.md` exists and still matches what shipped. Libraries and infra are
   exempt by the same test.
3. **Docs-lane pointer.** `commands/docs.md`'s doc-scan step (Step 2) gains a
   `GUIDE.md` entry beside the existing README/CLAUDE.md/CHANGELOG bullets,
   so a doc-drift pass keeps it in scope, gated by the same end-user test.

### Why not a hook or a new command

The kit's hard blocks stay reserved for safety-gate, push-to-main,
anti-rationalization, and the verification pipeline (AGENTS.md zone "Pause
if"; PHILOSOPHY rejects hard-gating process completeness). A GUIDE.md
staleness check is process completeness, so it gets the same warn-and-log
treatment as the Step 1b completeness log and the Step 4a release-hygiene
check, not a new enforcement surface. No renderer exists yet to auto-fill
the template, so this spec ships the contract only; a future row can add
automation on top without changing the template shape.

### Design

`obvious: three static-doc edits (one new template file, two existing
command files gain a section each); no new component, no schema, no
external integration, no irreversible choice.`

## Out of scope

- A GUIDE.md renderer or generator (ID-434 is the adjacent plain-language
  renderer; it stays a separate row if ever built for this).
- Hook enforcement of GUIDE.md presence or freshness.
- The WORKFLOW.md doc-impact map (a ship-time completeness-clause surface
  distinct from the docs-lane pointer this spec adds; a natural follow-up,
  left for its own row if the warn-only line proves insufficient).
- `/kit:explain` changes (adjacent surface, explains a change to someone who
  already knows the product; not touched).

## Verification

```bash
test -f docs/GUIDE.template.md \
  && grep -q "What this does" docs/GUIDE.template.md \
  && grep -q "How to use it" docs/GUIDE.template.md \
  && grep -q "What to do when it breaks" docs/GUIDE.template.md \
  && grep -q "end user who is not the builder" commands/ship.md \
  && grep -q "GUIDE.md" commands/docs.md \
  && echo VERIFIED
```

## After state

- [ ] `docs/GUIDE.template.md` exists with its three sections. (Today: no
      end-user-facing template exists anywhere in the kit.)
- [ ] `commands/ship.md` names the "has an end user" test and points at the
      template.
- [ ] `commands/docs.md`'s doc-scan step lists `GUIDE.md` as a companion to
      check, gated by the same test.
