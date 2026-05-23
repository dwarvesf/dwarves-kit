# 0020. Lock the dispatch primitive: in-session worktree subagents, not the agent view

Date: 2026-05-22
Status: Accepted
Relates-to: SPEC-032 (concurrent goal dispatch), SPEC-033 (dispatch-primitive spike),
`docs/research/2026-05-22-claude-code-agent-views.md`

## Decision (one line)

`/kit:dispatch` fans out via **in-session `Agent(run_in_background: true, isolation:
"worktree")` workers polled with the `Task*` tools (Path A).** The Claude Code "agent
view" (`claude agents`) is a human-facing monitor, **not** the dispatch control plane;
Path B is rejected for programmatic orchestration.

## Context

SPEC-032 committed to Path A on assumption, never executed. The maintainer separately
asked whether the new "agent view" (Path B) could manage the session lifecycle for a
concurrent workflow. SPEC-033 ran the same toy workload through both primitives on
Claude Code **v2.1.148** to settle it with evidence: two disjoint toy specs
(`spec-x` writes `a/**`, `spec-y` writes `b/**`), each run as one worker, observed on
fixed axes.

## Evidence

**Path A (in-session subagents), ran clean.**
- Two `Agent(run_in_background: true, isolation: "worktree")` workers launched
  **non-blocking**; the lead got control back immediately and did other git work while
  they ran, then received completion notifications (9.3s, 17.5s on Haiku).
- Each worker got its own worktree `.claude/worktrees/agent-<id>`, created on an
  auto-named branch `worktree-agent-<id>`; the worker then `git switch -c goal/<slug>`
  inside it and committed cleanly (no hook block once the subject was conventional).
- The lead **collected both branches** from the main checkout without switching:
  `git show goal/spec-y:b/hello.txt` → `y`. Both `goal/spec-x` (1d7e602) and
  `goal/spec-y` (d3c625f) visible via `git branch`.
- The drift guard (`gate.sh drift`) returned **CLEAN** on both real branches; the
  disjointness gate returned **DISJOINT** on the pair. The pure-bash moat works.

**Path B (agent view), not a programmable dispatcher.**
- `claude agents --json` lists live sessions and is scriptable (no TTY needed), but it
  is **read-only / monitor-only**.
- **There is no CLI verb to create a background session.** `claude agents`' flags
  (`--model`, `--effort`, `--permission-mode`, `--mcp-config`) are *defaults for
  sessions dispatched FROM the agent view* (the interactive TUI). Creation happens in
  the TUI or via `/bg` inside a session. The earlier-researched
  `claude --bg "<prompt>"` **does not exist** on v2.1.148.
- The Path A worktree subagents **do not appear in `claude agents`** at all (12
  interactive sessions, **0** background, **0** under `.claude/worktrees`). Path A and
  the agent view are separate layers; the agent view cannot observe or manage in-session
  fan-out.

## Verdict table

| Axis | Path A (in-session subagents) | Path B (agent view) | Winner |
|---|---|---|---|
| Scriptable fan-out (create N workers) | YES, `Agent(run_in_background, isolation:worktree)` | NO, create is interactive (TUI / `/bg`) | **A** |
| Non-blocking poll | YES, lead free immediately; `Task*` + notifications | monitor is scriptable (`agents --json`) but nothing to poll | **A** |
| N branches collectable by lead | YES, `git show goal/<slug>:<file>` | n/a, couldn't launch | **A** |
| Worker isolation | YES, `.claude/worktrees/agent-<id>`, own branch | YES, per-session worktree | tie |
| Durability on lead exit | none in-flight; commits survive as branches (documented) | survives (daemon-hosted) but moot, can't launch | B (moot) |
| Convergence ergonomics (SPEC-031) | in-process git collection in one session | cross-process; can't even create | **A** |
| Visible in agent view | NO | YES (it is the agent view) | n/a |
| Cost to kit (bash-over-binaries) | reuses harness tools, no new binary | shells to `claude`, but the creation gap kills it | **A** |

**Verdict: Path A, decisively.** SPEC-032's chosen Approach 1 is validated by execution.

## Consequences

- **SPEC-032 `## Solution` needs no change.** Its primitive is correct. Three
  implementation notes the spike surfaced for the build:
  1. `isolation: "worktree"` creates the worktree on an **auto-named branch**
     (`worktree-agent-<id>`). The worker must explicitly `git switch -c goal/<slug>`
     inside it; the dispatcher's worker prompt (SPEC-032 TASK-006/007) must include that
     step or the goal branch will not exist under the expected name.
  2. **Worktrees are left LOCKED after a worker completes** (not auto-cleaned, because
     they carry commits). The spike left 2 orphan worktrees. SPEC-032 TASK-008's
     worktree GC is therefore **necessary, not speculative**, and a plain `git worktree
     remove --force` is **not enough**: the harness locks the worktree
     (`cannot remove a locked working tree`), so GC must `git worktree unlock <path>`
     then `git worktree remove --force <path>` (or `remove -f -f`), then `git branch -D
     goal/<slug>` once detached.
  3. The repo's **conventional-commit hook applies to workers.** SPEC-032's worker
     prompt must instruct conventional subjects (`type(scope): summary`) or worker
     commits are blocked.
- **The agent view is out of the programmatic dispatch path.** It MAY be offered to
  downstream users as a human observation surface ("watch your goals in `claude
  agents`"), but `/kit:dispatch` must not be built on `claude agents`.
- **Maintainer's question answered:** you can *monitor* sessions via `claude agents
  --json`, but you cannot *create or manage* background sessions or in-session subagents
  from the agent view. For a concurrent orchestrator the control plane is the in-session
  `Agent` + `Task*` tools.
- **Durability:** Path A workers are tied to the lead session (in-flight workers die on
  lead exit; committed work survives as branches; documented, not destructively tested
  on a live session). This matches SPEC-032 DEC-002 / Edge-Case-4 and the maintainer's
  "tab-away, session stays open, no durability" decision. Acceptable.

## Numbering (linearized 2026-05-22)

The 0017-0020 block was linearized by logical dependency order: the C2/C1 boundary
ADRs precede the dispatch primitive that rides on them.

| # | ADR | State |
|---|---|---|
| 0017 | mega-decomposition-lane | exists |
| 0018 | v-model-phase-frame (SPEC-031 TASK-001) | to be written |
| 0019 | parallel-execution-boundary (SPEC-032 TASK-001) | to be written |
| 0020 | dispatch-primitive-lock (this ADR) | exists |

SPEC-031 and SPEC-032 task text were updated to match.
