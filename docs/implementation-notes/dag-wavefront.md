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

## 2026-07-03 15:00 , TASK-002 mkdir-lock + cmd_flip

**Context.** TASK-002 needs a mutual-exclusion primitive for concurrent box flips plus a `cmd_flip`
subcommand. Spec pins the mechanism (`mkdir` lock, PID-liveness stale reclaim, write-temp-then-`mv`)
but leaves a few knobs to the implementer.

**Decisions (the deltas the spec/DEC-009 did not pin).**
- **Retry sleep = `FLIP_LOCK_POLL_SECS` default `0.1`.** A new env knob (not in the spec) for the
  short block-and-retry interval while a LIVE holder owns the lock. BSD `sleep` on the macOS CI
  runner accepts fractional seconds. Reclaim of a crashed holder is immediate (`continue`, no
  sleep), so the poll interval only paces waiting on a genuinely-busy holder.
- **Empty/unreadable pid file is stale only past the timeout, not immediately.** The spec's reclaim
  rule keys on "recorded PID dead". A pid file that is absent/unreadable (the race window: `mkdir`
  won but `printf $$ > pid` has not landed yet) is treated as stale ONLY once the lock age exceeds
  `FLIP_LOCK_STALE_SECS`, so a lock created microseconds ago by a live sibling is never yanked. A
  present-but-dead PID is reclaimed immediately (crash case). This maps the spec's two clauses onto
  three concrete states (alive / dead / unreadable).
- **`_unlock` ownership guard.** Releases only a lock whose pid == `$$` (or an empty pid); never
  rmdir's a different LIVE holder's lock. Defends against a double-unlock / reclaim-race yanking the
  wrong holder.
- **No `rm` anywhere.** Reclaim + unlock move the pid file to `$TMPDIR` then `rmdir` the emptied
  dir (spec: "removing the pid file then rmdir", never `rm -rf`). The failed-write path likewise
  `mv`s the temp aside rather than `rm`-ing it. Satisfies the repo's no-bare-`rm` safety rule.
- **Atomic flip via same-dir mktemp.** The temp is `mktemp "$megadir/.roadmap.flip.XXXXXX"` (same
  filesystem as ROADMAP.md) so `mv -f` is a true atomic rename; the leading dot + non-`- [` prefix
  keeps a stray temp from ever matching a sub-goal grep. Idempotency + existence are re-checked
  UNDER the lock (a sibling may have flipped the box between the pre-lock probe and acquire).
- **Optional event emitted.** `cmd_flip` appends a `flip / box checked` event to the shared
  `.orchestrate/events.log` (the spec allowed this as optional). NO scheduling wired: `cmd_flip` +
  the lock helpers have zero call sites in the run loop; waves land in TASK-003/004.

**Impact.** `bash tests/test-orchestrate-wavefront.sh` 29/29 green (16 existing + 13 new; bash
3.2.57 + bash 5.3); `bash tests/test-orchestrate.sh` 59/59 green (no regression); `shellcheck -s
bash lib/orchestrate.sh` clean. New tests cover: correct-box flip + idempotency + unknown-id, 6
parallel flips on distinct boxes all landing with a well-formed ROADMAP, and a dead-PID stale-lock
reclaim guarded by a poll-timeout so a hang reads as FAIL.

## 2026-07-03 14:30 TASK-003 `_wave_gate` greedy admission

Delta from SPEC-106 (TASK-003 / DEC-007 / DEC-012b). Two judgment calls the spec left to the
implementer:

- **REUSE via SUBPROCESS, not source (2+-option call).** dispatch-gate.sh is the one disjointness
  authority (DEC-001), so `_wave_gate` must reuse it, not reimplement glob-disjointness. Options: (A)
  `source lib/dispatch-gate.sh` and call `gate_touches`/`gate_disjoint` in-process; (B) call
  `bash "$gate" touches|disjoint ...` as a subprocess. Chose **B**. Decider: dispatch-gate.sh runs
  `set -euo pipefail` at load (L26); sourcing it leaks `-e` into orchestrate.sh's deliberate `set -uo`
  posture (L33) AND into the sourced test harness (test-orchestrate-wavefront.sh sources
  orchestrate.sh), which would flip the whole harness to errexit. The subprocess boundary contains
  the `-e`; verified with `source lib/orchestrate.sh; case "$-" in *e*)` -> no leak. Fork-per-pair
  cost is negligible for a wave-launch decision over a small ready set. `disjoint` exit 0 = provably
  disjoint => admit-eligible; any nonzero (1 overlap / 2 undeclared) => not disjoint => defer.
- **Self-Touches detection = `gate_touches` non-empty.** A candidate admits only if
  `bash "$gate" touches "$gf"` is non-empty (its goal file declares its OWN `## Touches`). This is the
  real opt-in gate (DEC-012b): `gate_disjoint` admits the first member vacuously (empty admitted set),
  so a Touches-less sub-goal would be wrongly admitted without this. Touches-less or goal-file-less
  => always `defer`.
- **Admitted-set accumulation = plain bash array (not assoc).** bash 3.2 has no assoc arrays; the
  admitted set is `admitted_files=()` (goal-file paths), iterated with the empty-guard
  `${arr[@]+"${arr[@]}"}` (DEC-005, mega-merge.sh:224). The ready set is fed by **process-sub**
  (`< <(_ready_set ...)`) not a pipe, so the admitted state lives in THIS shell, not a while-subshell.
- **Defensive cap guard (belt-and-braces).** `case "$cap" in ''|*[!0-9]*) cap=1` prevents a
  non-numeric WAVE_CAP from making `[ -lt ]` emit a bash integer error on a direct call. The
  spec's parse-time rejection of `<1`/non-numeric WAVE_CAP is TASK-004b's wiring boundary; the wired
  path only ever hands `_wave_gate` a validated cap, so this fallback is never a substitute for that.

**Placement + scope.** `_wave_gate` sits right after `_goalfile` (both deps `_ready_set` + `_goalfile`
defined above). PURE decision helper: spawns nothing, zero call sites in cmd_run (wiring is TASK-004).

**Impact.** `bash tests/test-orchestrate-wavefront.sh` 35/35 green (29 existing + 6 new; bash 3.2.57);
`bash tests/test-orchestrate.sh` 59/59 green (no regression); `shellcheck lib/orchestrate.sh` clean.
New tests: (a) disjoint declaring pair @cap 2 -> both run; (b) overlapping declaring pair -> first
run/second defer (exit-criterion-2 negative control); (c) Touches-less ready set -> all defer
(Option-B gate); (d) cap 1 on the disjoint pair -> at most one run; (e) Touches-less-first/declaring-
second -> defer/run (per-candidate self-Touches, not first-wins); (f) unset WAVE_CAP == cap 1.

## 2026-07-03 01:37 TASK-004a `_wave_run` concurrent spawn/reap primitive

Delta from SPEC-106 (TASK-004a / invariant 5 / failure-modes table). The judgment calls the spec
left open:

- **Worktree-in-tests = a real throwaway `git init` repo (not a stub).** The spec offered "real git
  repo OR factor `_wave_worktree` so a test points it at a tmp dir". Chose the real-repo path for ALL
  wave tests: a `mk_git_mega` helper `git init`s a throwaway repo with the mega-goal dir at
  `<repo>/mega`, so `_wave_run` derives the repo root via `git -C "$megadir" rev-parse
  --show-toplevel` and stands up GENUINE worktrees at `<repo>/.claude/worktrees/<id>` (the repo-wide
  location per the global rule, NOT the megadir). This exercises the real collision/reuse/recreate
  logic instead of mocking it. `_wave_worktree` is still factored as its own helper (clean seam), but
  no test escape-hatch was added. Note: `show-toplevel` returns the symlink-resolved path, so
  worktrees land under `/private/var/...` while `$TMP` is `/var/...`; self-consistent, harmless.
- **Reap map = index-aligned plain arrays (`_WAVE_PIDS` / `wave_ids` / `wave_done` / `wave_pfiles`),
  NOT an assoc array.** bash 3.2 has no `declare -A`. `_WAVE_PIDS` is a GLOBAL (not a `_wave_run`
  local) precisely so the INT/TERM `_wave_abort` trap can reach the PID set while `_wave_run` is on
  the stack; the parallel arrays are locals. Empty-guarded `${_WAVE_PIDS[@]+"..."}` in the trap
  (DEC-005) for the fire-before-any-spawn case.
- **Reap = `kill -0` poll + `wait`, never `wait -n`.** Generalized `_run_session_watchdog`'s single-
  PID `while kill -0 "$spid"` (L493) to N PIDs: each poll iterates all not-yet-done indices, and a
  PID that fails `kill -0` is reaped once with `wait "$pid"` (bash caches a finished background job's
  status until waited, so the reap after bash's own SIGCHLD-reap still yields the real rc). `wait -n`
  is bash 4.3+ and absent on the macOS 3.2 CI.
- **Drain semantics = set-a-flag, never-break.** On a nonzero exit OR an unflipped box, `wave_failed=1`
  and the loop CONTINUES; healthy in-flight siblings are never `kill`ed and drain to completion in
  their worktrees; `_wave_run` returns nonzero only after every PID is reaped (invariant 5). The trap
  is the ONLY path that kills, and only on an operator abort (INT/TERM), so a normal sibling-failure
  never orphans or murders a peer.
- **Grounded check reads the SHARED roadmap, never flips.** Per DEC-008 the SESSION flips its own box
  (via the locked `orchestrate.sh flip` CLI); `_wave_run` only CHECKS via `_subgoals` on
  `$megadir/ROADMAP.md`. Sessions are backgrounded `cd`'d INTO their worktree for genuine isolation;
  `_run_one_session`'s `_ROS_SLOG` global is unused on the wave path (det-handoff regen is TASK-005),
  so losing it in the subshell is fine.

**Concurrency-proof mechanism (the load-bearing test).** Two disjoint admitted sub-goals; each mock
opens its OWN fifo AND the sibling's fifo read-write (`exec 3<>IN; exec 4<>OUT` , the RDWR open is
non-blocking so a lone process does not deadlock on `open`), writes a token to the sibling, then
`read -t <IN`. A read only unblocks once the sibling has WRITTEN, which requires the sibling to be
ALIVE at that instant , true temporal overlap. A SERIAL impl runs A fully first; A's `read -t` finds
no writer and TIMES OUT (4s) , A exits nonzero WITHOUT flipping , the "both boxes flipped + rc 0"
assertion FAILS. Verified a serial run fails via a standalone probe (A-alone timed out at 4s, rc 7).

**Deviation worth logging , the concurrent-flip lost-update.** First green-barrier run FAILED: both
mocks passed the barrier and both flipped, but their raw `awk+mv` flips RACED and the second `mv`
clobbered the first (SG-01's flip lost). Fix: the barrier mock flips via `bash "$ORCH" flip
"$MEGADIR" "$id"` , the mkdir-locked `cmd_flip` CLI (TASK-002) , exactly the real session contract
(DEC-008 "the session's contract calls `cmd_flip`, not a local `sed`"). So the concurrency test now
also proves concurrent flips are lock-safe (no lost update), not just temporal overlap. This is the
V-CRIT-2 / DEC-008 hazard surfacing live in a test.

**Orphan check.** Each mock touches `$RUNDIR/<id>.running` on start, clears it on EXIT (trap); the
test asserts zero `.running` files after `_wave_run` returns, proving no mock was left orphaned by
either the normal drain or a sibling failure.

**Scope.** `_wave_run` has ZERO call sites in the run loop (cmd_run untouched); wiring + size-dispatch
on admitted count is TASK-004b. Cleanup removes wave worktrees via `git worktree remove --force`
(never `rm -rf` a worktree path). `WAVE_POLL_SECS` (default 0.2) added as the reap-poll interval knob.

**Impact.** `bash tests/test-orchestrate-wavefront.sh` 43/43 green (35 prior + 8 new; bash 3.2.57 AND
5.3, stable over 9 repeated runs , no flake); `bash tests/test-orchestrate.sh` 59/59 green (no
regression, both bashes); `shellcheck -s bash lib/orchestrate.sh` fully clean.

## 2026-07-03 01:53 TASK-004b , size-dispatch `cmd_run` to the wave path

Context / Decision. Wired `_wave_run` into `cmd_run` via ADMITTED-count size-dispatch, keeping the
default (WAVE_CAP=1) path byte-identical to the pre-wavefront serial loop (the sacred invariant).

Dispatch shape (how the serial path stayed byte-identical). A single new guarded block sits at the
TOP of the `while :;` loop, textually BEFORE the untouched `local nx id policy` serial body:
`if [ "$WAVE_CAP" -ge 2 ]; then admitted_n=$(_wave_gate ... | awk '$1=="run"'); [ "$admitted_n" -ge 2 ]
&& { _wave_run && continue || return 1; }; fi`. The serial body below it is not edited at all , the
wave branch either `continue`s (recompute next cycle from the re-read ROADMAP) or `return 1`s, else
falls through. Because WAVE_CAP defaults to 1, the `-ge 2` guard is FALSE on the default path, so
`_wave_gate`/`_wave_run` are NEVER called and the loop runs exactly as before , byte-identity is
STRUCTURAL (the guard short-circuits), not merely test-asserted. This deviates slightly from the
spec's literal "compute `_wave_gate` each cycle": at CAP=1 the gate is provably all-`<=1`-admitted, so
skipping it is logically equivalent AND strictly safer for the byte-identical invariant (zero new
subprocess forks on the default path). Recompute-and-relaunch cannot double-launch / overshoot CAP
because `_wave_run` blocks until the wave drains (one blocking wave per cycle) and re-reads ROADMAP.

Why dispatch on ADMITTED, not raw ready size (DEC-012a). A no-deps mega-goal has ready size N (nothing
blocks), so raw ready size can never gate the serial path; `_wave_gate` first, then branch on the
`run`-line count. A Touches-less mega (every real one today) admits 0 -> serial fallback.

WAVE_CAP validation placement. Global default `WAVE_CAP="${WAVE_CAP:-1}"` added next to the other env
knobs (so the top-of-loop `-ge 2` test is `set -u`-safe), and PARSE-TIME rejection added at `cmd_run`
entry, AFTER the dir/roadmap/board checks and BEFORE the `--dry-run` block (so `--dry-run` also
rejects a bad cap): `case ... ''|*[!0-9]*) return 64` (empty/non-numeric/negative) then `[ -lt 1 ]
return 64` (rejects 0). Non-numeric / <1 fails loudly with a `WAVE_CAP`-named message + exit 64,
never silently coerced (DEC-009 / Edge case 4). `_wave_gate`'s own belt-and-braces coerce-to-1 stays
as defense for direct (non-`cmd_run`) callers; the entry rejection is the real gate.

Gate / `--step` / `--stream` / `--board` on the wave path are intentionally NOT handled here , that is
TASK-005/007 scope. At the default CAP=1 they are all untouched (serial path), which is the only
invariant 004b owes. A gate sub-goal cannot reach a wave on any real mega-goal today anyway (needs its
own `## Touches`, which no real sub-goal has , Option-B), so no live gate-bypass ships.

Impact. `bash tests/test-orchestrate.sh` 59/59 (unchanged , byte-identical serial invariant holds);
`bash tests/test-orchestrate-wavefront.sh` 53/53 (43 prior + 10 new: j serial-fallback, k full
cmd_run->wave concurrency via the barrier fifo, l WAVE_CAP=0/non-numeric rejection). Stable over
repeated runs, no flake. Tests j-l drive `cmd_run` OUT-OF-PROCESS so the real WAVE_CAP env + parse
validation are exercised.

## 2026-07-03 02:10 TASK-004c , wave convergence sequencer

`_wave_converge <megadir> [<id>...]` added to `lib/orchestrate.sh`, right after `_wave_run`. It merges a
landed wave's sub-goals back to the mega-goal base ONE AT A TIME, in ROADMAP order, each under the flip
lock. Deviations / decisions the spec did not pin down:

WAVE_MERGE_CMD deferral. The actual merge is a MOCKABLE hook `WAVE_MERGE_CMD` (default
`$ORCH_DIR/mega-merge.sh merge`), word-split like CLAUDE_FLAGS. `mega-merge.sh` is NOT edited , its merge
semantics stay untouched; convergence only SEQUENCES calls to it (spec Out-of-Scope). Real gh-backed
merge stays DEFERRED to ID-085-followup (same posture as the flip-contract prompt injection): waves are
off at the default WAVE_CAP=1 so the hook is never reached in the serial path, and a real merge needs
`gh` + real PRs. The hook is invoked `$WAVE_MERGE_CMD <pr> <id>`. The default real target's own signature
is `merge <pr> <rid> <lane>`, so `<pr> <id>` would be a usage error , acceptable because the default is
never invoked under CAP=1 (no wave) and tests always override WAVE_MERGE_CMD with a recording mock. Full
`<pr> <rid> <lane>` wiring lands with ID-085-followup.

Same-file detection approach. Belt-and-suspenders over dispatch-gate's PRE-admission disjointness (the
SPEC-106 risk row: a disjointness false-positive could yield a clean-but-wrong merge). For each landed
sub-goal I diff its branch vs the base , `git diff --name-only <base>...<branch>` (three-dot = changes on
the branch since its merge-base) , dedupe per branch (`sort -u`), then across the union a file appearing
>=2 times (`sort | uniq -d`) was touched by >=2 branches => overlap. On overlap: emit a `blocked` event,
print the offending file(s) to stderr, return nonzero, and merge NOTHING (refuse rather than land a
clean-but-wrong merge). base = the mega repo's current HEAD branch (`rev-parse --abbrev-ref HEAD`);
branch = `_sg_branch` (the goal file's `**Branch:**` header, else `wave/<id-lower>`).

Placeholder-PR skip (new, spec did not specify). A landed sub-goal whose ROADMAP line still has `PR #__`
(no real PR opened yet) is SKIPPED with a notice, not failed. This keeps the deferral honest (no real PRs
exist yet) AND keeps the existing TASK-004b dispatch test `k` green: its barrier mock flips boxes but
opens no PR, so convergence now runs on it (via the wiring below) and must no-op cleanly. `_sg_pr` parses
`PR #<n>`; empty => skip.

Wiring point. Called from `cmd_run`'s wave-success path (the TASK-004b `if _wave_run ...; then` block),
BEFORE the `continue`: `_wave_run` now appends each grounded-complete id to a new GLOBAL `_WAVE_LANDED`
(reset per run, sibling of `_WAVE_PIDS`), and `cmd_run` hands that set to `_wave_converge`. A convergence
flag (same-file overlap or merge-hook failure) halts the loop (`return 1`, no self-claim). At the default
WAVE_CAP=1 the whole wave block is unreachable, so the serial path is byte-identical
(`tests/test-orchestrate.sh` 59/59 unchanged). Ordering is by ROADMAP position, not argv , test `m`
passes ids reversed (SG-02 SG-01) and still asserts SG-01 merges first.

Serialization proof. The mock appends `enter:<id>:<pr>` / `exit:...` around a 0.2s sleep; test `m` asserts
the exact non-interleaved sequence `enter:SG-01 exit:SG-01 enter:SG-02 exit:SG-02`. A concurrent
sequencer would interleave the markers, so this is a strict no-temporal-overlap proof (stronger than a
coarse `date +%s` gap, and portable , macOS BSD `date` has no sub-second `%N`).

Impact. `bash tests/test-orchestrate.sh` 59/59 (byte-identical serial invariant holds);
`bash tests/test-orchestrate-wavefront.sh` 61/61 (53 prior + 8 new: m serial-order proof, n same-file
flag + no-merge + message, o placeholder-PR skip). Stable over repeated runs, no flake.
