# Sub-goal 05: lane-classify edit-vs-mention signal

**Merge policy:** auto
**Time budget:** 2-4 hours.
**Proof:** run-table , a task that only MENTIONS a machinery lib (a doc/research task about `mega-merge.sh`) classifies `normal`/`tiny`, while a task that EDITS it classifies `full`. Negative controls both directions: an edit still escalates; a mention no longer over-gates.
**Depends on:** none (independent, lowest priority; fails safe today).
Model: sonnet
Effort: medium
**Branch:** feat/kit-clean-05-editmention
**PR base:** master

## Outcome

`lib/lane-classify.sh` distinguishes EDITING a kit-machinery lib from merely MENTIONING it. Today the `kit-machinery` hard-gate matches any textual mention of a basename (`gate-ledger`, `mega-merge`, ...), so a doc/research/audit task ABOUT the machinery over-classifies to `full` (SG-03's own audit widened this surface, ID-088). Fix: give the classifier a touched-files signal (a `--files` hint, or read the branch diff) so it escalates on an actual edit to `lib/<machinery>.sh`, not on a description that names it. Lower urgency because it fails SAFE (over-gates, never under-gates), but it removes friction on the wave's own doc-heavy tasks.

## Quality bar

The signal is the TOUCHED FILES, not more regex. Prefer an explicit `--files` argument the caller passes (the diff is already known at spec->build), falling back to the current text-only behavior when no files are supplied (so nothing regresses for callers that do not pass files). Do NOT rewrite the flag-scoring model; add the edit-vs-mention discriminator as an additional signal. Keep the existing precedence (backfill > tiny > hard-gate).

## How to close the loop

Kit-adopted repo: read `AGENTS.md` first; classify + record gates before push.

```
cd dwarves-kit
# mention (should NOT escalate) vs edit (should):
bash lib/lane-classify.sh classify --files "" "explain mega-merge.sh in the architecture doc"   # normal/tiny
bash lib/lane-classify.sh classify --files "lib/mega-merge.sh" "add a guard clause"              # full
bash tests/test-lane-classify.sh                                                                  # extend with both pins
```

Proof run-table at `docs/verification/edit-vs-mention.md`. Extend `tests/test-lane-classify.sh` (SG-03's suite): mention-only -> not full; edit -> full; no-files-supplied -> current text behavior unchanged (regression guard).

**Done =** `classify` escalates a machinery lib EDIT to `full` and does NOT escalate a mere MENTION, with `--files` supplied; with no `--files`, current text-only classification is unchanged; pins + negative controls green; gates recorded.

## Handoff on completion

1. Flip 05's ROADMAP box, PR # + SHA. If this is the last sub-goal, next = the TIER-4 close gate.
2. HOT `HANDOFF.md`: next per roadmap (or the TIER-4 close).
3. WARM `DECISIONS.md`: the `--files` interface + the no-files fallback.
4. Report IN records, EXIT.

## Scope edges

**In:** the edit-vs-mention discriminator in `lib/lane-classify.sh` + its pins.
**Out:** the kit-machinery coverage set (shipped, SG-03); detectors (02); start-wiring (01).
**Not:** a classifier rewrite; new lanes; reading git history for anything beyond the touched-files of the current change.

## Where to look

`lib/lane-classify.sh` (the `kit-machinery` hard-gate + `classify_core`), `tests/test-lane-classify.sh` (SG-03's suite, extend), dwarves-kit board ID-088, `docs/research/2026-07-02-lane-rule-audit.md` (known limitation , the mention-vs-edit gap).

## PR body

lane-classify edit-vs-mention signal: escalate an EDIT to a machinery lib to `full`, not a mere MENTION (via a `--files` hint; text-only behavior unchanged without it). ID-088 (`#kit-telem-followup`). Verify: `bash tests/test-lane-classify.sh`. Proof: `docs/verification/edit-vs-mention.md`. Roadmap: ops-toolkit `_meta/megagoals/kit-telem-cleanup/ROADMAP.md`.

## Notes

<empty>
