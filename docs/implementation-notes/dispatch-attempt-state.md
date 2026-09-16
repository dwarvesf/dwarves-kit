# Implementation notes: dispatch attempt state

Delta from SPEC-290 and from the board row ID-882. Decisions the spec left open, and where the
build departs from the row's wording.

## 2026-09-16 Decisions the row left open

**Context**

Board row ID-882 named the shape (TaskState, AttemptState, a legal-transition table,
`mark_disconnected`, `lose_attempt`, `commit_result`) and the reference implementation
(`VoiceStudio backend/worker/lifecycle.py`). It left the language, the store, the state rosters,
and the grace default open. The research note the row cites no longer exists on disk, so the
contract came from `lifecycle.py` and the row text.

**Decision: bash, in `lib/goal/attempt-state.sh`, a new file beside `goal-registry.sh`**

`bin/precedent find --surface inventory --quiet attempt state` reported no existing attempt
machinery. Its nearest hit was the module this one sits beside:

> kit lib/goal/goal-registry.sh , goal-registry.sh -- the cross-session running-goal registry.

**Why** Bash keeps the store readable by the same `.git`-backed convention `goal-registry.sh`
uses, so a lead reads both with one set of habits. The transition table is two newline-delimited
strings matched with `grep -qx`, which stays legible without associative arrays, so the Apple bash
3.2 constraint costs nothing. Python would have added a second language for a state file the kit
reads from shell.

**Why not extend `goal-registry.sh`** Different grain. That module tracks one goal per SESSION for
disjointness. This tracks many attempts per TASK for outcome. Merging them would give one file two
state machines and two store layouts.

**Decision: a smaller state roster than `lifecycle.py`**

`lifecycle.py` carries ten task states and twelve attempt states, most of them GPU-inference
phases (`model_loading`, `result_uploading`). This build keeps four task states
(`queued`/`dispatched`/`done`/`lost`) and five attempt states
(`running`/`disconnected`/`committed`/`lost`/`superseded`).

**Why** The phases a subagent passes through are not observable from the lead, so a state for each
would never be written. `superseded` is kept because the row's own "a second commit reports which
attempt won" requires a name for the loser.

**Alternatives** Porting the full roster. Rejected: unwritable states make the transition table
lie about what the machine can prove.

**Decision: `dispatch` refuses a second live attempt**

The row asked for a grace window and no second dispatch inside it. The build enforces that in
code: `dispatch` exits 1 while any attempt is `running` or `disconnected`.

**Why** The row's rule was prose a lead follows under load. A refusal is a guard. It also makes the
row's headline scenario a one-line test.

**Impact** A deliberate parallel attempt on one task is impossible. That is intended here; nothing
in `/kit:dispatch` or `/kit:execute` wants two agents on one spec.

**Decision: kebab verbs with underscore aliases**

The row writes `mark_disconnected`, `lose_attempt`, `commit_result`. Kit subcommands are kebab
(`lose-attempt`). Both spellings dispatch to the same function.

**Why** The kit convention wins for the canonical name; the alias costs one `case` label each and
means prose quoting the row resolves.

**Decision: `--grace`, default 120 seconds, plus `ATTEMPT_NOW` for tests**

One constant, `ATTEMPT_GRACE_DEFAULT_SECONDS`, and one flag. No environment variable, so the
`KIT_*` name lint has nothing to check. `ATTEMPT_NOW` pins the clock so the grace tests assert
expiry without sleeping; `ATTEMPT_REGISTRY_DIR` mirrors `GOAL_REGISTRY_DIR`.

**Decision: SPEC-290, not the 289 `spec-next.sh` offered**

Open PR #649 adds `docs/specs/SPEC-288-ui-acceptance-verifier.md`, which already collides with
`SPEC-288-codex-hook-parity.md` on master. Resolving that collision most likely takes 289.

**Why** A number hole costs nothing; a second collision costs a rename after review.

**Decision: a repeat `mark-disconnected` does not refresh the window**

Found by the test-coverage review. `mark-disconnected` used to overwrite the deadline on every
call, so a lead (or a loop) signalling the same silence twice could hold a task indefinitely.

**Why** The window measures how long since the worker was last heard from. A second disconnect
signal carries no word from the worker, so it is not evidence of anything. Only `resume` clears
the window.

**Decision: `abandon` supersedes any live attempt**

Found by the architecture review. `abandon` moved the task to `lost` while leaving a `running` or
`disconnected` attempt untouched, a record no verb could resolve afterwards.

**Why** One invariant matters here: the task state reflects its live attempt. A verb that can break
it in one call is worse than no verb.

**Not taken: factoring `registry_dir` and the id guard into a shared store helper**

The architecture review flagged that `registry_dir` and `_check_id` near-duplicate the equivalents
in `goal-registry.sh`. Two call sites, about fifteen lines, and the two modules have different
lifecycles.

**Why not** A shared helper couples two modules that are independent today and buys nothing until
a third store exists. Revisit at the third.

**Open questions**

- The `megagoal-agent-drive` skill lives in `~/.claude/skills` (dotfiles-managed) and was not
  edited. It still tells a lead to resume rather than respawn in prose only, with no attempt state
  behind it. Wiring it is a follow-up in that repo.
- Nothing prunes `kit-attempts/`. `release <task>` exists but no caller runs it yet;
  `commands/dispatch.md` Step 6 already releases the goal registry and is the natural place.
