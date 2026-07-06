# NOTES: harness-observatory

## Active blockers

(none yet; updated in place, one fingerprint per blocker: command · failure · prerequisite · last verified)

## Proposed additions

- (append-only; discovered sub-goals + skill/tooling friction land here, never inline)
- Scope-cut REVERSED 2026-07-04: ID-250/257/259 now live in the sibling mega kit-absorptions; ID-258 adopted as practice there (nothing to build).
- 04-anomalies-advisor root-caused the kit_runs/lane-telemetry pre-existing issue (SG-01/02/03 flagged it, none dug further): a bash 3.2 `source`/`return`/`set -e` interaction makes `read_kit()`'s subprocess into `lane-telemetry.sh` abort silently in this local environment. Not fixed (out of scope for this tool); a real fix would live in dwarves-kit's `lane-telemetry.sh` itself (e.g. avoid a top-level `return` after a `set -e` re-arm, or guard the subprocess call differently). Filed here for whoever picks up `kit_runs` reliability next.

## Event log

- 2026-07-04 drafted (8 sub-goals); RESTRUCTURED same day after Han's completeness challenge: now 6 ops-only sub-goals, the dotfiles/kit work moved to the sibling mega kit-absorptions (9 sub-goals), runs in parallel. Launch pending Han's go + the family PR merge (Assumption 6).
