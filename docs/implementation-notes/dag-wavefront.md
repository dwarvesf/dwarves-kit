# Implementation notes , DAG-wavefront scheduling (ID-084)

Delta log from `DECISION-BRIEF-dag-wavefront.md` + ADR-0030. Only decisions the brief/ADR
did NOT pin. Started before code.

## 2026-07-03 , Gate Zero + build setup

**Context.** Gate Zero (ADR-0028 defers DAG work) required an Accepted amendment before code.
**Decision.** Drafted ADR-0030 (narrow amendment: wavefront in, GSD-v2 out), cited the brief +
kit-telemetry serial-cost data. Han blessed it explicitly in the goal loop; Status flipped to
Accepted (2026-07-03). Committed as the branch's first commit (2900e72).
**Why note it.** The brief said "mini-ADR amending ADR-0028's deferral scope" but did not pin the
ADR number or motivation sourcing; recorded here for traceability.

**Deviation , worktree policy.** Global CLAUDE.md mandates native `EnterWorktree` for committable
work. This session's cwd is pinned to `ops-toolkit`, a DIFFERENT repo from the build target
(`dwarves-kit`, one level over), and `EnterWorktree` keys off the session repo, so it created the
worktree in the wrong repo. Native cross-repo worktree is not reachable here.
**Decision.** Build on a plain feature branch `feat/dag-wavefront` in dwarves-kit's main checkout.
**Why acceptable.** This is a single-writer, single-branch build; the worktree policy exists to stop
parallel-writer `index.lock` corruption, which does not apply. `/kit:execute`'s worker subagents
manage their own isolation internally. No hand `git worktree add` was used (that is separately
forbidden); a plain branch is the fallback.
**Alternatives rejected.** (a) manual `git -C dwarves-kit worktree add` , forbidden by CLAUDE.md;
(b) delegate the whole SDD loop to one `Agent(isolation:worktree, cwd:dwarves-kit)` , too coarse for
an interactive kit command loop where the lead drives `/spec` -> `/spec-validate` -> `/kit:execute`.

## 2026-07-03 , spec-validate found a load-bearing gap the brief missed (STOP for Han)

**Context.** 5-lens adversarial spec-validate on SPEC-106.
**Finding (V-CRIT-1).** The brief's central reuse claim ("reuse `dispatch-gate.sh` across wave
pairs") assumes sub-goals declare `## Touches`. Evidence: 0 of 684 real sub-goal files have it, and
no generator emits one. `gate_disjoint` returns exit-2 REJECT without Touches -> `gate_plan`
serializes -> concurrency is inert on every real mega-goal. The brief's own "unprovable = serialize
(conservative)" becomes the always-case.
**Why this is a STOP, not a proceed.** It is a scope decision the brief + ADR-0030 do not cover
(Option A expands scope into the sub-goal generator; Option B ships opt-in + defers). A and B change
the task list and whether the feature works on real data now. The goal says "EXECUTES that brief,
does not re-design" + "unclassifiable state = stop with a reason" -> autonomy gate. Recorded as
SPEC-106 Open-question Q1 with a recommendation (Option A minimal). Loop stopped; `.planning/
BLOCKER-spec-touches.md` written.
**The ~19 mechanical findings** (ROADMAP-in-worktree flip target, convergence task, greedy
admission, `_run_one_session` extraction, TASK-004 split, per-edge HANDOFF write-side, `gate!`,
`WAVE_CAP`, mkdir-lock hardening, mock-barrier test, gitignore, etc.) are captured in the spec's
`## Review` section and will be applied in ONE coherent revision AFTER Q1 is decided (they interact
with the task list Q1 reshapes), to avoid revising twice.
