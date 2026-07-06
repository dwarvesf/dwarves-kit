---
title: "Mega-runner + fast-path: overnight sequential mega-goal queue and the routing triage ladder"
date: 2026-07-04
purpose: >
  Design for two absorptions Han asked for on 2026-07-04 evening: (1) a fast
  path so simple tasks never enter the mega machinery (routing triage, not a
  faster mega), and (2) a runner that executes a queue of mega-goal pointer
  prompts sequentially overnight, reading the queue from the kanban cockpit
  later. Realizes the "Overnight: FULL-AUTO mega-goals via claude -p +
  cron/launchd" slot in 2026-07-04-megagoal-portfolio-scheduling.md section 1.
  This doc is the spec for the v0 experiment and the design source for the
  runner-fastpath mega-goal.
source_repos: [ops-toolkit, dwarves-kit, dotfiles]
refresh_cadence: none
next_review: null
status: active
---

# Mega-runner + fast-path

## AMENDMENT 2026-07-05 (Han-directed; BINDING, supersedes below where they conflict)

**SPINE CHANGE (later same day):** the runner is NOT a Go tool at all. `dwarves-kit/lib/orchestrate.sh` (1783 lines, bash) already drives megas via unattended `claude -p` per sub-goal; the runner is a thin `orchestrate.sh queue` extension (bash, IN the kit) composing `backlog.sh` + `assign` + `orchestrate.sh run`. The Go `tools/mega-runner` (#705) is RETIRED (runner-fastpath 03R). The `board` command also moves INTO dwarves-kit (generic, config-driven). Read the whole "runner" design below as "the kit queue layer"; read "tools/board" as "the kit `board` command". Authoritative current design: runner-fastpath ROADMAP + DECISIONS 2026-07-05 (spine-change + board-to-kit) + goals/03K,04.


Two stack decisions in this doc are superseded (full rationale: runner-fastpath `DECISIONS.md` 2026-07-05):

- **SG-04 board-queue is BASH, not Go.** The kanban table is parsed once, in bash, inside `tools/board/` (a `queue` subcommand; surfaced as `board-all queue` via a thin `_meta` dispatch). The Go `mega-runner` is a pure SCHEDULER: it consumes `tools/board/board queue` output via argv-exec (a `CommandSource` at the QueueSource seam) and NEVER parses a board. Read every "04's Go reader" / Go-side boards.txt parsing below as "04's bash board-parse helper".
- **SG-07/08 board-bridge is BASH, not Python+DuckDB.** The table row at line ~141 ("07 bridge-mirror ... (Python+DuckDB)") is STRICKEN: board-bridge is one bash tool (`queue`/`mirror`/`writeback`); DuckDB stays only in `ledger-observatory`. Their binding design is `2026-07-04-board-hermes-bridge-design.md` + its own 2026-07-05 amendment.

Everything else in this doc (the runner state machine, the marker contract, the queue-row shape, caps/stall/error-stop, the triage ladder) stands unchanged.

**Problem.** A mega-goal takes ~2-3h wall. Two costs follow: simple tasks pay
mega ceremony they do not need, and Han can only supervise one run at a time,
so the queue of drafted megas drains at one per sitting. The fix is one
routing rule + one dumb scheduler, not a faster mega.

## 1. Fast-path triage ladder (routing, not speed)

Decided BEFORE any scaffold exists, at intake (goal-craft / plan-for-goal /
`/kit:mega` mirror):

```
task arrives
  ├─ one file / one behavior / obvious proof ─► DIRECT: kit lane in-session
  │     (lane-classify -> tiny/small; 1 worker + verify + 1 PR;
  │      no scaffold, no conductor; gate-ledger still records)
  ├─ one objective, multiple steps ──────────► single /goal (plan-for-goal)
  └─ multiple objectives / repos / gates ────► mega-goal (plan-for-mega-goal)
```

The kit already ships the bottom half (lane de-escalation nudge, tiny lane);
what is missing is the pre-hoc rule at intake. Landing spots: goal-craft +
plan-for-goal intake step (dotfiles) and the `/kit:mega` mirror paragraph
(dwarves-kit), never-diverge contract as usual. Measure first: the
`mega-durations` observatory query (SG-02) answers where the 2-3h actually
goes before anyone optimizes the mega path itself.

## 2. Mega-runner (sequential overnight queue)

### Contract with the payload (the only clever part)

The runner does not parse roadmaps. It wraps any pointer prompt with a
RUNNER CONTRACT asking the session to end its final message with one marker:

- `RUNNER_DONE` , the pointer's terminal state is reached.
- `RUNNER_GATED: <reason>` , a genuine STOP per the pointer (human gate held,
  launch guard failing, budget). Checkpoint bookkeeping happens BEFORE the
  marker.

This works identically for mega pointers and single-goal pointers, and it
composes with launch guards: a mega whose guard fails simply gates on turn 1
and costs one turn. RUN_REPORT sniffing was rejected (mega-only, and the
conductor writes it before merge-holds anyway).

### Loop (tools/mega-runner, Go per the background-tools directive; built BY the mega, not hand-bootstrapped)

```
per queue.tsv row (slug, repo, pointer):
  skip if journal already has slug=done
  repo must be on its default branch with a CLEAN tree, git pull --ff-only
  1st call:  claude -p "<pointer + RUNNER CONTRACT>" \
               --dangerously-skip-permissions --output-format json
  loop (cap RUNNER_MAX_ITER=12):
    result has RUNNER_DONE  -> journal done, next row
    result has RUNNER_GATED -> journal gated, next row
    stall (branch-tip hash + result text unchanged 2 iters) -> journal stalled
    else claude -p --resume <session_id> "Continue per the pointer..."
  claude exits nonzero -> sleep 30m, retry once; 2nd failure -> journal error,
    STOP THE NIGHT (assume account-level rate limit, do not burn retries)
journal: runs/journal.tsv (ts, slug, result, iters, cost)
logs:    runs/<date>-<slug>.log (full result text per iteration)
```

Safety posture: `--dangerously-skip-permissions` is the meaning of full-auto
overnight; the PreToolUse hooks (secret-guard, destructive-delete,
commit-format) still fire in headless mode, and human gates are pointer
CONTRACT, not permission prompts, so held PRs stay held. The runner itself
never touches git beyond `status`/`pull --ff-only`/`for-each-ref`.

Testability pin: the claude binary is injected (`RUNNER_CLAUDE_BIN`), so the
test suite runs against a stub emitting canned JSON (no API calls in CI); one
real live smoke (haiku) is recorded in the proof-of-done. Markers are matched
LINE-ANCHORED (`^RUNNER_DONE$` / `^RUNNER_GATED:`), so a session quoting the
contract text mid-prose cannot false-trigger.

### Queue source

First cut: `queue.tsv` next to the tool (slug, repo path, pointer path).
Then rows come from the cockpit boards: rows in state `queued` carrying a
runner token in the Notes column (NO new kanban state; the legal states are
owned by `dwarves-kit lib/backlog.sh`), per the board-adapter seam in
2026-07-04-team-collab-workflow-proposal.md section 7. One source of truth
per repo; the tsv remains the offline fallback. Board-sourced tokens are
ALLOW-LISTED: repo must be registered in `_meta/boards.txt`, pointer confined
to `_meta/megagoals/**` or `.claude/goals/**`; anything else is skipped with
a reason (a free-text Notes cell must never grant an unattended
skip-permissions run against an arbitrary path).

### Where it runs

The AIR (Han's explicit call 2026-07-04), inside `caffeinate -dims` + tmux;
Phase 1 is a manual start per night. launchd nightly is PARKED until journal
data proves the cadence (minimum-infra rule). The Mini (always-on; claude
2.1.201 + repos + Max auth already there, attachable from iPhone) stays the
named LATER option if leaving the Air awake proves annoying; same steps over
`ssh mini-tieubao`, nothing else changes.

### Known risks, named

| Risk | Handling |
|---|---|
| Weekly Max cap (one 9-SG mega measured ~2.7M tokens) | error-row stops the night early; journal cost column feeds the decision; runner never auto-retries past 2 failures |
| Dependent megas (B needs A's held PR) | B's own launch guard gates it; the runner just records RUNNER_GATED and moves on |
| Two megas sharing files in one night | not solved in v0; queue discipline (author disjoint rows) + each mega's guard. The merge-queue idea stays in the portfolio note |
| Hung iteration | gtimeout/timeout wrapper when available (2h default), else bare; a hung bare run holds the night, ceiling accepted in v0 |
| Runner modifying itself mid-run | SUPERSEDED 2026-07-05: the Go `tools/mega-runner` (#705) is RETIRED (03R); the runner is `orchestrate.sh queue` (bash launcher, dwarves-kit) |

## 3. The runner-fastpath mega-goal (builds everything; Han runs it tonight via /goal)

Scaffold `_meta/megagoals/runner-fastpath/`. The chicken-and-egg resolves
itself: tonight's run is a normal interactive `/goal`; the mega BUILDS the
runner; the runner takes over from the next night.

| SG | Scope | Repo |
|---|---|---|
| 01 triage-ladder | intake routing rule in goal-craft + plan-for-goal | dotfiles |
| 02 mega-mirror-triage | /kit:mega mirror paragraph + never-diverge row | dwarves-kit (dep 01, wording fixed there) |
| 03 runner-core | `tools/mega-runner` (Go): queue parse, contract wrapper, ralph loop, journal, stall/caps/error-stop; stub-injected tests + one live haiku smoke | ops-toolkit |
| 04 board-tool | the kit `board` command: render migrated + `queue` emit (allow-listed) | **dwarves-kit** (dep: agree queue format with 03K) |
| 05 mega-durations | observatory query: per-rid wall time + phase split from kit_gates (honest-zero) | ops-toolkit; PARKED until gate-review's 04-review-yield-lens PR merges (same adapter files) |
| 06 deploy-runbook | Air runbook (caffeinate+tmux Phase 1, launchd + Mini migration parked) + live local smoke, `gate` | ops-toolkit (dep 03) |
| 07 bridge-mirror | kit `board mirror` (BASH, see 2026-07-05 amendment; NOT Python+DuckDB): opt-in boards + mega cards onto the Hermes kanban, `hermes kanban` CLI loads, idempotent | **dwarves-kit** (dep 04 MERGED) |
| 08 bridge-writeback | kit `board writeback`: Hermes status moves -> staged BACKLOG.md commits via chore/board-sync PRs, row-hash git-wins, `gate` | **dwarves-kit** (dep 07) |

Launch guard: gate-review-absorptions' AUTO lanes complete (01/02/05/06
boxes flipped) AND its RUN_REPORT.md exists or its 03/04 PRs sit held
awaiting Han; the held PRs do NOT block this mega (files disjoint except
SG-05, which parks on its own dependency).

## Backlog map

| Row | Scope |
|---|---|
| ID-274 | umbrella: runner-fastpath mega (this doc + scaffold + v0 experiment) |
