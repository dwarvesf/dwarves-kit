# Goals, mega-goals and the queue: rules, laws, findings

Every implicit state machine and decision in `lib/goal/*`, `lib/mega/mega.sh`, `lib/queue/{queue,watch-board,orchestrate}.sh`
and `lib/decide/flick.sh` that gdp-wired can hold is a native `rule()` / `fun()` in this folder.

- Run `cd lib/rules && node goals/prove.ts` (`--no-bridges` for the proofs alone, about 31 s; `--only <name>`).
- State laws are proven `{from: 'any'}` and must be `proven && checked && !assumes`: every store here is reloaded from disk.
- Each rule keeps at least one broken variant, which must be refused. A variant marked *as found* is the bash before a
  fix in this change.
- Bridges run the real scripts in temp dirs and repos, with `claude`, `gh`, `tmux` and the network stubbed through the
  scripts' own seams (`CLAUDE_CMD`, `GH_CMD`, `GH_BIN`, `MUX_CMD`, `MEGA_MERGE_*_CMD`, `FLICK_TEST`).
- Negative controls: the four bash fixes were reverted in a copy of the kit and every new assertion failed there
  (A10, B9 in runaway-guards; B8, B9 in gate-dispatch; the appendix checks in mega-box).

## Rules

| Rule | Source | Laws | Shipped | Broken variants (all refused) | Bridge |
|---|---|---|---|---|---|
| attempt-state | `lib/goal/attempt-state.sh`, all verbs | 8 invariants + 8 step | proven, any state | second-dispatch, grace-extends, lose-early, recommit, no-exclusion | 2364 agree |
| goal-registry | `goal-registry.sh:reg_claim,reg_release` | 1 + 3 | proven after F1 | **takeover** (as found), no-gate | 3915 agree |
| registry-race | `reg_claim` gate / write / re-read, two sessions | 1 + 1 | proven | no-reread | 96 agree |
| queue-guard | `queue.sh:_breaker_apply,_stall_bump,_schedule_retry`; `watch-board.sh:_guard_skip_reason,_reap_stale_runs` | 4 + 13 | proven after F3 | **error-unbounded** (as found), self-report-clears, no-quarantine-gate, no-beat-gate, stall-unbumped | 96 agree (450 over 3 seeds) |
| queue-conductors | `queue.sh:cmd_run,_beat_claim` + the watcher's re-pick gate | 2 + 1 | proven after F4 | **unclaimed** (as found) | 8 agree |
| queue-night | `queue.sh:cmd_run` row loop | 3 + 5 | proven | skip-resets, no-stop | 25 agree |
| wave-gate | `orchestrate.sh:_wave_gate,_ready_set` | 7 step | proven | no-self-touches, gate-admitted, no-disjoint | 150 agree |
| orchestrate-pick | `orchestrate.sh:cmd_run` cycle body | 6 decisions | proven after F5 | **redispatch** (as found), gate-in-wave | 60 agree |
| mega-status | `lib/mega/mega.sh:_classify,cmd_status` | 6 decisions + 1 finding | proven; F6 refuted | parked-flagged, done-trusted | 120 agree |
| mega-merge | `lib/goal/mega-merge.sh:merge` | 12 decisions | proven | gate-after-execute, fallback-squash, review-merges | 177 agree |
| flick-egress | `lib/decide/flick.sh:main,guard_ok,word_gate_apply` | 8 decisions | proven | short-passes, no-dict-open, deny-unchecked | 120 agree |
| megagoals | `lib/goal/megagoals.sh:count_subgoals,cmd_list` | 6 invariants | proven after F7 | **h1-leaks** (as found), parked-hidden | 120 agree |
| goal-drafts | `lib/goal/goal-drafts.sh:drafts_archive` | 1 + 5 | proven | clobber, archive-unshipped, dry-moves | 1152 agree |
| touches-disjoint | `lib/gate/dispatch-gate.sh:gate_normalize_glob,prefix_overlap` | 1 decision + 1 | proven after F8 | equal-only, **dot-segments** (as found) | 900 agree |

### Laws, by rule

- **attempt-state.** Invariants: a task never has two live attempts; only the newest attempt can be live; no attempt
  exists past the last one dispatched; a task is dispatched exactly when its newest attempt is live; done exactly when
  it has a winner; the winner is a committed attempt; at most one attempt ever commits; a disconnected attempt always
  has a grace deadline. Step laws: an excluded worker is never dispatched again; an attempt is lost only after its
  grace window; a repeated disconnect never pushes the deadline out; a done task keeps its winner; an abandoned task
  never runs again; exclusion is permanent; a finished attempt never moves; losing excludes the worker and frees the task.
- **goal-registry:** no two running goals overlap; a claim never takes over another session's goal; a refused claim
  writes nothing; a release ends the goal.
- **registry-race:** two sessions never both hold overlapping claims; a claim lands only after a clean re-read.
- **queue-guard.** Invariants: a stall count at the ceiling never carries a retry alarm (quarantine); below it, stalls
  always carry an alarm; past the breaker threshold every no-progress run is on the ladder; maxStalls + npTrip
  no-progress runs means quarantine. Never planned: a quarantined slug, a slug with a live heartbeat, a done/gated slug,
  a slug in backoff or cooldown. Step laws: a self-report never clears the ladder; a stalled run with no verified
  delta climbs it, and so does a dead conductor; the retry alarm lands in the jitter window; the breaker never rewrites
  done/gated; done only with a git delta; a run ends its claim; a done/gated slug is never launched again.
- **queue-conductors:** never two conductors on one slug; a running conductor holds the beat; a slug with a live beat
  is never launched again.
- **queue-night:** an unstopped night never carries two failures in a row; never more than `--max-megas` launches; a
  stopped night opens no window; two consecutive error/stalled rows stop the night; skipped, held or terminal rows
  never move the streak; done or gated resets it; only a launched row counts.
- **wave-gate:** admitted only into a free slot under WAVE_CAP; only when provably disjoint from every member (an
  unprovable glob only alone); never a gate or gate!; never a checked or dep-blocked sub-goal; never one without its
  own Touches; never one whose dependency has not converged; never a running member.
- **orchestrate-pick:** a held gate is never re-dispatched; a held gate! neither; a held chain-stop gate never blocks a
  ready independent sub-goal; a ready gate! halts everything else; a dep-blocked pick is never dispatched on the wave
  path; a wave never carries a gate.
- **mega-status:** a checked box is OK only when its PR is verified MERGED; parked is informational and never drift;
  unchecked with a merged PR is MERGED-UNCHECKED; STALLED means the branch exists with 0 commits and no open PR;
  commits or an open PR are never STALLED; drift is exactly the three warning classes.
- **mega-merge:** never merged when the gate fails, the PR is held, its state is unreadable, it touches `.kit.toml` or
  its file list is unreadable, under per-pr-review, without `--execute`, when the head moved after the pin, when the
  base was retargeted, or when the merge command is unreadable. A head that moved since the join exits 75. A refused
  project merge command never falls back to the plain squash.
- **flick-egress:** nothing leaves with no backend, a disabled point, or an empty deny list; deny-word, non-slug and
  non-public questions never leave; with the word gate on, nothing leaves without a usable dictionary, and a candidate
  leaves only if every segment is a dev word, a kit-public name or a dictionary word.
- **megagoals:** done + open + parked = total; the counted section is open exactly inside Sub-goals/Status; no box
  outside is counted; open work is always listed; parked-only megas are listed; fully done megas are hidden unless `--all`.
- **goal-drafts:** a draft is never deleted; archived only when its spec is SHIPPED; an archived copy is never
  overwritten; a dry run moves nothing; specless and unresolvable drafts stay; a second archive moves nothing.
- **touches-disjoint:** a pair the gate proves disjoint never shares a file (proven after F8).

## Fixes

| # | Law that was broken | Fix | Before → after | Test added |
|---|---|---|---|---|
| F1 | A claim never takes over another session's running goal (ADR-0022, single writer). | `goal-registry.sh` `reg_claim` refuses a slug whose record names another worktree (`REFUSED: goal '<slug>' is already claimed by the session in '<wt>'...`). | Session 1's `claim s0` over session 0's rewrote `worktree=` (exit 0). Bridge 3915 agree. | `tests/test-hooks.sh` registry block (3 checks) |
| F3 | maxStalls + npTrip no-progress runs means quarantine (watch-board.sh rule 5). | `queue.sh` `_breaker_apply`: a breaker trip also climbs the stall ladder. | Six dead-window runs left `stalls=0 noprogress=6`, re-planned forever. Now `stalls=5`, quarantined. | `tests/test-runaway-guards.sh` B9 |
| F4 | A slug is never run by two conductors at once. | `queue.sh`: `_beat_claim` (noclobber, atomic create); `cmd_run` skips a held row. | A watcher plan plus a beat let `queue run` open a second window that killed the first conductor's window and deleted its beat. | `tests/test-runaway-guards.sh` A10 |
| F5 | A held gate (PR open) is never dispatched again, and a held chain-stop gate never blocks an independent ready sub-goal (ADR-0030 verification 4). | `orchestrate.sh` `cmd_run`: a gate whose PR exists is held; under waves the first sub-goal `_wave_gate` admits runs; otherwise STOP `... is a held <policy> sub-goal; its PR is open and waits for a human merge.` | Every re-run sent SG-01 (gate, PR open) to a fresh session, and SG-02 never ran. The as-found variant agreed with old bash 40/40. | `tests/test-orchestrate-gate-dispatch.sh` B8, B9 (its fake session now opens the gate PR during the run) |
| F7 | A box outside the Sub-goals/Status sections is never counted (megagoals.sh header). | `megagoals.sh`: `insec && /^# / { insec=0 }` | A box under a later `# Appendix` counted as open work. | `tests/test-mega-box.sh` section 6 |
| F8 | A pair `dispatch-gate disjoint` proves disjoint never shares a file. | `dispatch-gate.sh` (fixed by the lead): a `/**` prefix with an empty, `.` or `..` segment, or a leading `/`, is unprovable (`?`), never disjoint. | `./**` vs `a/**`, `a/./**` vs `a/a/**`, `a//**` vs `a/b/**`, `b/../a/**` vs `a/**` all exited 0 (disjoint); `goal-registry claim` accepted both `./**` and `lib/**`, and `_wave_gate` could put such sub-goals in one wave. | `tests/test-dispatch-gate*.sh` (see the suite) |

## Findings kept (not fixed)

- **F6 — `mega status` mislabels rows as PENDING.** The header says PENDING means "no branch, no PR at all", and the
  rule refutes that law. An existing branch measured against a missing `--base` prints PENDING (the default base is
  `master`, so any `main` repo hits this; `_commit_count` swallows the failed `rev-list`, so STALLED/WIP never fire).
  A row that cites an OPEN or CLOSED PR but has no branch also prints PENDING. A proper fix needs a default base taken
  from the repo's default branch, or a new label in `labels.tsv` (shared with `mega-review.py`): a maintainer's call.

## Positive result

- **F2 — the registry claim protocol is race-safe.** Two sessions interleaving `reg_claim`'s gate, its non-atomic write
  (a reader treats a half-written record as no record) and its re-read can never both hold overlapping claims. The
  bridge injects the other session's record between the gate and the write through a `date` stub: 96 cases agree.

## Smaller observations (not modelled)

- `_journal_count` says it counts terminal rows but counts all rows, so `queue wait` returns 0 on a `skipped` row.
- SYSTEM-DESIGN says a plain `queue run` skips only `no-delta` gated rows; the code skips every gated row.
- The protected-path list misses a nested `sub/CLAUDE.md`.
- The reaper treats an old beat as a dead conductor; after a laptop sleep, the missed watcher tick that fires on wake
  can reap a live conductor.

## Implicit machines found but not modelled

- `sanitize.sh` (a perl string pipeline).
- `_scan_marker` and the `_launch_once` poll loop (text and timing).
- `stack-merge.sh` (side-effect choreography on GitHub).
- `wt.sh close` (depends on `lib/gate/branch-merged.sh`).
- The mkdir flip lock (process liveness).
- The `_wave_run` reap loop and `_wave_converge`.
- The no-claim retry and turn-cap counters, and the tier-4 aggregation.
- The custom merge-command exec/verify arms: proven but not bridged (they need a GitHub remote).
- ql-verdict: modelled, fixed and bridged by the hooks area (`lib/rules/hooks/ql-verdict.ts`).
