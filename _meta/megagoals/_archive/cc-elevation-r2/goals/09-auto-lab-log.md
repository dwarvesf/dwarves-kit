# Sub-goal 09: Auto-draft the session-close LAB_LOG entry

**Time budget:** ~2-3h
**Depends on:** none (extends cc-harvest, PR #267)
**Branch:** feat/cc-elev-r2-09-lab-log
**PR base:** main

## Outcome

Extend cc-harvest with an auto-LAB_LOG-draft mode (the in-repo redirect of the old Stop->Notion idea): on `SessionEnd`, a cheap Haiku pass over the transcript drafts a candidate `_meta/LAB_LOG.md` entry in the repo's exact format (newest-first `## YYYY-MM-DD · slug: title` block, hygiene-compliant: index-not-record, no narrative arcs, no commit-message restating, 5-10 line budget) and STAGES it to a draft file for review. It does NOT write LAB_LOG.md directly. Complements cc-harvest (ledger) and `/wrap-session` (manual draft) by making the draft automatic so it is ready even if I forget.

## Quality bar

Propose-don't-dispose: stages a draft (e.g. `_meta/.lab-log-draft.md`), never edits LAB_LOG.md itself. Hygiene-compliant output (verified against a real LAB_LOG entry's shape). Reuses cc-harvest's transcript-read + extractor (no second parser). Privacy = cc-harvest's (transcript already in-session; output stays in the private repo, no external push). No mini.ollama.

## How to close the loop

- Add the lab-log-draft mode to cc-harvest (SessionEnd); format the block per the LAB_LOG shape; stage to the draft file.
- Given a fixture transcript of a substantive session: it stages a hygiene-compliant block (right header, <=10 lines, no narrative); given a trivial/no-op session: it stages nothing (negative control); confirm it never touches LAB_LOG.md.
- Lane via lane-classify; extend `tools/cc-harvest/docs/proof-of-done.md` (now multi-feature) with the draft run + the no-op control.

**Done =** on SessionEnd, cc-harvest drafts a hygiene-compliant LAB_LOG block to a staging file (never LAB_LOG.md) for a substantive fixture and stages nothing for a trivial one, reusing the existing transcript-read; proof updated; on PR #NN.

## Scope edges

**In:** the lab-log-draft mode in `tools/cc-harvest/` + staging + tests + proof + dotfiles one-line wire (SessionEnd).
**Out:** auto-writing LAB_LOG.md (human reviews + commits it into the feature PR per SPEC-005); replacing /wrap-session; the ledger harvest (already shipped).
**Not:** pushing anything external (the whole point of the redirect).

## Where to look

cc-harvest's existing transcript-read + extractor (PR #267), the LAB_LOG format + hygiene rules (CLAUDE.md "Log hygiene" + the newest entries), the `SessionEnd` payload, the `/wrap-session` skill, SPEC-005 session-closer.

## PR body

Outcome: cc-harvest gains an auto-LAB_LOG-draft mode (SessionEnd -> staged hygiene-compliant draft; never auto-writes LAB_LOG.md). In-repo redirect of the old Stop->Notion idea.
Verify: substantive fixture stages a compliant block; trivial session stages nothing; LAB_LOG.md untouched.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 09).

## Notes
