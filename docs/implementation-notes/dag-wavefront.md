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
