# Implementation notes: SPEC-236 gauntlet ops hardening

Delta from the spec only.

## 2026-08-31 validation folded, VALIDATED without operator sign-off

Context: full-lane cycle run autonomously on operator instruction ("do them all, apply kit"). The Opus panel returned 5 criticals + 6 warnings; all folded (spec DEC-005), including a full rework of the ID-489 approach (pass-container naming) after the panel proved the original symlink scheme would restart the campaign matrix nightly.
Decision: Status flipped to VALIDATED in-session; the PR is the operator's review surface, same convention as SPEC-235.
Open question for the operator: the campaign pass-container rename changes where the NEXT campaign writes; the never-installed plist is unaffected, but if you have muscle memory for `campaign-current` as a real dir, it becomes a symlink on first new-pass start.

## 2026-08-31 build + review round

Context: two Sonnet workers built on disjoint file sets; Opus review returned FIX THEN SHIP (1 critical + 2 medium + 2 low).
Decisions beyond the spec: (a) worker collision on shellcheck severity resolved lead-side with a scoped SC2012 disable in watch.sh (tier1 lints at default severity; the spec's AC said `-S warning`); (b) persist-check.sh stages under `$HOME/.cache` not bare mktemp, the colima bind-mount hazard run.sh's own header documents; (c) review critical fixed: campaign `readlink` now anchored to `GAUNTLET_DIR` (bare basename would have recreated the restart-the-matrix bug the validation round caught in its first form); (d) remote pull rsync guarded so the probe's exit survives a failed pull; (e) tutorial block trimmed of run.sh's own preamble and its assignment guidance corrected to a quoted heredoc (the block contains single quotes); (f) global AC widened to name the ride-along bookkeeping files.
