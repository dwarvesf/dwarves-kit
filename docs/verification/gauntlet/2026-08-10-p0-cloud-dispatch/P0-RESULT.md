# SPEC-230 P0 platform verification: FAILED

Date: 2026-08-10. Both probes recorded. Verdict: **the spec's dispatch
mechanism does not work as designed in this harness.** Build does not
proceed on Approach A via the Agent tool.

## The finding in one line

`Agent(isolation:"remote")` in this Claude Code harness does NOT dispatch to
a Claude Code cloud environment. It silently creates a LOCAL git worktree on
this Mac and runs the agent there, with full inherited credentials. Remote
isolation via the Agent tool is not backed by a cloud sandbox boundary.

## P0.1: headless `claude -p` dispatching `Agent(isolation:"remote")`

Ran a headless `claude -p --dangerously-skip-permissions` process instructed
to dispatch one remote agent that reports `uname -a` and `pwd`.

- Result: `P01-RESULT: OK` in ~21s, no VM provisioning delay.
- The agent reported `Darwin Mac 25.5.0 arm64`, cwd
  `.../ops-toolkit/.claude/worktrees/agent-a03df257...`.
- Conclusion: ran LOCALLY in a worktree, not a cloud VM. Fast wall-clock
  confirms no VM spin-up. Pass criterion (remote agent runs in a controllable
  cloud env) NOT met.

## P0.2: interactive session dispatching `Agent(isolation:"remote")` for recon

Dispatched a recon probe with `isolation: "remote"` from the interactive
session. Full report in this dir. Key rows:

| Check | Result | Meaning |
|---|---|---|
| OS | `Darwin`, no `/etc/os-release` | native macOS, not a Linux container |
| user / HOME | `tieubao` / `/Users/tieubao` | real local account, not a throwaway |
| pwd | `.../ops-toolkit/.claude/worktrees/agent-a9cfab24...` | a worktree of the REAL local checkout |
| private repo auth | `git ls-remote` on private `tieubao/ops-toolkit` succeeded | inherited real gh-backed GitHub auth |
| push capability | `git push --dry-run` reported `[new branch]` | real write access, not scoped |
| network | github/npm 200, deepseek 401 (reachable), none blocked | unrestricted host network |
| permission prompts | none anywhere | no sandbox boundary |

Conclusion: a "remote" subagent lands inside the real ops-toolkit worktree on
this Mac with the operator's real credentials and unrestricted network. There
is no cloud VM, no fresh clone, no credential scoping, no isolation boundary.

## Why (root cause)

The spec conflated two different Claude Code features:

1. `Agent(isolation:"remote")` , a local-harness subagent isolation knob. In
   this build it resolves to a local git worktree (same family as
   `isolation:"worktree"`), NOT a cloud dispatch.
2. Claude Code CLOUD ENVIRONMENTS , the actual on-demand cloud VMs, driven by
   `claude --cloud` / claude.ai/code web sessions / the mobile app, selected
   by `/remote-env`. These are a SESSION launch mode, not a subagent dispatch
   target reachable from the Agent tool.

SPEC-230 assumed (1) would deliver (2). It does not. The cloud VM cannot be
made the gauntlet room by dispatching a remote subagent.

## Impact on SPEC-230

- Approach A (probe dispatches as `Agent(isolation:"remote")`, the VM is the
  room) is NOT buildable through the Agent tool in this harness. Blocked.
- The spec's own named fallback stands: Approach B (ephemeral CI runner) keeps
  every property that motivated cloud and is unblocked.
- A THIRD path exists and was not in the spec: drive a real cloud session
  (`claude --cloud` or the web/mobile UI against the target repo + a
  configured environment) as the probe, with the orchestrator handing it the
  seed card. This is the genuine "cloud VM as the room" route, but it is a
  session launch, not an Agent-tool dispatch, so the orchestration model
  differs from what the spec drew. Needs its own P0 (can a session be
  launched + driven programmatically from the orchestrator, or is it
  human-initiated only?).

## P0.3: can the orchestrator LAUNCH a real cloud session programmatically? NO

Path C was "drive a genuine `claude --cloud` session as the probe". Tested the
actual CLI surface (`claude --help`):

- `claude --cloud [desc] -p` -> `Error: --cloud cannot be combined with
  --print. Cloud sessions are interactive only.`
- `claude --cloud "<desc>" </dev/null` -> `Error: --cloud requires an
  interactive terminal. Non-interactive invocations ... run locally and would
  silently ignore --cloud. Drop --cloud, or run from a TTY.`

Conclusion: a cloud session can ONLY be started from a human TTY (or the
claude.ai/code web / mobile UI). It cannot be launched from a script, a
headless `claude -p`, or the gauntlet orchestrator's tools. `claude agents
--json` can LIST sessions (scriptable), but nothing can START a cloud one
without a human at a terminal. Path C fails for programmatic orchestration.

## Runner decision (all three cloud routes exhausted)

| Route | Mechanism | Verdict |
|---|---|---|
| A. remote subagent | `Agent(isolation:"remote")` | FAIL: resolves to a local worktree, no cloud VM (P0.1, P0.2) |
| C. programmatic cloud session | `claude --cloud` from the orchestrator | FAIL: TTY-only, cannot be scripted (P0.3) |
| B. ephemeral CI runner | `gh workflow run` builds the room, runs the probe | VIABLE, fully scriptable, keeps the spend-capped key |
| Mini (today) | `runner_host=<ssh alias>` in run-remote.sh | WORKS now |

Cloud remains usable for Han's ORIGINAL phone/no-laptop and manual "few dozen
tasks" case via the claude.ai/code WEB UI (human-initiated parallel tasks) ,
that is real and unblocked , but it is a MANUAL surface, not a kit-automated
`runner_host`. The gauntlet's programmatic loop cannot use it.

## Next

- SPEC-230's automated-cloud-runner premise is dead (A and C both failed).
  Rewrite the spec to: (1) keep the config knob + root-only-read security fix
  (still valuable on their own), (2) make `runner_host = "cloud"` mean the CI
  runner (Approach B), not a remote subagent, (3) move genuine cloud-VM use to
  a documented MANUAL web-UI path in the research doc, not a kit runner.
- OR: ship the smaller win now , the config security fix + Mini runner
  polish , and park the CI-runner build as its own row.
- Han picks B-build vs park-and-ship-fix.

## Artifacts left in the cloud-probe worktree

`/tmp/p02-til` (clone + local branch `p02-probe-test`, never pushed). Harmless;
in a worktree of the real repo, so sweep with the other worktrees.
