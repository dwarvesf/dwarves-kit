# SG-04: dwarves-kit context-hygiene implementation

Merge policy: gate
Time budget: ~1-2 sessions
Depends on: SG-03 (design must be approved first)

## Directional outcome
Implement the SG-03 design in dwarves-kit: subagent returns come back summarized, and the
mega-goal loop emits a post-sub-goal checkpoint signal. Resolve exact behavior from SG-03's
approved SPEC.

## Done =
In `dwarves-kit`: the changes from the SG-03 SPEC are implemented and the kit's own tests
pass; PR opened. `gate` (shared repo, team review + team buy-in before merge).

## Close the loop (verification)
```
# in the dwarves-kit checkout
bash tests/<relevant>.sh        # kit test suite for the changed paths (resolve at execution)
```
Plus a manual demo: a small 2-sub-goal mega-goal run shows (a) summarized subagent returns
in the lead and (b) the checkpoint signal after each sub-goal. Capture as proof.

## Scope edges
Only the behaviors in SG-03's SPEC. Do NOT change unrelated kit lanes. Shared repo: keep
the change behind a flag/default that does not surprise other contributors; do not
auto-merge.

## Where to look
SG-03's merged SPEC + ADR; `~/.claude/dwarves-kit/` WORKFLOW.md + execute/dispatch lib.
This sub-goal resolves its details from SG-03's output (do not pre-guess the interface).

## PR body
feat(kit): summarize subagent returns + post-sub-goal checkpoint signal. Implements the
SG-03 SPEC. Gated for team review.
