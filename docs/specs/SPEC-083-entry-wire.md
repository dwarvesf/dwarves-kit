# SPEC-083: Session-start board wire (orchestration as the verified entry point)

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery hard-gate)
Type: spec-feature / behavioral (hook) + command-prose
Board: ID-033 (I1, re-scoped 2026-05-23; 2026-06-10 intake item 5 folded in)

## Problem

ID-033's re-scoped intent: drive the kit by stating intent, not by memorizing
slash commands, with the orchestration layer as the kit's VERIFIED entry point.
The docs side landed earlier (README "You drive it by intent", MANUAL "Drive it
by intent (start here)" table, branch docs/kit-as-interface). The wire audit
(this cycle's think gate) walked the five hops from session start to commands:

| Hop | Surface | State |
|---|---|---|
| 1 | SessionStart -> `hooks/context-readiness.sh` stdout injection | BROKEN: board-blind, suggestions speak bare command-catalog ("consider 'think' then 'spec'") |
| 2 | `/kit:start` detector | wired: board + telemetry misfires + goal registry |
| 3 | intent -> `/kit:assign` interpret-and-bridge (RID, board claim) | wired |
| 4 | assign -> lane x type loop -> commands | wired: AGENTS.md task loop steps 0-1 |
| 5 | enforcement: ship-gate boardless advisory (SPEC-069) closes the loop | wired |

Hop 1 is the only zero-action surface the operator ALWAYS sees, and it
contradicts the interface doctrine: it never mentions the board (so queued work
is invisible at session start) and its suggestions name bare commands instead
of intent.

## Decision

Fix hop 1 only; pin the whole wire.

1. **Board awareness in `context-readiness.sh`**: when `_meta/BACKLOG.md`
   exists, count rows whose LEADING status keyword is `queued`, using the same
   `$(NF-1)` second-to-last-cell + leading-keyword parse as `lib/backlog.sh`
   `_rows` (self-contained awk in the hook; ship-gate's direct-grep precedent,
   no lib/ dependency). Emit a `board:<N>q` state token whenever the file
   exists, including `0q` (absence ambiguity is worse than one token).
2. **Intent-first suggestion strings**: every `SUGGEST` branch leads with the
   intent phrasing and parenthesizes the command:
   - no spec, queued > 0: `N queued on the board; state the task, or /kit:assign --next`
   - no spec, no queue: `no spec found; state the task (the kit routes it), or /kit:think then /kit:spec`
   - DRAFT: `spec is DRAFT; say "validate it" (or /kit:spec-validate)`
   - tasks in progress: `tasks in progress; say "continue" (or /kit:execute)`
   - all done, unreviewed: `all tasks done; say "review it" (or /kit:review)`
   - reviewed: `all tasks done and reviewed; say "ship it" (or /kit:ship)`
   - ambiguous spec: unchanged semantics, phrasing kept.
3. **Precedence**: a live spec's cycle suggestion beats the board pull
   (mid-cycle, finishing beats starting); the `board:` token is emitted
   regardless.
4. **Deliberately excluded**: goal-registry read and in-flight counts in the
   hook (`/kit:start` and `--full` cover resume; the SessionStart hook stays
   cheap and low-noise, one line).
5. **Docs**: MANUAL `/kit:start` "Reads" line + the context-readiness hook row
   gain the board mention; no other doc churn (the intent framing already
   exists).

## Acceptance criteria

- AC1: hook emits `board:<N>q` when `_meta/BACKLOG.md` exists (fixture: 2
  queued + 1 claimed -> `board:2q`); no token when no board file.
- AC2: no-spec + queued>0 suggestion carries "state the task" +
  `/kit:assign --next` (fixture).
- AC3: no-spec + no-board suggestion is the intent-first line (fixture).
- AC4: live-spec suggestion takes precedence over the board pull; board token
  still present (fixture).
- AC5: every rewired suggestion string pinned; intent phrase precedes the
  command name in each.
- AC6: MANUAL updated (board in /kit:start Reads + hook row); pins.
- AC7: suites green; NC: revert the board-count block -> fixture pins RED.

## Test plan

| # | Case | Proof | Expected |
|---|---|---|---|
| 1 | board 2q, no spec | temp repo fixture, run hook, grep stdout | `board:2q` + assign --next suggestion |
| 2 | no board, no spec | same fixture minus BACKLOG | no `board:` token; intent-first no-spec line |
| 3 | board + live VALIDATED spec, tasks open | fixture with spec file | cycle suggestion ("continue"), `board:` token present |
| 4 | claimed/prose statuses not counted | fixture row `claimed [..]` + `queued [re-eval ..]` | count = queued-leading only |
| 5 | NC | revert board block | cases 1/4 RED |

## Tasks

- [x] Failing-first fixture pins in tests/test-hooks.sh (temp-repo hook runs)
- [x] context-readiness.sh: board count + intent-first SUGGEST strings
- [x] Meta pins: suggestion strings + MANUAL lines
- [x] MANUAL.md: /kit:start Reads + hook row
- [x] NC measured; suites green

## Verification

- 14 fixture pins failing-first: 11 RED pre-implementation (3 not-contains pins
  trivially green, expected) -> all green post. 6 meta pins.
- NC: board-token emission reverted -> 3 RED (board:2q x2, board:0q) -> restored.
- Suites: hooks 426/426 (x3 consecutive clean runs), meta 479/479, e2e 20/20.
  The pre-existing ID-081 PTY flake fired in 3 mid-cycle suite runs (always the
  same unrelated gate-ledger progress test, never a SPEC-083 pin); 4th sighting
  recorded on the board with capture + hypothesis.

## Review

Date: 2026-06-11. Multi-lens inline (correctness / interface-contract /
robustness), 7/10 pre-fix. MEDIUM: the say-branch meta pin used a digit-class
regex (`^[4-9]`) that false-fails at 10+ branches, the exact hardcoded-count
trap this session's doctrine names; fixed to arithmetic `-ge 4`. LOW
(accepted, recorded): a downstream repo whose BACKLOG rows do not match the
`| ID-NNN |` shape parses to `board:0q`, an honest "no parseable queue" token,
not a wrong count; the hook comment cross-references the lib/backlog.sh twin
parser for the drift risk. Verdict: SHIP.
