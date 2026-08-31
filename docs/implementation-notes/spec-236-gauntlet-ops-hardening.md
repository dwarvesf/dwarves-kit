# Implementation notes: SPEC-236 gauntlet ops hardening

Delta from the spec only.

## 2026-08-31 validation folded, VALIDATED without operator sign-off

Context: full-lane cycle run autonomously on operator instruction ("do them all, apply kit"). The Opus panel returned 5 criticals + 6 warnings; all folded (spec DEC-005), including a full rework of the ID-489 approach (pass-container naming) after the panel proved the original symlink scheme would restart the campaign matrix nightly.
Decision: Status flipped to VALIDATED in-session; the PR is the operator's review surface, same convention as SPEC-235.
Open question for the operator: the campaign pass-container rename changes where the NEXT campaign writes; the never-installed plist is unaffected, but if you have muscle memory for `campaign-current` as a real dir, it becomes a symlink on first new-pass start.
