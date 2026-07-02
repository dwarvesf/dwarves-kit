# Implementation notes: SPEC-096 mega-lane reconcile (kit-hardening SG-08)

Delta from SPEC-096 / ADR-0028 P2/P3.

## 2026-07-02 `gate` and `merge` are separate verbs, not one gate-checking `merge`

Context: the SG-08 goal file calls the negative control "load-bearing" -- a
failing/missing gate must never merge, under any flag combination.
Decision: `lib/mega-merge.sh` exposes `gate <rid> <lane>` (pure decision, zero side
effects, exit code only) and `merge <pr> <rid> <lane>` (the action, which calls
`gate` internally as its first step). `gate` is independently testable with no `gh`
in the picture at all.
Why: a single `merge` that both decides and acts is harder to prove side-effect-free
in the decision path -- a test asserting "the decision is correct" would always also
be exercising the action code. Splitting them means AC2/AC3's gate assertions never
touch `gh`, and AC3/AC4's merge assertions can assert BOTH "refused" and "never
called gh" independently.

## 2026-07-02 Dry-run is the default action, not an opt-in flag

Context: ADR-0028 names "auto-merge escaping the ship-gate" as the mis-build risk
this whole property exists to prevent.
Decision: `merge` without `--execute` always prints the `gh pr merge` command it
would run and exits 0 (a passing gate) or the BLOCKED path (a failing gate) -- it
never calls `gh` either way unless `--execute` is explicitly given.
Why: inverting the default (execute-by-default, `--dry-run` to opt out) makes the
safe path the one a caller has to remember to add under time pressure -- exactly
the shape of mistake that produces the mis-build ADR-0028 warns about. Defaulting
to dry-run means a caller that forgets the flag entirely still cannot accidentally
auto-merge anything; the worst case of "forgot a flag" is a no-op print, not a
merge.

## 2026-07-02 `MEGA_MERGE_POSTURE=per-pr-review` overrides `--execute`, not the other way around

Context: ADR-0028's "one team-facing change" section frames `merge_autonomy` as a
posture a teammate sets FOR THEIR OWN RUNS to keep human review on every PR, distinct
from the per-invocation `--execute` flag.
Decision: in `merge()`, the `per-pr-review` branch is checked and returned BEFORE the
`--execute` check, so `--posture=per-pr-review` (or the `MEGA_MERGE_POSTURE` env)
always wins over `--execute` -- a run configured for per-PR review cannot be
accidentally executed by a stray `--execute` on one invocation.
Why: the run-level posture is meant to be the team's safety configuration, not a
per-call convenience; if `--execute` could override it, the posture knob would not
actually guarantee "a human reviews every PR" the way ADR-0028 describes it.

## 2026-07-02 `gate` reuses `lib/gate-ledger.sh check` verbatim; no second required-gate list

Context: `hooks/ship-gate.sh` already computes "does this lane's ledger satisfy its
required gates" via `lib/gate-ledger.sh check <lane> <rid>` at push time.
Decision: `lib/mega-merge.sh gate` is a one-line call to that same function, not a
re-derivation of the lane x phase matrix or a second copy of the required-gate
list.
Why: two copies of "what gates does lane X require" drift over time (a WORKFLOW.md
matrix edit would need to land in two places); calling the existing function means
the auto-merge path and the push-time ship-gate can never disagree about whether a
run is ship-ready. This is the same "reuse, do not reinvent" instruction SPEC-095
followed for the deployable classifier.

## 2026-07-02 `commands/mega.md` reuses SPEC-034's scaffold conventions, and explicitly supersedes only its auto-merge stance

Context: SPEC-034 (`Status: VALIDATED`, ID-037) already designed `/kit:mega`'s
roadmap conventions (home, line shape, single-chain gate) but was never built (no
`commands/mega.md` existed on `main` before this spec), and its DEC-009 said
"Auto-merge. Merge stays human, at `/kit:ship`" -- written before ADR-0028 existed.
Decision: `commands/mega.md` is written against SPEC-034's DEC-002/DEC-007/DEC-008
(roadmap home, branch-chain naming, single-chain gate) unchanged, and against
`lib/orchestrate.sh`'s already-shipped directory contract (`ROADMAP.md`,
`goals/NN-*.md`, `POINTER_PROMPT.md`, `HANDOFF.md`, `DECISIONS.md` -- which itself
already diverged from SPEC-034's "no NOTES.md/FEEDBACK.md" stance by adding the
HOT/WARM `HANDOFF.md`/`DECISIONS.md` pair under SPEC-087). Only SPEC-034 DEC-009 is
explicitly superseded, and only for `auto`-tagged sub-goals -- `gate`-tagged
sub-goals and the held final PR still merge by human hand exactly as SPEC-034
intended.
Why: SPEC-034's non-merge conventions are still correct and already have a live
consumer (`lib/orchestrate.sh`); re-deriving them would risk drifting from what the
driver actually expects. Only the specific decision ADR-0028 changed (auto-merge
policy) needed to change; everything else SPEC-034 got right stays as-is.

## 2026-07-02 The dynamic-injection skill (SPEC-034 TASK-004) is out of scope here, and why that is not a gap

Context: SPEC-034 TASK-004 proposed a small skill that re-surfaces the next
unchecked sub-goal every turn, because the built-in `/goal`/`ralph-loop` activators
were verified (via claude-code-guide, SPEC-034's own research) to re-inject only
literal prompt text, never auto-re-reading referenced files.
Decision: not built as part of this spec. `lib/orchestrate.sh` (SPEC-087,
already shipped) is a non-LLM bash driver that reads `ROADMAP.md` fresh on every
`cmd_next` call by construction -- it has no "stale re-injected text" failure mode
to begin with, so the injection skill's reason for existing does not apply to that
path.
Why: building the injection skill now would be solving a problem `orchestrate.sh`
does not have. A team driving `/kit:mega`'s scaffold under bare `/goal` (without
`orchestrate.sh`) still has the original problem and should install the ops-toolkit
`plan-for-mega-goal` skill, which already ships the equivalent re-surfacing
behavior as part of its pointer convention.

## Deviations from the SG-08 goal file

None. The goal file's contract (mirror the skill's three beats in `commands/mega.md`;
`gate`/`merge` split in `lib/mega-merge.sh` with dry-run default and the
load-bearing negative control; deploy/UAT terminus via SG-07's `deployable`
verb) is implemented as specified.
