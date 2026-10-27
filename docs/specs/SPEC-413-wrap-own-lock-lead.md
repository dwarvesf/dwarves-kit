# SPEC-413: wrap apply --own treats the calling session's own Agent-tool lock as stale

Generated: 2026-10-27
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a self-pid exemption that also passes a different live session's lock, or a still-running subagent's worktree outside the named set)
Type: spec-fix
References: `lib/wrap/wrap-apply.sh:68-91` (`_wt_locked`, `_wt_lock_pid`, `_wt_lock_live`), `:103-181` (`_wt_busy`, whose awk already walks this run's ancestors and excludes them), `:241-244` (the live-pid SKIP), `:255-262` (the `-f -f` override comment); `tests/test-wrap-apply.sh:275-299` (the live-pid / dead-pid block), `:119-150` (the SPEC-302 `--own` block); `commands/wrap.md:161` (the "A LOCK is not a skip reason there" sentence); SPEC-302 (`--own`), SPEC-376 Decision 6 (`docs/specs/SPEC-376-wrap-land-merged-pr.md:75`); commit ad34ad63 (#698, the live-pid guard).

## Problem

A lead session ran `wrap apply --apply --own <wt> <repo>` on a subagent worktree. The worktree was clean and its branch carried a merge proof. `apply` still refused it:

```
SKIP <wt>: locked by live pid <pid> (an agent is still running)
```

The pid was the lead Claude session itself, not a running agent. The Agent tool runs every subagent inside the lead's own process. It locks each worktree it creates with that process's pid. So the lock outlives the finished agent for the whole session, and `kill -0` on it always succeeds. The operator had to run `git worktree unlock` by hand before `apply` would tidy.

`commands/wrap.md:161` says a lock is not a skip reason once the merge proof holds. The live-pid guard from #698 overrides that sentence for every Agent-tool worktree while its lead lives. That means for the whole session that made it, which is exactly when `--own` runs.

SPEC-376 Decision 6 assumed two things this spec measures as false. First, that `_apply_worktrees` only ever sees locks naming someone else. Second, that a bash script cannot tell its own caller's lock from another live agent's. The lock pid is the long-lived Claude process. Through the Bash tool, that process is an ancestor of the `wrap.sh` process (see `## Grounding`). An ancestor walk tells the two apart.

## Terms

none

## Solution

### Approaches considered

1. **Ancestor walk, `--own` only, Agent-shaped reason only.** Under `--own`, a live lock pid that is `wrap.sh`'s own pid or one of its ancestors, on a lock whose reason starts `claude agent `, counts as stale. Tradeoff: one `ps` walk per locked candidate, and a still-idle subagent the lead itself names in `--own` can be removed (named in `## Failure modes`).
2. **Match `$CLAUDE_PID` from the environment.** Treat the lock as stale when its pid equals `$CLAUDE_PID`. Tradeoff: the variable is inherited, so a process that left the session's tree (a detached tmux, a reparented daemon) still carries it. It also lets anyone set it. The ancestor walk reads the live process table instead.
3. **Drop the live-pid guard under `--own` entirely.** Tradeoff: a second live session's worktree named by mistake in `--own` loses its guard. The negative control in `## Grounding` is a real live case of exactly that on this Mac.

### Chosen approach + why

Approach 1. It removes the false refusal for the case that produced the incident and keeps the guard for every pid outside the caller's own chain. Approach 2 trades the live process table for an inheritable string. Approach 3 trades away the only guard against a second live session.

The exemption stays inside `--own`. Under `--worktrees` (unscoped), the sweep reaches every worktree in the repo, and that includes worktrees of this session's still-running background subagents. Their locks carry the same lead pid, and a fresh branch is a trivial ancestor of origin. This is the hazard #698 closed, and the memory note on `wrap apply --worktrees` pruning fresh worker worktrees records it. `--own` is the caller naming each worktree as finished, so it is the only scope where the caller vouches for it.

The exemption also stays with Agent-shaped reasons. A `claude session <name> (pid N ...)` lock is the session's own `EnterWorktree` worktree. `commands/wrap.md:161` routes that through `ExitWorktree` so the harness records the removal, and the session's cwd may sit inside it. A self pid on a session-shaped lock gets its own SKIP that names `ExitWorktree`.

### Extensibility & boundaries

- Load-bearing dimension: the number of locked candidates per run. Each one costs one bounded ancestor walk (a `ps` snapshot taken once per run, walked in bash, at most 64 hops). The cost grows linearly with candidates, not with the process table.
- Units: `_pid_is_caller <pid>` answers one question: is this pid `$$` or an ancestor of `$$`. `_wt_lock_reason <wt>` echoes the lock file's first line. `_apply_worktrees` composes them at the existing lock step. Each one is testable alone.

### Architecture

See `## Design`.

## Picture

```
  lead claude (pid L) ── Bash tool ── zsh ── bin/wrap (exec) ── wrap.sh ($$)
        │                                                          │
        │ Agent tool: worktree add + lock                          │ apply --own <wt>
        ▼                                                          ▼
  <wt>/.git admin: locked = "claude agent agent-<id> (pid L start <UTC date>)"
                                                                   │
                     lock step in _apply_worktrees  ◀──────────────┘
                     ┌───────────────────────────────────────────────┐
                     │ pid dead / absent ............ override (today) │
                     │ pid live, NOT in $$'s chain .. SKIP (today)     │
                     │ pid live, in chain, --own,                      │
                     │   reason "claude agent " ..... self-locked: go  │
                     │   reason other ............... SKIP ExitWorktree│
                     │ pid live, in chain, no --own . SKIP (today)     │
                     └───────────────────────────────────────────────┘
                                         │ go
                                         ▼
                     _wt_busy (unchanged) ── remove -f -f ── branch -D
```

## Design

### Approaches considered + chosen

See `## Solution`. The design view adds one point. The lock step sits after the dirty, proof, re-dirty, and tip-moved checks, so the exemption inherits all four. It also sits before `_wt_busy`, which still refuses when a subagent's own shell (a sibling under the lead, never an ancestor of `wrap.sh`) holds the worktree.

### Diagram

Decision flow at the lock step, for one worktree that already passed the clean, proof and tip checks:

```
            locked? ──no──▶ unlocked ─────────────────────────────┐
              │yes                                                 │
              ▼                                                    │
     lock pid live? ──no──▶ locked (stale, dead or absent pid) ───┤
              │yes                                                 │
              ▼                                                    │
   pid is $$ or ancestor? ──no──▶ SKIP locked by live pid (today)  │
              │yes                                                 │
              ▼                                                    │
       wt in OWN_SET? ──no──▶ SKIP locked by live pid (today)      │
              │yes                                                 │
              ▼                                                    │
 reason starts "claude agent "? ──no──▶ SKIP own session lock       │
              │yes                     (leave it through            │
              ▼                         ExitWorktree)               │
         self-locked ──────────────────────────────────────────────┤
                                                                   ▼
                                                    _wt_busy ─▶ WOULD / remove
```

### ADR link(s)

No ADR. The decision is reversible and local to one verb. It corrects the premise of SPEC-376 Decision 6 for `apply` only. `land` keeps Decision 6 as is (`## Out of Scope`).

### Boundaries & failure modes

The change touches worktree removal, a data-loss surface. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes: the worktree admin `locked` file (first line, git's free-text reason); the live process table through `ps -axo pid=,ppid=`; `$$` of the `wrap.sh` shell; the existing `OWN_SET`.
- Outputs / produces, on stdout, inside the `-- worktrees:` section:
  - New verdict label `self-locked`: `WOULD remove worktree <wt> [<branch>, self-locked] and delete <branch> (<proof>)` (dry run), and the same verdict under `--apply`, then `delete <branch> (<proof>, its self-locked worktree is gone)`.
  - New SKIP: `SKIP <wt>: locked by this session's own pid <pid> (a session lock, not an Agent-tool one; leave it through ExitWorktree)`.
  - Every other line is byte-identical to today, including `SKIP <wt>: locked by live pid <pid> (an agent is still running)`.
- Invariants:
  - A lock whose live pid is outside `$$`'s ancestor chain is refused, under every flag combination.
  - Outside `--own`, the lock step behaves exactly as today.
  - `_pid_is_caller` fails closed: no `ps`, an unreadable table, or a walk past 64 hops answers "not the caller".

### Data model changes

None.

### API changes

None beyond the two output lines above.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-A: Add `_pid_is_caller <pid>` and `_wt_lock_reason <wt>` to `lib/wrap/wrap-apply.sh` next to the lock helpers. `_pid_is_caller` takes one `ps -axo pid=,ppid=` snapshot, walks from `$$` through parents, and stops at pid 1, an empty parent, or 64 hops. Acceptance: it answers 0 for `$$` and for its parent, 1 for a sibling `sleep` pid, and 1 when `ps` is shadowed by a failing stub on `PATH`.
- [ ] TASK-B: Rework the lock step at `_apply_worktrees:241-244` to the decision flow in `## Design`, and update the `:255-262` comment to match. Acceptance: under `--own`, an Agent-shaped lock naming `$$`'s chain is removed with the `self-locked` label. An Agent-shaped lock naming a live non-ancestor pid prints today's SKIP. A session-shaped self lock prints the new ExitWorktree SKIP. Under `--worktrees`, the existing live-pid block at `tests/test-wrap-apply.sh:275-299` stays green unchanged.

### Phase 2: Tests and docs

- [ ] TASK-C: Add a `=== apply --own: a lock naming the caller's own pid ===` block to `tests/test-wrap-apply.sh`. It covers a self Agent lock (dry run plus apply, removed, branch deleted), a foreign live pid (a background `sleep` the test spawns, kept, SKIP line, branch kept), a self session lock (kept, new SKIP), and a `ps` stub that fails (self Agent lock kept, today's SKIP). Acceptance: the block passes, and each mutation in `## Grounding` turns at least one named check red.
- [ ] TASK-D: Fix `commands/wrap.md:161`. The sentence "A LOCK is not a skip reason there" becomes a statement of the real rule: a dead or absent lock pid is overridden; a live one is refused unless `--own` names the worktree, the pid is the calling session's own, and the lock is an Agent-tool lock. Acceptance: `rg -n "A LOCK is not a skip reason" commands/wrap.md` returns nothing, and the new sentence names `--own`, `self-locked` and `ExitWorktree`.

## After state

- [ ] `wrap apply --apply --own <wt> <repo>`, run from the session whose Agent tool locked `<wt>`, removes a clean, proven-merged `<wt>` and deletes its branch with no hand `git worktree unlock`. (Today: `SKIP <wt>: locked by live pid <pid> (an agent is still running)`.)
- [ ] The same command on a worktree locked by a different live process prints `SKIP <wt>: locked by live pid <pid> (an agent is still running)` and keeps both worktree and branch, checkable by `bash tests/test-wrap-apply.sh`.
- [ ] `wrap apply --apply --worktrees <repo>` still refuses every live-pid lock, the caller's own included. The existing block at `tests/test-wrap-apply.sh:275-299` stays green with no edit.
- [ ] `commands/wrap.md` no longer claims a lock is never a skip reason.

## Quality requirements

none (the repo keeps no `docs/QUALITY.md`; the invariants in `## Technical Design` carry the safety rule, tested by TASK-C)

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path + edge cases listed below
- [ ] No regressions in existing functionality
- [ ] Both mutations in `## Grounding` were run once by hand and each turned its named check red, then were reverted

## Verification

```
bash tests/test-wrap-apply.sh && bash tests/run-all.sh --changed origin/master
```

## Edge Cases

Journey walk, guarantee inversion, and category sweep:

1. Lock reason names no pid (a bare `git worktree lock`). `_wt_lock_pid` is empty, the lock is not live, and the worktree is overridden as today. The `--own` matrix fixtures at `tests/test-wrap-apply.sh:133` keep their `[wt-clean, locked]` label.
2. Pid reuse: the lock's writer died and its pid now belongs to one of this run's ancestors. The walk calls it the caller, so the lock is treated as stale. That is correct, because the writer is gone.
3. Pid reuse the other way: the writer died and an unrelated live process now holds its pid. Today's SKIP stands (a false refusal, unchanged, out of scope).
4. `ps` missing or failing. `_pid_is_caller` answers no, and today's SKIP stands (fail closed; TASK-C stub case).
5. `wrap` runs under `timeout`, `nohup`, or the Bash tool's `run_in_background`. Each stays a descendant of the lead, so the exemption applies.
6. `wrap` runs from a different Claude session, or from a process that reparented to launchd (`setsid`, a daemon). The lead is not an ancestor, so the lock is refused.
7. One `--own` run names a self-locked worktree and a foreign-locked one. Each is decided alone: one is removed and one is skipped.
8. A self Agent lock on a dirty worktree. The dirty SKIP fires first (`:211`), so the lock step never runs.
9. A self Agent lock on a worktree with no merge proof. The proof SKIP fires first (`:227`).
10. A self Agent lock while a subagent's own shell has its cwd inside. `_wt_busy` refuses, because that shell is a sibling, not an ancestor.
11. A self `claude session` lock (the lead's own `EnterWorktree` worktree) named in `--own`. It gets the new ExitWorktree SKIP and is never removed.
12. A lock file with several `pid N` tokens. `_wt_lock_pid` keeps reading the first one, unchanged.
13. Guarantee inversion of "the merge proof holds": a fresh worktree whose branch is a trivial ancestor of origin, still in use by an idle background subagent, named in `--own` by mistake. See `## Failure modes`, row 2.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| The ancestor walk misreads a foreign pid as the caller | TASK-C foreign-pid check goes red; in use, a worktree vanishes under another session | The walk reads `ps` parents only, with no name or env matching. The mutation control in `## Grounding` proves the check catches it. |
| The lead names an idle, still-running background subagent's worktree in `--own` | The subagent's next tool call fails with "no such file or directory" | Only when the tree is clean, the tip is unmoved, and the proof holds, so no committed work is lost. This is the same residual gap SPEC-376 accepted for `land`. A subagent mid-command is caught by `_wt_busy`. |
| `ps` output format differs across macOS and Linux | TASK-A acceptance on both CI legs | `ps -axo pid=,ppid=` is already used by `_wt_busy` (`:132`) on both. A parse failure answers "not the caller" (fail closed). |
| The Agent tool changes its lock reason shape | A self lock prints the session SKIP or today's SKIP again | The failure is a false refusal, never a removal. The reason prefix is sampled live in `## Grounding`. |

## Out of Scope

- `wrap land`. SPEC-376 Decision 6 dropped the lock check there entirely. Bringing `land` in line with this rule is a separate decision.
- The misleading "an agent is still running" text on today's SKIP for non-Agent locks outside `--own`. The line stays byte-identical so existing callers and tests keep matching.
- Pid-reuse defense through the lock's `start <date>` field. The field is in UTC while `ps lstart` prints local time (see `## Grounding`), so it needs its own parsing contract.

## Touches

- lib/wrap/**
- tests/**
- commands/**

## Grounding

**Sample 1: the Agent tool's lock reason in `git worktree list --porcelain`** (read-only, ops-toolkit main checkout on this Mac, 2026-10-27, agent ids masked):

```
$ git worktree list --porcelain | rg "^locked" | sed -E 's/agent-[0-9a-f]+/agent-<id>/g' | sort | uniq -c
   2 locked claude agent agent-<id> (pid 78615 start Sun Oct 25 14:56:35 2026)
   1 locked claude session fovea-days (pid 78615 start Sun Oct 25 14:56:35 2026)
```

Two reason shapes exist: `claude agent agent-<id> (pid N start <date>)` from the Agent tool and `claude session <name> (pid N start <date>)` from `EnterWorktree`. Both name the same long-lived Claude process. `_wt_lock_pid`'s `pid [0-9]+` grep reads both.

```
$ ps -o pid=,ppid=,lstart=,comm= -p 78615
78615 78481 Sun Oct 25 21:56:35 2026     claude
```

The lock's `start` field is UTC. `ps lstart` is local time (UTC+7 here). The two differ by 7 hours for the same process.

**Sample 2: the lock pid relative to the calling process tree** (read-only, from this worker's Bash tool shell; nothing killed or signalled except `kill -0`):

```
$ p=$$; while [ "$p" -gt 1 ]; do ps -o pid=,ppid=,pgid=,comm= -p "$p"; p=$(ps -o ppid= -p "$p" | tr -d ' '); done
37944 75803 37944 /opt/homebrew/bin/zsh
75803 84866 75803 claude
84866 84865 84866 -/opt/homebrew/bin/fish
84865  2810 84865 /usr/bin/login
 2810     1  2810 .../Orca Terminal Host
$ echo "CLAUDE_PID=$CLAUDE_PID PPID=$PPID"
CLAUDE_PID=75803 PPID=75803
```

This worker is a subagent, and its Bash shell's direct parent is the lead's `claude` process (75803). So subagents run inside the lead's process, and any worktree the Agent tool makes for one is locked with the lead's pid. When the lead later runs `bin/wrap apply`, the chain is `claude(L) -> zsh -> bash wrap.sh` (`bin/wrap` `exec`s `wrap.sh`, `bin/wrap:24`). So L is an ancestor of `wrap.sh`'s `$$`:

```
$ is_anc 75803; is_anc 78615     # ps-parent walk from $$
pid 75803: ancestor of this shell (kill -0 rc=0)
pid 78615: NOT an ancestor (kill -0 rc=0)
```

Both pids are live Claude sessions on this Mac right now. `kill -0`, today's only test, cannot tell them apart. The ancestor walk can.

**Sample 3: the existing test fixture already locks with an ancestor pid.** `tests/test-wrap-apply.sh:283` writes `claude agent test (pid $$ started now)`, where `$$` is the test shell. That shell is an ancestor of the `wrap.sh` it spawns (`out="$("$WRAP" ...)"`, `bin/wrap` execs). So that block is already the self-pid case under `--worktrees`, and its "kept" checks (`:289-290`, `:297-299`) become the scoping control for free.

**Negative control 1, dry trace: an unrelated live pid under `--own` is still refused.**
- Fixture (TASK-C): `git -C "$MTX" worktree add "$TMPD/own-foreign" <branch at origin/merged-ancestor>`, then `( exec sleep 120 ) & FOREIGN_PID=$!`, then `git worktree lock --reason "claude agent agent-t (pid $FOREIGN_PID start now)"`.
- Run: `"$WRAP" apply --apply --own "$TMPD/own-foreign" "$MTX"`.
- Code path: `OWN_SET` matches, the tree is clean, the branch is not protected, `_merge_proof` says `ancestor of origin/main`, and the tip is unmoved. `_wt_locked` is 0 and `_wt_lock_live` is 0 (the `sleep` is alive). `_pid_is_caller $FOREIGN_PID` walks `wrap.sh -> test shell -> ...`. The `sleep` is the test shell's child, a sibling of `wrap.sh`, so it is not in the chain, and the walk returns 1. The run prints `SKIP .../own-foreign: locked by live pid $FOREIGN_PID (an agent is still running)` and continues.
- Mutation: make `_pid_is_caller` return 0 unconditionally (or drop its call from the lock step).
- Red: `chk "own foreign live pid: worktree kept"` and `chk_has "own foreign live pid: SKIP names the pid"` fail, because the worktree is removed with the `self-locked` label.

**Negative control 2, dry trace: the exemption stays inside `--own`.**
- Fixture: the existing `mtx-livepid` worktree (`tests/test-wrap-apply.sh:280-283`), lock pid `$$`, an ancestor, with an Agent-shaped reason.
- Run: `"$WRAP" apply --apply --worktrees "$MTX"` (`:294`).
- Code path: `OWN_SET` is empty. The walk says caller, but the `--own` condition fails, so the run prints today's SKIP.
- Mutation: drop the `OWN_SET` membership condition from the exemption.
- Red: `chk "livepid apply kept the live-pid worktree"` (`:297`) and `chk_has "livepid dry-run: the live-pid worktree is skipped, not removed"` (`:289`) fail.

**Not sampled:** the Linux leg's `ps -axo pid=,ppid=` output. It is not reachable from this Mac. `_wt_busy` already relies on the same flags there (`lib/wrap/wrap-apply.sh:132`), and CI's Ubuntu leg checks TASK-A.

## Decision Log

- DEC-1: Identify "the calling session" by a `ps` parent walk from `wrap.sh`'s `$$`. Rationale: the Agent tool's lock pid is the lead `claude` process, which is the Bash tool's ancestor (Sample 2). Rejected: `$CLAUDE_PID` equality, because it is inheritable and settable.
- DEC-2: Apply the exemption only under `--own`. Rationale: unscoped `--worktrees` reaches this session's still-running background subagents, whose locks carry the same pid (the #698 hazard). Rejected: all scopes.
- DEC-3: Apply the exemption only to `claude agent ` reasons. A self `claude session` lock gets an ExitWorktree SKIP. Rationale: `commands/wrap.md:161` routes the session's own worktree through `ExitWorktree`, and the session's cwd may sit inside it. Rejected: any reason shape.
- DEC-4: Fail closed. Rationale: a false refusal costs one hand unlock, while a false removal can lose a live agent's writes.
- DEC-5: Leave `wrap land` unchanged. Rationale: SPEC-376 Decision 6 owns that path's lock rule, and changing it is a separate decision. This spec corrects only Decision 6's premise as it applies to `apply`.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
