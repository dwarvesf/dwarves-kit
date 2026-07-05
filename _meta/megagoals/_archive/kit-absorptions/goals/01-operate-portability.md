# Sub-goal 01: operate-portability (the run contract ships WITH the skill)

**Merge policy:** gate
**Time budget:** 1-1.5 hours of loop work
**Proof:** run-table: (a) `chezmoi apply` clean + source/applied checksums match; (b) the teammate-grep NC: `rg -n 'ops-toolkit|/Users/tieubao' references/OPERATE.md` returns ONLY the optional-overlay mention (captured); (c) a resolution walk-through showing a scaffold in a NON-ops repo resolves the RUN CONTRACT line to the skill's portable copy.
**Design:** obvious
**Depends on:** none (dotfiles stack head)
Model: sonnet
**Branch:** `feat/operate-portability`
**PR base:** main (dotfiles repo)

## Outcome

ID-246 re-applied against the thin+GUIDE skill structure: `references/OPERATE.md` is the confirmed SINGLE SOURCE for the shared run-clauses, carries zero private paths, and the invocation-template's RUN CONTRACT resolution (local overlay if present, else the skill's portable copy) is verified end to end. A teammate without ops-toolkit access can run a mega-goal from the skill bundle alone.

## Quality bar

No private ops-toolkit paths anywhere in the portable copy (the grep NC is the bar). The ops-toolkit overlay relationship is described, never required.

## How to close the loop

- `chezmoi apply` + shasum table over touched files.
- The teammate-grep NC captured (only the optional-overlay mention survives).
- Read-through: `invocation-template.md`'s resolution paragraph names both paths and the fallback order; capture the paragraph in the proof.
- dotfiles is NOT kit-adopted: proof lands in the PR body.

**Done =** portable OPERATE.md has zero private-path dependencies (grep NC captured) and the resolution order is verified in the template, chezmoi-clean.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. Overwrite HOT `HANDOFF.md`: next is 02-dotfiles-contracts-batch + exact first action + `file:line` pointers. 3. Append invariants to `DECISIONS.md`. 4. Report in the records, EXIT immediately.

## Scope edges

**In:** dotfiles `home/dot_claude/skills/plan-for-mega-goal/references/{OPERATE,invocation-template}.md` (+ GUIDE.md if it names the contract path).
**Out:** the ops-toolkit overlay file itself (ops repo; log a Proposed-addition if it needs a sync edit); every other contract item (sub-goal 02).
**Not:** restructuring the skill again; new clauses (portability only).

## Where to look

dotfiles #193/#194 history (the restructure that dropped the original); ops-toolkit `_meta/megagoals/OPERATE.md` (the overlay it must reference optionally); cockpit row ID-246.

## PR body

Portable run contract re-applied against thin+GUIDE: skill-bundled OPERATE, zero private paths (grep NC), resolution order verified. Part of mega-goal kit-absorptions (ops-toolkit `_meta/megagoals/kit-absorptions/ROADMAP.md`). Covers ID-246.

## Notes

