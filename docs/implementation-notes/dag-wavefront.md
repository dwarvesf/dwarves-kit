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

## 2026-07-03 , Q1 resolved provisionally (Option B) + first revision applied

Han away >60s on the Q1 scope ask -> took **Option B** (opt-in Touches; generator/schema retrofit =
follow-up ID-085-followup). Rationale: scope-faithful to the brief, fully reversible, A = B + generator
(no rework). Applied all ~19 mechanical fixes. Committed 1b9726f. See spec DEC-006..DEC-011.

## 2026-07-03 , second revision (delta re-validation found 3 real new bugs)

Fresh-context re-validation caught bugs the first revision introduced. Applied:
- **Byte-identity fix (was false):** `_ready_set` returns ALL unchecked when no deps (nothing blocks),
  so raw ready size is N, not 1. Size-dispatch now keys on ADMITTED (post-`_wave_gate`) size: admitted
  <=1 -> untouched serial body on the first ready pick; admitted>=2 -> wave. admitted==0 (Touches-less,
  the real case) -> serial fallback -> byte-identical. Corrects the earlier wrong premise.
- **`_wave_gate` admission:** a candidate is admitted iff it declares its OWN `## Touches` AND proves
  disjoint vs every already-admitted member (`gate_plan` admits the first vacuously, so self-Touches is
  the real opt-in gate). Touches-less -> never admitted -> serial.
- **Per-edge HANDOFF keyed on DEPENDENTS, not deps:** a sub-goal writes `HANDOFF-<own-id>.md` iff
  something `depends` on it; the read side falls back to plain `HANDOFF.md` when the per-edge file is
  absent. Fixes feed-forward loss at every chain's root.
- **`WAVE_CAP` default = 1 (was 2), a deliberate deviation from the brief.** At default 2, existing
  mega-goals whose `gate` meant global-stop silently migrate to chain-stop , exactly the linear-chain
  regression the goal forbids ("any regression on it is a failed goal"). Default 1 => serial path
  always, gate stays global, byte-identical; waves + chain-`gate` activate only when the operator sets
  `WAVE_CAP>=2`. Conservative-everywhere per the quality bar. This overrides the brief's "cap default 2".
- **Flip-contract injection deferred:** a real wave session needs the `cmd_flip <abs-megadir> <id>`
  instruction injected into its prompt (else it edits its worktree's ROADMAP copy, invisible to the
  driver). That prompt/authoring change bundles with ID-085-followup (real-wave activation); the
  machinery + mock-barrier tests ship now, real waves activate in the followup. Documented as inert.
- **Split convergence into its own task** (TASK-004c) so the missing-merge closure has its own
  acceptance, not proven only transitively.

## 2026-07-03 14:30 , TASK-000 extract _run_one_session

**Context.** The spec keys the helper on `dir id pfile route_flags`, but the three run-paths also
read `stream` (a `cmd_run` local, set from `--stream`) and must return both the exit code and the
`slog` stream-log path that post-session logic (grounded completion, deterministic handoff) consumes.
**Decision.** Passed `stream` as an explicit 5th positional arg (`dir id pfile route_flags stream`);
exposed `slog` via a global `_ROS_SLOG` that the caller reads immediately after the call
(`slog="$_ROS_SLOG"`). Return value carries `rc` via `|| rc=$?` at the call site, matching the
former inline capture.
**Why.** bash 3.2 has no namerefs, so a return-by-name for `slog` uses a well-known global; `stream`
is a local not a global so it cannot be read implicitly like `WATCHDOG_STALL_SECS`/`DETERMINISTIC_HANDOFF`.
**Impact.** Zero behavior change: the watchdog / stream-json / plain branches moved verbatim (comments
included). tests/test-orchestrate.sh 59/59 green, tests/test-meta.sh 578/578 green, before and after.

## 2026-07-03 , TASK-001 add _ready_set + source guard for unit-testability

**Context.** TASK-001 adds the pure `_ready_set` read helper. Its unit test needs to call the
internal function directly (it is intentionally NOT wired into any CLI subcommand this task), but
`orchestrate.sh` ended with an unconditional `main "$@"`, so sourcing it fired `main` (usage +
`exit 64`) and killed the sourced test before any assert.
**Decision.** Wrapped the tail call in the source guard `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
main "$@"; fi`, the exact pattern already in `lib/dispatch-gate.sh:208`. The new test SOURCES
orchestrate.sh and calls `_ready_set` / `_next` directly.
**Why.** House pattern (not an invention); behavior-preserving when executed (`bash orchestrate.sh
<cmd>` still runs main because `BASH_SOURCE[0] == $0`). Alternative rejected: adding a hidden
`ready` subcommand, which would add CLI surface the spec did not ask for and risk reading as
scheduling wiring.
**Ready-set edge behavior (pinned by the fixtures).** (a) no-deps ROADMAP -> ALL unchecked returned
in ROADMAP order, first line == `_next` (size-1 superset invariant tested every cycle); (b) diamond
-> root alone, then {SG-02,SG-03} as a wave, then the join, cycle by cycle; (c) all-checked ->
empty output, matching empty `_next`. Reused `_subgoals`/`_sg_line`/`_sg_deps_blocked` verbatim, no
dep parsing reimplemented. Process-sub loop (`< <(_subgoals ...)`) not a pipe, matching
`_derive_board` L172, so the caller shell owns the loop under `set -uo pipefail`.
**Impact.** `bash tests/test-orchestrate-wavefront.sh` 16/16 green (bash 3.2.57 + default);
`bash tests/test-orchestrate.sh` 59/59 green (no regression). No scheduling change; `_ready_set`
has zero call sites in the run loop (TASK-004b wires it later).
