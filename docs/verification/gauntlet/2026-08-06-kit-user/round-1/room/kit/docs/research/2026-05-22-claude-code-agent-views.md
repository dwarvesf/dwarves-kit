---
title: Claude Code agent view + session-lifecycle primitives (for concurrent dispatch)
date: 2026-05-22
source: claude-code-guide agent sweep of docs.claude.com / platform.claude.com / CC changelog (May 2026); cross-checked against the harness tool surface in this session
feeds: SPEC-032 (ID-035, concurrent goal dispatch); refines the parallelism menu in docs/research/2026-05-22-concurrent-goal-dispatch.md (section 3, option 4)
benchmarked_against: docs/specs/SPEC-032-concurrent-goal-dispatch.md (chosen approach), docs/specs/SPEC-031-v-model-and-convergence.md (convergence contract), docs/PHILOSOPHY.md (bash-over-binaries, no Node/Python in hooks)
status: active
---

# Claude Code agent view + session lifecycle

Companion to `2026-05-22-concurrent-goal-dispatch.md`. That note decided the *model*
(one autonomous worker per goal, fan out, escalate on blockers). This note answers a
narrower question the maintainer raised: **is the new "agent view" a control plane I
can drive the session lifecycle from, and does it change SPEC-032's chosen primitive?**

Short answer: agent view is a **monitoring UI, not an orchestration engine**. It
surfaces a *second* dispatch primitive (`claude --bg` background sessions) that is
distinct from the in-session `run_in_background` + `isolation: worktree` subagents
SPEC-032 currently commits to. That distinction is the one real decision this note
forces; see section 4.

---

## 1. What "agent view" is

- Official feature, **research preview, shipped 2026-05-11, needs CC v2.1.139+**.
- One CLI dashboard (`claude agents`) over all **background sessions**, grouped by
  state (Pinned / Ready-for-review / Needs-input / Working / Completed), each row an
  independent full CC session hosted by a **supervisor daemon** (`~/.claude/daemon/`),
  each auto-moved into its own git worktree (`.claude/worktrees/<id>/`).
- It is the UI for the supervisor; it does not own scheduling, ordering, or merge.

Source: https://code.claude.com/docs/en/agent-view

## 2. Session-lifecycle control (the verbs)

Scriptable via the `claude` CLI (no SDK, no API key beyond existing CC auth):

```
claude --bg [--name N] "<prompt>"   create (detached background session)
claude agents --json                list (pid, cwd, sessionId, name, status)
claude logs <id>                    get output / status
claude attach <id>                  continue interactively
claude stop|kill <id>               stop
claude respawn <id> | --all         restart, conversation intact
claude rm <id>                      remove + worktree GC (if clean)
claude daemon status                supervisor health
```

In-session equivalents (NOT scriptable): `/bg`, `/agents`, `/tasks`. Cloud/headless
equivalent: the Agent SDK managed-agents API (coordinator -> <=25 worker threads),
but that runs in Anthropic-hosted VMs and breaks the bash-over-binaries thesis, so
it is out for the kit.

**Gap that matters for us:** `agents --json` is read-only and thin (no
deps/priority/progress fields). Any ordering or wait-queue logic is ours to own. That
is consistent with SPEC-032's "no DAG, no scheduler" line.

## 3. Concurrency model

- Isolation: per-session git worktree (or `worktree.bgIsolation: "none"` to opt out).
  Each session/subagent gets its own context window; no history transfer.
- Limits: background sessions effectively unbounded (token quota is the real cap);
  SDK multiagent caps at 25 threads.
- Result flow: **no auto-upstreaming.** You read results via `claude logs` / peek
  panel / attach, or (in-session) the subagent returns a summary to the lead. The
  orchestrator synthesizes; nothing merges for you.

## 4. The fork this forces on SPEC-032

SPEC-032's chosen approach (Approach 1) fans out **in-session** workers:
`Agent(run_in_background: true, isolation: "worktree")`, managed by the lead via the
`Task*` tools (`TaskList`/`TaskGet`/`TaskOutput`/`TaskStop`). The agent view I was
asked to research is a **different** primitive. They are not interchangeable:

| Axis | Path A: in-session subagents (SPEC-032 today) | Path B: `claude --bg` agent-view sessions |
|---|---|---|
| Spawned by | Agent tool, inside the lead session | `claude --bg` CLI, separate OS process |
| Managed by | `Task*` tools in-session | `claude agents` CLI + `--json` poll |
| Host | the lead session | supervisor daemon |
| Durability | lead dies -> workers die (commits survive as branches) | survives lead exit (daemon-hosted) |
| Worktree isolation | `isolation: "worktree"` (explicit) | automatic per session |
| Fit to maintainer ask | "tab-away, session stays open, no durability" -> matches | adds durability the maintainer said isn't needed |
| Fit to "use the agent view" curiosity | not the agent view at all | this *is* the agent view |
| Convergence model | lead reads Task output, converges in-session | lead reads `claude logs`, converges across processes |
| Cost to the kit | uses primitives already in the harness | shells out to `claude` subcommands (bash-friendly) |

**The tension:** the maintainer's documented decision ("tab-away, session stays open,
no durability") points at Path A, and SPEC-032 is built on it. But the maintainer's
*stated curiosity* ("can I use the agent view to manage the session lifecycle?") is
literally Path B. They are not the same code path, and the kit cannot claim to "use
the agent view" while building on in-session subagents. The prototype is where this
gets resolved with evidence instead of assumption.

## 5. Gotchas for an orchestrator (both paths)

- Token cost scales linearly with worker count (use Haiku workers, prompt caching).
- Rate limits are shared across all concurrent workers (stagger launches).
- Path B adds a supervisor SPOF: if the daemon dies, sessions go dark until respawn;
  an orchestrator on Path B needs a `daemon status` healthcheck.
- Agent Teams is a third thing (experimental, off by default, not resumable) and is
  explicitly NOT on this path; see the companion note section 6.

## Bottom line

Can you manage the session lifecycle from the agent view? **Yes, via the `claude` CLI
+ `--json` underneath it, not via the TUI.** But agent view = Path B, and SPEC-032
currently builds Path A. Decide which one the prototype validates before writing
`/kit:dispatch`.

## Sources

- https://code.claude.com/docs/en/agent-view
- https://code.claude.com/docs/en/agents
- https://code.claude.com/docs/en/sub-agents
- https://code.claude.com/docs/en/agent-teams
- https://platform.claude.com/docs/en/managed-agents/multi-agent
