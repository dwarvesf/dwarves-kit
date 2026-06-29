# SPEC-087: Inter-sub-goal context hygiene (orchestrator + feed-forward handoff + distilled returns)

Status: DRAFT
Date: 2026-06-29
Lane: normal (classified: normal)
Type: design + impl (orchestrator built in token-hygiene SG-04; distilled-returns is phase 2)
Board: token-hygiene mega-goal SG-03/SG-04 (ops-toolkit `_meta/megagoals/token-hygiene/`); kit intake ID operator-assigned

## Problem

A mega-goal run under the kit is one un-cleared session whose context grows monotonically
across 6-10h. Cost is dominated by `cache_read`: the whole accumulated context is re-read
every turn (~58.5% of spend; ops-toolkit `research/2026-06-28-token-spend-forensic.md`). Three
drivers:

1. **One marathon session.** The `/goal` loop runs every sub-goal in a single session whose
   context only grows. The kit cannot fix this by self-`/clear`ing: a `/clear` inside the loop
   kills the loop's own driving context.

2. **Full subagent returns.** Inside a sub-goal, `/kit:execute` dispatches 5-9 subagents
   (workers, task-verifiers, reviewers) and the lead absorbs each one's FULL output. The state
   flow distils nothing between phases (`WORKFLOW.md:651-652`); the execute loop re-enters the
   lead after every increment (`WORKFLOW.md:707-712`). A 16-25K-token return per subagent,
   multiplied across a sub-goal, lands permanently in the lead.

3. **Re-discovery tax.** Reading a real run's log, each step spends many turns re-finding
   context (which files, which interface) that an earlier step already knew, because nothing
   is handed forward (operator observation, 2026-06-29).

This SPEC supersedes its own v1 ("operator checkpoint signal"): an advisory "safe to /clear"
that a human performs defeats the kit's automation premise (the kit exists to run without a
human in the middle). The fix is to move the loop OUT of the LLM session.

## Design

### Mechanism A: outer orchestrator (the structural fix)

A **non-LLM** driver owns the loop; the LLM work happens only in disposable per-sub-goal
sessions.

```
orchestrator (bash/SDK, NOT an LLM context)
   ├─ claude -p (fresh session, empty context) -> SG-01 -> ship PR -> write HANDOFF -> exit
   ├─ claude -p (fresh session, empty context) -> SG-02 -> ship PR -> write HANDOFF -> exit
   └─ ... stop at the first `gate` sub-goal (shared-repo review needs a human)
```

- Each `claude -p` invocation is a new session, so the `/clear` happens for free; no session
  ever holds more than one sub-goal's context. The monotonic growth (driver 1) is removed
  structurally, with no human and no kit self-clear.
- **The driver must be non-LLM** (DEC-004). If the orchestrator were itself a persistent
  Claude session spawning a subagent per sub-goal, that session would re-accumulate every
  return and become the new marathon. A subagent reports back into a parent LLM context; only
  a dumb driver avoids re-accumulation.
- **Gate sub-goals stop the orchestrator** (DEC-005). A shared-repo (`gate`) sub-goal needs
  team review before its dependents proceed; the orchestrator runs the `auto` chain
  back-to-back and halts at the first `gate`, printing the held PR. "No human in the middle"
  holds for the auto chain, not for shared-repo merges (which are intentionally human).
- **Completion is grounded, not self-claimed**: after a session returns, the orchestrator
  re-reads the ROADMAP; it advances only if the sub-goal's checkbox flipped to `[x]`. A
  session that returns without checking its box is a failure, and the orchestrator stops
  rather than spinning. (Future guard, noted not yet built: also assert the working tree is
  clean before advancing, so a session that died mid-edit halts the loop rather than handing a
  dirty baseline to the next sub-goal.)

### Mechanism B: feed-forward handoff (kills the re-discovery tax)

Each sub-goal session, on completion, writes a `HANDOFF.md` for the next one; the orchestrator
injects the previous HANDOFF into the next session's prompt. This turns driver 3's
re-discovery into a read.

```
HANDOFF.md (written by the sub-goal that just finished)
- Next sub-goal: SG-NN  (goal file: goals/NN-*.md)
- Files / symbols it will touch: <paths, the ones already located>
- Constraints already fixed: <e.g. SG-01 named the field `parent`; reuse it>
- Open risks / gotchas: <...>
```

Distinct from `POINTER_PROMPT.md`, which is static (it points at the ROADMAP). The handoff is
dynamic, per-transition, and must be **grounded** (cite real files / PRs), so it cannot become
an optimistic lie about the next step; the receiving session verifies before trusting.

### Session invocation (the per-sub-goal `claude -p` call)

Resolves the former OQ-001. Two things were under-specified: what goes into each session's
prompt, and what permission posture it runs with.

**Prompt structure.** For each sub-goal the orchestrator feeds, in order, the *content* (not
just paths) of: (1) `POINTER_PROMPT.md`, (2) the sub-goal's goal file `goals/NN-*.md`, (3) the
previous `HANDOFF.md` if present. Injecting the goal-file content (not a path hint) is what
actually eliminates re-discovery, and is why a fresh run with no handoff still works (the goal
file carries the contract). The HANDOFF's `goal file: goals/NN-*.md` line is a human pointer;
the orchestrator injects the file's body.

**Permission posture.** Default: `--dangerously-skip-permissions` (Han, 2026-06-29). An
unattended sub-goal session must edit, commit, push, and open a PR, so it needs full tool
access; a prompt-per-action permission wall would stall the loop. This is a deliberate
blast-radius choice for the auto chain, mitigated by the gate-stop (shared-repo merges stay
human) and by each sub-goal being a disposable session. The posture is **overridable** via the
`CLAUDE_FLAGS` env var (e.g. a tight `--allowedTools` allowlist) or by running the session
inside an agentkernel sandbox via `CLAUDE_CMD`; these are options, not the default.

### Mechanism C: distilled subagent returns (within-sub-goal; phase 2)

Bounds growth INSIDE one sub-goal. Each kit-dispatched role returns a bounded structured
summary (`verdict`, `key findings`, `artifacts`, `read-next`), not the full diff / log; the
full output stays recoverable in the subagent transcript. The lead absorbs the summary and
pulls detail on demand. Applies to worker, task-verifier, integration-checker, reviewer /
review-team, research-*. This is additive to A+B and is built as a follow-up increment.

### Where it lives

- Orchestrator (A) + handoff (B): a new `lib/orchestrate.sh` (bash, matching the other lib
  drivers) plus the handoff convention documented in `WORKFLOW.md` / `plan-for-mega-goal`.
- Distilled returns (C): the dispatched-role agent definitions (`agents/*.md`) + the dispatch
  prose in `/kit:execute`.

## Acceptance criteria

Phase 1 (SG-04, this cycle):
- AC1: `lib/orchestrate.sh` parses a mega-goal ROADMAP, finds the next unchecked sub-goal +
  its policy, and (real mode) runs it via a fresh `claude -p` session; the loop driver holds
  no LLM context.
- AC2: `--dry-run` prints the ordered plan (each sub-goal, its policy, the injected handoff,
  the stop point) without invoking `claude`, so the control flow is testable and cheap.
- AC3: The orchestrator stops at the first `gate` sub-goal and prints the held PR; it advances
  past an `auto` sub-goal only when the ROADMAP checkbox flipped to `[x]`.
- AC4: The previous sub-goal's `HANDOFF.md` AND the goal-file content are injected into the
  next session's prompt; a fresh run with no handoff still works (the goal file carries the
  contract).
- AC5: A `tests/test-orchestrate.sh` exercises the above with a mock `claude` (via `CLAUDE_CMD`),
  including a negative control (a session that does not check its box halts the loop) and a
  check that the default permission posture (`--dangerously-skip-permissions` via `CLAUDE_FLAGS`)
  is passed and is overridable.

Phase 2 (follow-up): the distilled-return contract (Mechanism C) in the agent defs, measured by
a before / after `token-forensic --loops` comparison of an equivalent run (lower `cache_read`/turn
and lower total, the mega-goal success metric).

## Verification

```
# in the dwarves-kit checkout
bash tests/test-orchestrate.sh            # phase-1 control flow + negative control
bash lib/orchestrate.sh run <megagoal-dir> --dry-run   # ordered plan, no claude spawned
```

## Out of scope

- Replacing the interactive `/goal` loop; the orchestrator is an additive outer driver, the
  in-session loop still works for hands-on runs.
- A full Agent-SDK orchestrator (TypeScript/Python). Bash `claude -p` is phase 1; the SDK is
  the upgrade path when structured handoffs / retries / inline distilled returns are wanted.
- Self-clearing inside a session (rejected; kills the loop's own context).

## Decision log

- DEC-001: Distill returns rather than route subagent output to a side file the lead re-reads.
  The cheapest token is the one never absorbed.
- DEC-002 (superseded by DEC-004): v1 made the checkpoint an operator signal. Replaced: a
  human-performed clear defeats the automation premise.
- DEC-003: Full subagent output stays recoverable in the transcript, not discarded.
- DEC-004: The loop driver MUST be non-LLM. An LLM orchestrator spawning a subagent per
  sub-goal re-accumulates every return and becomes the new marathon; only a dumb driver
  running disposable fresh sessions removes the growth.
- DEC-005: Gate sub-goals halt the orchestrator. The auto chain runs unattended; shared-repo
  merges are an intentional human gate, not a flaw.
- DEC-006: The handoff is feed-forward and grounded, distinct from the static POINTER_PROMPT;
  it must cite real artifacts and the receiver verifies before trusting.

## Open questions

- OQ-001: RESOLVED , see "Session invocation": default `--dangerously-skip-permissions`,
  overridable via `CLAUDE_FLAGS`; prompt = POINTER + goal-file content + HANDOFF.
- OQ-002: Exact distilled-return field set + length bound per role (phase 2).
