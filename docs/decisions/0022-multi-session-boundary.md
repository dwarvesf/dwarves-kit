# ADR-0022: Multi-session boundary (one operator, N same-machine sessions, via a running-goal registry)

## Status: accepted (2026-05-23). Implements SPEC-036 conflict C4. Supersedes the multi-session "stays L5" boundary for the one-operator / N-same-machine-sessions / disjoint-goals case.

## Context

ADR-0019 settled the **in-session** concurrency boundary: one LEAD session may fan out N
isolated worktree workers over disjoint specs (`/kit:dispatch`, SPEC-032). It left the
**cross-session** boundary standing. Two PHILOSOPHY lines still forbid the maintainer's
other real workflow, open several Claude sessions (one terminal/tab per goal), set a
`/goal` in each, and walk away (conflict **C4**, SPEC-036, `_meta/BACKLOG.md` ID-040):

1. `docs/PHILOSOPHY.md` target-user note (~line 121): **"someone who needs multi-session
   orchestration across machines or 3+ live operators (that's L5, use
   Nimbalyst/Conductor)."**
2. `docs/PHILOSOPHY.md` "What the kit does NOT cover" (~line 151): **"multi-session
   coordination across machines or live operators stays L5."**

These were written for the *team* case (3+ contractors on their own machines). They also,
as written, sweep up the *single-operator multi-window* case, one person running several
sessions on one machine over disjoint goals, which is lightweight and needs no runtime.
The in-session moat (`lib/dispatch-gate.sh`) does not reach across sessions because it
lives in one lead's context, not on disk. PHILOSOPHY line 11 is explicit: a principle that
cannot bend when the tradeoff shifts is not a real principle. The tradeoff shifted (the
multi-window workflow is now real); the boundary must be bent **deliberately, by ADR**, for
exactly the case that shifted, and no wider.

This is NOT a re-litigation of ADR-0019 (in-session fan-out) nor of build-left/test-right.
It is the one remaining boundary the C1 ADR did not reach: cross-session coordination.

## Decision

**One operator running N concurrent sessions on one machine over disjoint goals is
in-scope, coordinated by a passive running-goal registry. A daemon / lock server /
scheduler is not.**

The permitted model:

- **Each session that starts a goal registers a claim** in a per-goal file under
  `$(git rev-parse --git-common-dir)/kit-goals/` (the git common dir, shared by every
  worktree of one repo on one machine, inherently untracked). One file per goal,
  **single-writer**: a session writes only its own goal's record. No file has two
  writers, so there is no shared-state parallelism.
- **A cross-session disjointness gate is the moat**: before a goal starts, its declared
  globs are checked against every active registered goal, **reusing `lib/dispatch-gate.sh`**
  (not a second implementation). Any pair the gate cannot PROVE disjoint is refused, the
  colliding goal named; the operator serializes or repicks. Conservative by construction,
  the same prove-or-serialize rule as SPEC-032 (DEC-008).
- **The registry is the cross-session monitor**: `goal-registry list` shows every running
  goal + lane + status from any session. It complements the native agent view, which can
  only show the subagents inside one session, not goals across sessions.
- **Each goal leaves a running attempt log** (`<slug>.attempts`), so a human glancing at
  the registry sees not just who is running but what each has tried.
- **Coordination is advisory at claim time, not a kernel lock**: a real lock needs a
  daemon (a runtime, the L5 handoff). The advisory gate + a last-writer-loud re-read +
  human-gated merge is the same safety posture as the in-session gate; a missed
  same-instant overlap costs a manual merge, not corruption.

### Naming (disambiguation, load-bearing)

This **running-goal registry** is distinct from ADR-0011's **goal-draft store**
(`.claude/goals/`, the candidate-draft files beside the built-in `/goal`). ADR-0011 stores
*drafts a human might activate*; ADR-0022 records *goals currently running across
sessions*. They are different artifacts with different lifecycles; do not conflate them.

### The two boundary rewords

| # | Old (forbids) | New (permits the bounded model) |
|---|---|---|
| 1 | "someone who needs multi-session orchestration across machines or 3+ live operators (that's L5, use Nimbalyst/Conductor)" | "one operator running N concurrent same-machine sessions over disjoint goals IS in-scope (a passive running-goal registry, ADR-0022); multi-session orchestration **across machines or by 3+ live operators (a team)** stays L5 (Nimbalyst/Conductor)" |
| 2 | "multi-session coordination across machines or live operators stays L5" | "cross-session coordination for one operator on one machine is in-kit via the running-goal registry (ADR-0022); coordination **across machines, by multiple human operators, or with goal-ordering chains** stays L5" |

### What stays UPHELD (explicitly not loosened)

- **The L5 fence for teams and machines**: across machines (a different `.git` ⇒ a
  different registry), 3+ live *human* operators sharing a pool, and goal-ordering chains
  (B waits for A to merge) all stay L5 (GSD v2 / Nimbalyst). "Several sessions" means one
  human running several, never a team. The registry's `.git`-local location enforces the
  machine fence by construction.
- **No runtime**: the registry records and compares; it never launches a session,
  sequences goals, or merges. No daemon, no lease server, no scheduler, no durability
  state machine. The "In-kit DAG executor" parking-lot entry stays parked; this ADR does
  not unpark it.
- **Bash over binaries**: the registry is flat key=value files read/written by bash; no
  new binary, no `jq` dependency added for the human-legible records.
- **The safety subset**: safety-gate, push-to-main blocker, anti-rationalization, and the
  verification pipeline are NOT loosened. Cross-session safety rides on the registry gate
  + the worktree isolation + human-gated merge.
- **Single-writer per surface**: the registry uses the same one-writer-per-file model as
  the hands-off shared-surface list (SPEC-031); it introduces no shared-write.
- **ADR-0019 and `/kit:dispatch`**: the in-session single-lead fan-out is unchanged; this
  ADR is the cross-session complement, not a replacement.

## Alternatives considered

- **Keep the ban; route all multi-session to Nimbalyst.** Rejected: the single-operator
  multi-window case needs only a passive file registry the kit can own in bash; deferring
  it to a full L5 runtime imposes a heavyweight dependency for a lightweight need. The
  team / across-machines case still routes to Nimbalyst.
- **A coordinating daemon / lock server.** Rejected: a long-lived process to supervise is
  a runtime (the L5 handoff), and breaks bash-over-binaries. The registry needs to record
  and compare, not to schedule or lease.
- **Commit the registry into the repo.** Rejected: ephemeral state churns the repo, and a
  tracked shared file is a write-collision magnet across worktrees, the exact thing the
  disjoint-file rule forbids. The git common dir is per-repo, per-machine, and untracked.
- **A dedicated `/kit:running` command.** Rejected (for now): "Reconcile before adding" +
  minimal surface. The claim folds into `/kit:assign`, the monitor into `/kit:start`; a
  new command would add inventory churn and an orphan-command risk. Revisit only if the
  monitor proves undiscoverable.

## Consequences

- `docs/PHILOSOPHY.md` reframes the two boundaries above from a blanket "stays L5" to the
  bounded one-operator model; the team / across-machines fence is restated, not removed.
  The change is a **boundary/policy restatement**, correct independent of build status.
- `commands/kit-health.md` Step 4 gains a recorded carve-out (alongside the visual-team
  and `/kit:dispatch` exceptions) so the self-assessment does not flag the running-goal
  registry as "duplicates an external tool (Nimbalyst)" or "competes with agent runtimes":
  a passive file registry for one operator's sessions is in-scope per this ADR; only a
  daemon / scheduler / lease runtime is a REJECT.
- `_meta/BACKLOG.md` re-scopes the parked "L5 orchestration ... not needed until 3+
  concurrent sessions" entry to this ADR's boundary (the trigger is teams / machines /
  ordering, not session count).
- The implementing surface is **SPEC-036** (`lib/goal-registry.sh` + the `/kit:assign`
  claim step + the `/kit:start` monitor + the attempt-log convention). This ADR carries
  only the policy decision.
- `docs/architecture.md` cross-references this ADR (the concurrency boundary now names
  both the in-session ADR-0019 case and the cross-session ADR-0022 case).
- `tests/test-meta.sh` asserts this ADR exists, is cross-referenced from architecture.md,
  and that the blanket "multi-session coordination across machines or live operators stays
  L5" no longer survives as the *only* live PHILOSOPHY claim (the reworded form names the
  in-scope one-operator case).

Source: SPEC-036 (conflict C4, TASK-001/002), ADR-0019 (in-session parallel boundary),
ADR-0011 (goal-draft store, disambiguated above), SPEC-031 (single-writer / lead-owned
convergence), `_meta/BACKLOG.md` ID-040. Builds on, does not re-litigate, ADR-0019.
