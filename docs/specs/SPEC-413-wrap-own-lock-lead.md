# SPEC-413: wrap apply --own treats the calling session's own Agent-tool lock as stale

Generated: 2026-10-27
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a self-pid exemption that also passes a different live session's lock, or a still-running subagent's worktree)
Type: spec-fix
References: `lib/wrap/wrap-apply.sh:68-91` (`_wt_locked`, `_wt_lock_pid`, `_wt_lock_live`), `:103-181` (`_wt_busy` and its `lsof` NOTE at `:125-130`), `:241-244` (the live-pid SKIP), `:255-262` (the `-f -f` override comment); `lib/wrap/wrap.sh:25-28` (the header's removal-refusal paragraph); `lib/wrap/wrap-land.sh:1028-1029` (land's lock-override comment); `tests/test-wrap-apply.sh:275-299` (the live-pid / dead-pid block), `:119-150` (the SPEC-302 `--own` block); `commands/wrap.md:153` (the `--own` contract), `:161` (the "A LOCK is not a skip reason there" sentence); SPEC-302 (`--own`), SPEC-376 Decision 6 (`docs/specs/SPEC-376-wrap-land-merged-pr.md:75`); commit ad34ad63 (#698, the live-pid guard).

## Problem

A lead session ran `wrap apply --apply --own <wt> <repo>` on a subagent worktree. The worktree was clean and its branch carried a merge proof. `apply` still refused it:

```
SKIP <wt>: locked by live pid <pid> (an agent is still running)
```

The pid was the lead Claude session itself, not a running agent. The Agent tool runs every subagent inside the lead's own process. It locks each worktree it creates with that process's pid. So the lock outlives the finished agent for the whole session, and `kill -0` on it always succeeds. The operator had to run `git worktree unlock` by hand before `apply` would tidy.

`commands/wrap.md:161` says a lock is not a skip reason once the merge proof holds. The live-pid guard from #698 overrides that sentence for every Agent-tool worktree while its lead lives. That means for the whole session that made it, which is exactly when `--own` runs.

A second defect sits in the same guard. `_wt_lock_live` decides liveness with `kill -0`. For a live pid owned by another uid, `kill -0` fails with EPERM, so the guard reads that pid as dead and overrides the lock (`## Grounding`, Sample 4).

SPEC-376 Decision 6 assumed two things this spec measures as false. First, that `_apply_worktrees` only ever sees locks naming someone else. Second, that a bash script cannot tell its own caller's lock from another live session's. The lock pid is the long-lived Claude process. Through the Bash tool, that process is the nearest `claude` ancestor of the `wrap.sh` process (`## Grounding`, Sample 2).

## Terms

none

## Solution

### Approaches considered

1. **Nearest `claude` ancestor, `--own` only, recognized Agent reason only, plus a quiescence guard.** Under `--own`, a live lock pid that equals the nearest ancestor of `wrap.sh` whose command name is `claude` counts as the caller's own. The lock must parse as an Agent-tool reason. The worktree's admin files must show no git activity in the last 5 minutes. Tradeoff: one `ps` snapshot and one `find` per self-locked candidate. A subagent that stays idle for 5 minutes with no git activity is still unprotected (`## Failure modes`).
2. **Match `$CLAUDE_PID` from the environment.** Tradeoff: the variable is inherited. A process that left the session's tree (a detached tmux, a reparented daemon) still carries it, and anyone can set it. The walk reads the live process table instead.
3. **Read the subagent's own transcript.** The lock names the agent id. The harness keeps `subagents/agent-<id>.jsonl` under the session's project dir (`## Grounding`, Sample 5), so its mtime would say whether that one agent is still active. Tradeoff: it couples a bash verb to a harness-internal path that moves with the profile home, which the Orca profile on this Mac already does. Rejected for this spec.
4. **Drop the live-pid guard under `--own` entirely.** Tradeoff: a second live session's worktree named by mistake loses its guard. Sample 2 shows that exact live case on this Mac.

### Chosen approach + why

Approach 1. It removes the false refusal for the incident's case. It keeps the guard for every pid that is not the caller's own Claude process, and it adds the one cheap signal that catches a freshly created worktree.

**The walk carries one bit, and that bit is per session.** Every agent the lead dispatches carries the same lock pid L. The walk can tell "a lock from my session" from "a lock from another session". Inside the caller's own session it carries no signal: a finished agent and a running agent look identical to it. Under `--own`, the protection inside the session is therefore the caller's naming plus these guards: the worktree is clean, the merge proof holds, the tip is unmoved, the admin files are quiet for 5 minutes, no non-ancestor process holds the worktree (`_wt_busy`), and the caller's own cwd is outside it. The contract at `commands/wrap.md:153` changes to match. `--own` names only worktrees this session created whose Agent call has returned.

The exemption stays inside `--own`. Under `--worktrees` (unscoped), the sweep reaches every worktree in the repo, and that includes this session's still-running background subagents. Their locks carry the same pid L, and a fresh branch is a trivial ancestor of origin. This is the hazard #698 closed. `--own` is the caller naming each worktree as finished, so it is the only scope where the caller vouches for it. **The incident therefore stays on the `--worktrees` path,** even in an unshared repo. A finished agent's self-locked worktree still prints the live-pid SKIP there. The operator's path is `--own`.

The exemption also stays with the recognized `claude agent ` reason. A `claude session <name> (pid N ...)` lock is the session's own `EnterWorktree` worktree. `commands/wrap.md:161` routes that through `ExitWorktree` so the harness records the removal. A self pid on a session lock gets a SKIP that names `ExitWorktree`. A reason that matches neither shape gets a separate "not recognized" SKIP.

The nearest `claude` ancestor beats "any ancestor". A headless `claude -p` worker that the lead spawned has the lead as a distant ancestor. Under "any ancestor", such a worker would pass the lead's other agent locks. Under "nearest", the worker's own process is the match, so the lead's locks stay foreign to it. It also keeps a lock naming a shell, a terminal host, or pid 1 from ever matching.

### Extensibility & boundaries

- Load-bearing dimension: the number of self-locked candidates per run. Each one costs one `ps -axo pid=,ppid=,comm=` snapshot (per call), a bash walk of at most 64 hops, and one `find` over three files. The cost grows linearly with candidates, not with the size of the process table or the worktree tree.
- Units, each testable alone:
  - `_pid_live <pid>`: is the pid alive, owner aside.
  - `_lock_parse <wt>`: read the lock file's first line once, then echo `<kind> <pid>` or nothing.
  - `_nearest_claude`: echo the pid of the nearest ancestor of `$$` whose command basename is `claude`, or nothing.
  - `_admin_quiet <wt>`: no change to `locked`, `HEAD` or `logs/HEAD` in the admin dir within 5 minutes.
- `_apply_worktrees` composes them at the existing lock step.

### Architecture

See `## Design`.

## Picture

```
  lead claude (pid L) ── Bash tool ── zsh ── bin/wrap (exec) ── wrap.sh ($$)
        │                                                          │
        │ Agent tool: worktree add + lock                          │ apply --own <wt>
        ▼                                                          ▼
  <wt> admin dir: locked = "claude agent agent-<id> (pid L start <UTC date>)"
                  HEAD, logs/HEAD (mtimes = creation / last commit)
                                                                   │
                         lock step in _apply_worktrees ◀───────────┘
                         (after the clean, proof and tip checks)
                                         │ self-locked
                                         ▼
                 _wt_busy (unchanged) ── remove -f -f ── branch -D
```

## Design

### Approaches considered + chosen

See `## Solution`. The design view adds two points:

- The lock step sits after the dirty, proof, re-dirty and tip-moved checks, so the exemption inherits all four. It sits before `_wt_busy`, which still refuses when a subagent's own shell holds the worktree. That shell is a sibling under the lead, never an ancestor of `wrap.sh`.
- The `--own given` test comes before the parse and the walk. So the `--worktrees` path runs exactly today's code, apart from the liveness fix.

### Diagram

Decision flow at the lock step, for one worktree that already passed the clean, proof and tip checks:

```
            locked? ──no──▶ unlocked ───────────────────────────────────┐
              │yes                                                       │
              ▼                                                          │
    _pid_live(lock pid)? ──no──▶ locked (dead or absent pid) ───────────┤
              │yes                                                       │
              ▼                                                          │
         --own given? ──no──▶ SKIP locked by live pid (today's text)     │
              │yes                                                       │
              ▼                                                          │
   _lock_parse: kind, pid ──none──▶ SKIP lock reason not recognized      │
              │                                                          │
              ▼                                                          │
   pid == _nearest_claude? ──no──▶ SKIP locked by live pid (today's text)│
              │yes                                                       │
              ▼                                                          │
       kind == agent? ──no (session)──▶ SKIP session lock, ExitWorktree  │
              │yes                                                       │
              ▼                                                          │
   caller cwd inside wt? ──yes──▶ SKIP this run's cwd is inside it       │
              │no                                                        │
              ▼                                                          │
     _admin_quiet(wt)? ──no──▶ SKIP git activity in the last 5 minutes   │
              │yes                                                       │
              ▼                                                          │
         self-locked ───────────────────────────────────────────────────┤
                                                                         ▼
                                                          _wt_busy ─▶ WOULD / remove
```

### ADR link(s)

No ADR. The decision is reversible and local to one verb. It corrects the premise of SPEC-376 Decision 6 for `apply` only. `land` keeps Decision 6 as is (`## Out of Scope`).

### Boundaries & failure modes

The change touches worktree removal, a data-loss surface. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes:
  - The first line of the worktree admin `locked` file, read once and parsed with one anchored regex: `^claude (agent|session) [^ ]+ \(pid ([0-9]+) start `.
  - The mtimes of `<admin>/locked`, `<admin>/HEAD` and `<admin>/logs/HEAD`. The index is excluded on purpose, because any `git status` rewrites it (Sample 6), wrap's own `:211` check included.
  - The live process table through `ps -axo pid=,ppid=,comm=` (one snapshot per call) and `ps -p <pid> -o pid=`.
  - `$$` and `pwd -P` of the `wrap.sh` shell, plus the existing `OWN_SET`.
- Outputs / produces, on stdout, inside the `-- worktrees:` section:
  - New verdict label `self-locked`: `WOULD remove worktree <wt> [<branch>, self-locked] and delete <branch> (<proof>)` on a dry run, the same verdict under `--apply`, then `delete <branch> (<proof>, its self-locked worktree is gone)`.
  - `SKIP <wt>: lock reason not recognized (pid <pid> is live)`.
  - `SKIP <wt>: locked by this session (pid <pid>, a session lock, not an Agent-tool one); leave it through ExitWorktree`.
  - `SKIP <wt>: this wrap run's own cwd is inside it`.
  - `SKIP <wt>: self-locked, but its git state changed in the last 5 minutes (a subagent may still be running)`.
  - `NOTE: self-lock check unavailable (ps failed); live locks stay refused`, printed once per run and mirroring the `lsof` NOTE.
  - Every other line is byte-identical to today, including `SKIP <wt>: locked by live pid <pid> (an agent is still running)`.
- Invariants:
  - A lock whose live pid is not the nearest `claude` ancestor of `wrap.sh` is refused, under every flag combination.
  - Liveness ignores the owner: a live pid of any uid is live.
  - Outside `--own`, the lock step runs today's code except for the liveness fix.
  - Every unknown fails closed. When `ps` fails, liveness falls back to `kill -0` (today's behavior) and the self-lock exemption is off. No `claude` ancestor within 64 hops means "not the caller". A failed `find` means "not quiet".

### Data model changes

None.

### API changes

None beyond the output lines above.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-A: Add the four helpers to `lib/wrap/wrap-apply.sh` next to the lock helpers, and rebase `_wt_lock_live` on `_pid_live`.
  - `_pid_live` returns 0 when `ps -p <pid> -o pid=` prints the pid. When `ps -p $$` itself fails, it falls back to `kill -0`, prints the ps NOTE once, and sets a flag that turns the exemption off.
  - `_lock_parse` reads the lock file once with `IFS= read -r` (keeping the line when git wrote no trailing newline, since `read` then exits 1) and applies the anchored regex with bash `[[ =~ ]]`. Bash 3.2 supports this (Sample 3).
  - `_nearest_claude` walks the `ps` snapshot from `$$` through parents. It stops at the first pid whose comm basename is `claude`, at pid 1, at an empty parent, or after 64 hops.
  - `_admin_quiet` runs `find <the three files> -prune -mmin -5` and passes when it prints nothing and exits 0.
  - Acceptance: `_pid_live 1` is 0 as a non-root user; `_nearest_claude` returns the fake `claude` pid from two hops up; `_admin_quiet` fails on a fresh worktree and passes after `touch -t` backdates the three files.
- [ ] TASK-B: Rework the lock step at `_apply_worktrees:241-244` to the decision flow in `## Design`. Acceptance:
  - Under `--own`, an Agent-shaped, quiet lock naming the nearest `claude` ancestor is removed with the `self-locked` label.
  - Every SKIP in the Interfaces list fires on its own case.
  - Under `--worktrees`, the existing block at `tests/test-wrap-apply.sh:275-299` stays green unchanged.

### Phase 2: Tests and docs

- [ ] TASK-C: Add a `=== apply --own: a lock naming the caller's own Claude process ===` block to `tests/test-wrap-apply.sh`.
  - Fixture: a fake `claude`, which is a symlink named `claude` to `bash` (Sample 3). The fake runs an intermediate `bash -c '...; true'` hop (the `; true` defeats bash's exec of a sole command), and that hop runs `"$WRAP"`. So the match sits two hops up, as in real use. The fixture writes each lock from inside the fake with its own `$$`, then runs wrap.
  - Self, Agent reason, backdated admin files: removed, `self-locked`, branch deleted; on a dry run, `WOULD ... self-locked`.
  - Fresh self worktree (no backdate): kept, git-activity SKIP.
  - Self, session reason: kept, ExitWorktree SKIP.
  - Unrecognized reason with a live pid: kept, not-recognized SKIP.
  - Caller cwd inside the worktree (the fake `cd`s in first): kept, cwd SKIP.
  - Sibling subtree: a second live fake `claude` started from the test shell names the lock. Kept, today's SKIP.
  - Same-pgid sibling: a fake `claude` child that the first fake backgrounds names the lock. Kept, today's SKIP.
  - Hop cap: the match sits 65 hops up (nested `bash -c '...; true'`). Kept, today's SKIP.
  - Pid 1 under `--own` (Agent reason) and under `--worktrees`: kept, today's SKIP. As a non-root user, today's code overrides it.
  - `ps` replaced by a failing stub on `PATH`: kept, the ps NOTE printed once.
  - Acceptance: the block passes, and every mutation in `## Grounding` turns at least one named check red.
- [ ] TASK-D: Fix the lock-rule statements so each one says the real rule. Acceptance: `rg -n "A LOCK is not a skip reason" commands/wrap.md` returns nothing, and every edited statement names the `--own` exemption or points to `commands/wrap.md:161`.
  - `commands/wrap.md:161`: a dead or absent lock pid is overridden. A live one, of any uid, is refused. The exception is `--own` with an Agent-tool lock naming the calling session's own Claude process and 5 quiet minutes, which prints `self-locked`.
  - `commands/wrap.md:153`: "naming only the worktrees this session created" becomes "naming only worktrees this session created whose Agent call has returned; a running subagent's worktree is never named".
  - `lib/wrap/wrap.sh:25-28`: add the live-lock refusal next to the busy refusal.
  - `lib/wrap/wrap-apply.sh:255-262`: rewrite the comment to the new flow.
  - `lib/wrap/wrap-land.sh:1028-1029`: one line saying `land` forces past every lock by SPEC-376 Decision 6, unlike `apply`.

## After state

- [ ] `wrap apply --apply --own <wt> <repo>` is run from the session whose Agent tool locked `<wt>`, after that agent returned and 5 quiet minutes. It removes a clean, proven-merged `<wt>` and deletes its branch with no hand `git worktree unlock`. (Today: `SKIP <wt>: locked by live pid <pid> (an agent is still running)`.)
- [ ] The same command on a worktree locked by a different live Claude process, or by pid 1, prints `SKIP <wt>: locked by live pid <pid> (an agent is still running)` and keeps the worktree and branch, checkable by `bash tests/test-wrap-apply.sh`. (Today, a pid 1 lock is overridden.)
- [ ] A self-locked worktree whose admin files changed in the last 5 minutes is kept under `--own`.
- [ ] `wrap apply --apply --worktrees <repo>` still refuses every live-pid lock, the caller's own included, and the block at `tests/test-wrap-apply.sh:275-299` stays green with no edit.
- [ ] `commands/wrap.md` no longer claims a lock is never a skip reason, and its `--own` contract says "whose Agent call has returned".

## Quality requirements

none (the repo keeps no `docs/QUALITY.md`; the invariants in `## Technical Design` carry the safety rule, tested by TASK-C)

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality
- [ ] Every mutation in `## Grounding` was run once by hand, turned its named check red, and was reverted

## Verification

```
bash tests/test-wrap-apply.sh && bash tests/run-all.sh --changed origin/master
```

Known to work on: macOS (Darwin 27, `/bin/bash` 3.2.57 and Homebrew bash 5.3.20, git 2.56), where the samples below were taken. Linux is not sampled. The helpers use only `ps -o pid=,ppid=,comm=`, `ps -p`, `find -mmin` and bash `[[ =~ ]]`, which GNU procps and findutils provide. `_wt_busy` already relies on the same `ps` flags there. Linux stays unproven until a run on a Linux host.

## Edge Cases

Journey walk, guarantee inversion, and category sweep:

1. Lock reason names no pid (a bare `git worktree lock`). It is not live and is overridden as today. The `--own` matrix fixtures at `tests/test-wrap-apply.sh:133` keep their `[wt-clean, locked]` label.
2. A live pid of another uid (pid 1, a root daemon). It is now live, so it is refused on every path (critical 1 of round 1).
3. Pid reuse inside the chain: the lock's writer died and its pid now belongs to the caller's nearest `claude`. The lock is treated as the caller's, which is harmless, because the writer is gone. Accepted gap; see `## Failure modes`.
4. Pid reuse outside the chain: an unrelated live process now holds the dead writer's pid. Today's SKIP stands (a false refusal, unchanged).
5. `ps` missing or failing. Liveness falls back to `kill -0`, the exemption is off, and the NOTE prints once.
6. `wrap` runs under `timeout`, `nohup`, or the Bash tool's `run_in_background`. The lead stays the nearest `claude` ancestor, so the exemption applies.
7. `wrap` runs from a different Claude session, from a headless `claude -p` worker the lead spawned, or from a process reparented to launchd. The lead is not the nearest `claude`, so the lock is refused.
8. One `--own` run names a self-locked worktree and a foreign-locked one. Each is decided alone.
9. A self lock on a dirty worktree, or on one without a merge proof. The earlier SKIPs fire first (`:211`, `:227`).
10. A subagent's own shell has its cwd inside the worktree. `_wt_busy` refuses, because that shell is a sibling, not an ancestor.
11. The caller's own cwd sits inside the target (the lead `cd`ed into the agent worktree). The cwd SKIP fires, so the session never loses its working directory.
12. A self `claude session` lock (the lead's own `EnterWorktree` worktree). The ExitWorktree SKIP fires, and the worktree is never removed.
13. A lock line with a different shape (a future harness, a hand lock with a reason). The not-recognized SKIP fires: a false refusal, never a removal.
14. Guarantee inversion of "the agent finished": a freshly created worktree for a subagent still running. Its `locked` file is seconds old, so the git-activity SKIP fires.
15. Guarantee inversion, longer: a subagent that has run with no commit, checkout or reset for over 5 minutes, named in `--own` by mistake. See `## Failure modes`, row 2.
16. The lead or `wrap` touched `logs/HEAD` later (Sample 6 shows one written 14 hours after its agent ended). The git-activity SKIP fires for 5 minutes, then clears: a delay, never a removal.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| The walk misreads a foreign pid as the caller | TASK-C sibling-subtree, same-pgid or hop-cap check goes red; in use, a worktree vanishes under another session | The walk matches only the nearest `claude` ancestor by `ps` parents, with no env or pgid matching. The mutation controls in `## Grounding` prove each check catches its mutant. |
| An idle subagent in the caller's own session, named in `--own` by mistake | The subagent's next tool call fails with "no such file or directory" | The walk carries no signal inside the session (`## Solution`). The guards are: the `--own` contract (only worktrees whose Agent call returned), a clean tree, a held proof, an unmoved tip, 5 quiet minutes in the admin files, and `_wt_busy` for a subagent mid-command. **Accepted gap:** a subagent that ran past 5 minutes with no commit, checkout or reset, and whose tree is clean, is removed. It has no committed work to lose, and anything it writes next fails loudly. This is the same residual gap SPEC-376 accepted for `land`. |
| Pid reuse inside the chain | None at run time | **Accepted gap.** A dead writer's pid reused by the caller's nearest `claude` makes the lock read as the caller's. The writer is gone, so treating its lock as stale is correct. The other guards still apply. |
| `ps` output differs across hosts | TASK-A acceptance on each host that runs the suite | Comm is compared by basename, so macOS's full path and Linux's short name both match. A parse failure answers "not the caller". |
| The Agent tool changes its lock reason shape | A self lock prints the not-recognized SKIP | A false refusal, never a removal. The shape is sampled live in `## Grounding`. |
| The 5-minute window blocks a legit tidy right after a fast merge | The git-activity SKIP | Re-run after the window. The SKIP names the reason. |

## Out of Scope

- `wrap land`. SPEC-376 Decision 6 dropped the lock check there entirely. TASK-D adds only a comment there.
- The same `kill -0` EPERM class elsewhere: `lib/spec/spec-next.sh:284` and `lib/queue/orchestrate.sh:163` use `kill -0` on pids they wrote themselves, so they are same-uid in practice. Flagged here, not changed.
- The misleading "an agent is still running" text on today's SKIP. The line stays byte-identical so existing callers and tests keep matching.
- Pid-reuse defense through the lock's `start <date>` field. The field is in UTC while `ps lstart` prints local time (Sample 1), so it needs its own parsing contract.
- Reading the harness's subagent transcripts (Approach 3).

## Touches

- lib/wrap/**
- tests/**
- commands/**

## Grounding

**Sample 1: the Agent tool's lock reason in `git worktree list --porcelain`.** Read-only, ops-toolkit main checkout on this Mac, 2026-10-27, agent ids masked:

```
$ git worktree list --porcelain | rg "^locked" | sed -E 's/agent-[0-9a-f]+/agent-<id>/g' | sort | uniq -c
   2 locked claude agent agent-<id> (pid 78615 start Sun Oct 25 14:56:35 2026)
   1 locked claude session fovea-days (pid 78615 start Sun Oct 25 14:56:35 2026)
$ ps -o pid=,ppid=,lstart=,comm= -p 78615
78615 78481 Sun Oct 25 21:56:35 2026     claude
```

Two reason shapes exist: `claude agent agent-<id> (pid N start <date>)` from the Agent tool and `claude session <name> (pid N start <date>)` from `EnterWorktree`. Both name the same long-lived process, whose comm is `claude`. The lock's `start` field is UTC, and `ps lstart` is local time (UTC+7).

**Sample 2: the lock pid relative to the calling process tree.** Read-only, from this worker's Bash tool shell. Nothing was signalled except by `kill -0`:

```
$ p=$$; while [ "$p" -gt 1 ]; do ps -o pid=,ppid=,pgid=,comm= -p "$p"; p=$(ps -o ppid= -p "$p" | tr -d ' '); done
37944 75803 37944 /opt/homebrew/bin/zsh
75803 84866 75803 claude
84866 84865 84866 -/opt/homebrew/bin/fish
84865  2810 84865 /usr/bin/login
 2810     1  2810 .../Orca Terminal Host
$ echo "CLAUDE_PID=$CLAUDE_PID PPID=$PPID"
CLAUDE_PID=75803 PPID=75803
$ is_anc 75803; is_anc 78615
pid 75803: ancestor of this shell (kill -0 rc=0)
pid 78615: NOT an ancestor (kill -0 rc=0)
```

This worker is a subagent, and its shell's direct parent is the lead's `claude` (75803). Subagents run inside the lead's process, so any worktree the Agent tool makes for one is locked with the lead's pid. When the lead runs `bin/wrap apply`, the chain is `claude(L) -> zsh -> bash wrap.sh` (`bin/wrap:24` `exec`s `wrap.sh`). So L is the nearest `claude` ancestor, two hops up, and a `$PPID`-only check would miss it. Both 75803 and 78615 are live Claude sessions; `kill -0` cannot tell them apart.

**Sample 3: fixture mechanics.** A symlink named `claude` to `/bin/bash` shows comm `.../claude` on macOS, basename `claude`. A *copy* of `/bin/bash` is SIGKILLed on launch (rc 137, platform-binary signing), so the fixture uses a symlink. `bash -c '<one command>'` execs that command in place and drops the hop, so the fixture appends `; true`. The anchored regex parses the live line on `/bin/bash` 3.2:

```
$ /bin/bash -c '... [[ $l =~ $re ]] && echo "kind=${BASH_REMATCH[1]} pid=${BASH_REMATCH[2]}"'
kind=agent pid=78615
fixture-283 shape: not recognized      # "claude agent test (pid N started now)"
```

The `:283` fixture's reason does not match, and that is fine: it runs only under `--worktrees`, which never parses.

**Sample 4: `kill -0` reads a live other-uid pid as dead.**

```
$ /bin/bash -c 'kill -0 1 2>/dev/null; echo "kill -0 1 rc=$?"'
kill -0 1 rc=1
$ /bin/bash -c 'ps -p 1 >/dev/null; echo "ps -p 1 rc=$?"'
ps -p 1 rc=0
$ ps -p 1 -o pid=,user=,comm=
    1 root /sbin/launchd
```

Today, a lock naming pid 1, or any live root process, passes `_wt_lock_live` as dead and is overridden with `-f -f`.

**Sample 5: the subagent transcript exists, which informs the rejected Approach 3.** A `fd` for one sampled agent id found `~/.claude/projects/<proj>/<session>/subagents/agent-<id>.jsonl` and `.meta.json`. Its mtime (00:47:25 local) was 12 s after the worktree's last commit (index 00:47:13).

**Sample 6: which admin files mean git activity.** For the sampled agent worktree, the admin dir showed `locked` and `HEAD` at creation (00:22:12), `index` and `COMMIT_EDITMSG` at the last commit (00:47:13), and `logs/HEAD` at 15:15:47 the next day, written by a later operation. Then a scratch repo was made in `$TMPDIR`: one worktree, one file touched, then `git -C <wt> status --short` (clean):

```
2026-10-27T12:33:18 index        <- rewritten by `git status` itself
2026-10-27T12:33:16 HEAD
2026-10-27T12:33:16 logs/HEAD
```

So `index` is not a quiet signal: wrap's own dirty check at `:211`, or an operator's dry run, would reset it. `locked`, `HEAD` and `logs/HEAD` change only on creation, commit, checkout or reset. The guard reads those three.

**Negative controls, dry traces.** Each fixture runs inside TASK-C's block. Each mutation is applied by hand once and reverted.

| # | Fixture | Code path on the real code | Mutation | Check that goes red |
|---|---|---|---|---|
| 1 | Sibling subtree: a second live fake `claude` (started from the test shell) names the lock; `--own` | parse ok -> `_nearest_claude` returns the first fake -> pid differs -> today's SKIP | `_nearest_claude` matches any live `claude` in the table | "own sibling claude: worktree kept" |
| 2 | Same pgid: a fake `claude` child the first fake backgrounds names the lock | walk goes up from `$$` only, so the child is never visited -> today's SKIP | match by process group instead of parent walk | "own same-pgid claude: worktree kept" |
| 3 | Match two hops up (fake -> `bash -c '...; true'` -> wrap), quiet, Agent reason | walk reaches the fake at hop 2 -> `self-locked` -> removed | walk checks `$PPID` only | "own self lock: worktree removed" (it stays) |
| 4 | Hop cap: the match 65 hops up | the walk stops at 64 -> nothing found -> today's SKIP | drop the 64-hop cap | "own beyond hop cap: worktree kept" |
| 5 | Fresh self worktree, no backdate | `_admin_quiet` sees `locked` under 5 min -> git-activity SKIP | `_admin_quiet` returns 0 | "own fresh self lock: worktree kept" |
| 6 | Pid 1 lock, `--worktrees` and `--own`, as a non-root user | `_pid_live 1` -> `ps -p 1` rc 0 -> live -> today's SKIP | `_pid_live` reverts to `kill -0` | "pid 1 lock: worktree kept" (both) |
| 7 | Existing `mtx-livepid` (`:280-283`, lock pid `$$`), `--worktrees` | `--own given` fails first -> today's SKIP | drop the `--own given` check | `:289` and `:297` checks |
| 8 | Self lock with the caller's cwd inside | cwd SKIP | drop the cwd check | "own cwd inside: worktree kept" |
| 9 | `ps` stub that exits 1, live self lock | `_pid_live` falls back to `kill -0`, exemption off, NOTE once -> today's SKIP | treat ps failure as "caller" | "ps failure: worktree kept", "ps failure: NOTE printed" |

Mutation 6 goes red only as a non-root user, because root's `kill -0 1` succeeds. The operator's host and CI runners are non-root.

**Not sampled:** Linux `ps -o comm=` output and Linux `find -mmin` on the three admin files. This Mac cannot reach them. See `## Verification`.

## Decision Log

- DEC-1: Identify the caller as the nearest ancestor of `wrap.sh` whose comm basename is `claude`. Rationale: the Agent tool's lock pid is that process (Sample 2). "Nearest" keeps a spawned headless worker, a shell, or pid 1 from matching. Rejected: any ancestor (round 1 warning), `$PPID` only (misses the two-hop real chain), `$CLAUDE_PID` (inheritable).
- DEC-2: Apply the exemption only under `--own`, checked before the parse and the walk. Rationale: unscoped `--worktrees` reaches this session's running background subagents, whose locks carry the same pid. Rejected: all scopes. Consequence: the incident stays on `--worktrees`.
- DEC-3: Apply it only to a recognized `claude agent ` reason. Session locks and unrecognized shapes get separate SKIPs. Rationale: the session's own worktree routes through `ExitWorktree`, and a shape the parse does not know cannot vouch for anything.
- DEC-4: Decide liveness by `ps -p`, falling back to `kill -0` only when `ps` itself fails. Rationale: EPERM made `kill -0` read live other-uid pids as dead (Sample 4, round 1 critical 1).
- DEC-5: Add the 5-minute admin-file quiescence guard and accept the longer idle gap. Rationale: the walk carries no signal inside the session (round 1 critical 2). The guard catches the fresh-worktree case #698 named, at the cost of one `find` over three files. A full tree mtime walk is rejected, because the busy-check comment measured `+D` walks at 3.6 s on a 160k-file tree. `index` is rejected, because `git status` rewrites it (Sample 6).
- DEC-6: Refuse when the caller's cwd is inside the target. Rationale: removing the lead's working directory breaks the session itself, and `_wt_busy` exempts ancestors by design.
- DEC-7: Fail closed everywhere. Rationale: a false refusal costs one re-run or one hand unlock, while a false removal can lose a live agent's writes.
- DEC-8: Leave `wrap land`'s behavior unchanged and add a comment only. Rationale: SPEC-376 Decision 6 owns that path's lock rule.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
