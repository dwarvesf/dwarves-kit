# Mega-goal: kit-telem-cleanup

**Destination:** The dwarves-kit telemetry produces CLEAN, trustworthy data and the SPEC-100 merge-guard loop is CLOSED. Concretely: every mega-dispatched run is tracked (carries a START line), the `misfires` detectors no longer false-flag, the test suite never pollutes the operator's real `completeness.log`, gate/gated-final PRs are auto-marked so the merge guard always has a mark to catch, and lane-classify escalates a machinery EDIT (not a mere mention). The kit-telemetry wave built the substrate + surfaced the findings; this wave makes the data actually clean.
**Quality bar:** Every fix ships with a pinned test AND a negative control (the false-flag/pollution/bypass STILL fires when the guard is removed). No detector is blinded to true positives to kill a false one. These are surgical fixes to `commands/` + `lib/`, not rewrites.
**Work repo:** `dwarves-kit` (cross-repo: roadmap here in ops-toolkit; all PRs land in dwarves-kit against `master`).
**Source cluster:** the five `#kit-telem-followup` board rows in dwarves-kit (`ID-085`/`086`/`087`/`088`/`089`), filed by the kit-telemetry mega-goal's eval + reviews.
**Stacking tool:** gh (independent sub-goals, each off `master`; merged bottom-up as the loop goes).
**Merge mode:** auto-bottom-up (the loop merges each `auto` sub-goal once its gates pass, doing the retarget-child-before-delete dance itself).
**Merge autonomy:** gated-final (the LAST sub-goal PR that completes the mega-goal is held for Han; everything before it auto-merges).
**Terminus:** build + merge. Kit-internal tooling, no runtime deploy surface; deliberately NO deploy/UAT gate. NOTE: the SPEC-073 eval RE-RUN on a START-complete corpus is deliberately NOT in this wave , it needs several days of real usage to accumulate; it stays a filed follow-up (advisor P6-4) to run later.
**Started:** 2026-07-02

## Authority

This wave EXECUTES the five `#kit-telem-followup` rows tagged in dwarves-kit `_meta/BACKLOG.md` (PR #119): ID-085 (start-wiring, HIGH), ID-086 (detectors), ID-087 (fixture isolation), ID-088 (edit-vs-mention, LOW), ID-089 (merge-mark, HIGH). Evidence base: `dwarves-kit/docs/research/2026-07-02-effectiveness-eval.md` (metrics 3 + 9 + bonus) and `.../2026-07-02-lane-rule-audit.md` (mention-vs-edit limit) and `docs/specs/SPEC-100-mega-merge-guard.md` (threat model B1). Each sub-goal gets its own SPEC via the kit lane (SDD); each is `auto` (machine-verifiable Done).

## Sub-goals

- [x] 01-start-wiring , automated mega dispatch emits `gate-ledger start` so runs are tracked (not `?`) , `auto` , PR #120 merged 8dbe47f
- [x] 02-detector-refinements , lane-telemetry boardless + shipped-incomplete stop false-flagging , `auto` , PR #121 merged d681dc0
- [x] 03-fixture-isolation , the test suite stops polluting the real `completeness.log` , `auto` , PR #122 merged 917891e
- [x] 04-merge-mark , mega opens gate/gated-final PRs as draft + `do-not-merge` (closes the SPEC-100 guard) , `auto` , PR #123 merged da0c3bb
- [x] 05-edit-vs-mention , lane-classify escalates a machinery EDIT, not a mere mention , `auto` , PR #124 merged 5f93161 (carries SG-05 + TIER-4 close; Han un-held + merged on wrap-up).

## Dependencies

- All five are INDEPENDENT (each fixes a distinct file/behavior); each branches off `master`.
- 02 benefits from 01's START data but does not require it (its tests use fixtures).
- Suggested order by leverage: 01 (unblocks the measurement layer) -> 02 -> 03 (the "clean data" trio) -> 04 (closes the guard) -> 05 (low, last). Order is flexible since none block another.

## Assumptions (resolved at decompose time, 2026-07-02)

- **ID-088 IS in scope** (sub-goal 05) per Han , small, self-contained; the loop may drop it to NOTES `## Proposed additions` if it becomes a rabbit hole.
- **No capstone eval re-run** , a START-complete corpus needs days of real usage; the re-run is a filed follow-up, not this wave. The wave's Done= is "the mechanisms that produce clean data are fixed + tested", not "the eval re-ran clean".
- **gated-final** , the final sub-goal PR is held for Han (dwarves-kit master requires CI, so full-auto would fall back to this regardless).
- **The already-leaked completeness.log lines** are NOT cleaned by SG-03 (a one-off operator action; noted in its proof).
- **Board-row flips:** the dwarves-kit rows ID-085..089 flip to shipped RIDING each sub-goal's own PR (bookkeeping-inside-feature-PR).

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
