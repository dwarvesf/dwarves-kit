# Implementation notes: SPEC-094 lane mid-flight escalation (kit-hardening SG-06)

Delta from SPEC-094 / ADR-0028 refinement point 4.

## 2026-07-02 Boundary hook lives in `commands/execute.md` Prerequisites, not `commands/spec.md`

Context: the spec named two candidate wiring points ("`commands/execute.md` near the
start, or `commands/spec.md` at its end -- pick the point where the SPEC is VALIDATED
and build is about to start").
Decision: wired into `commands/execute.md` Prerequisites (`commands/execute.md:16-49`),
immediately after the existing spec-status check ("verify: spec exists and has status
APPROVED or VALIDATED") and before Step 1 dispatches any task.
Why: `commands/spec.md`'s own terminus (`### Step 4: Present for review`) only sets
`Status: APPROVED` and hands off to a human for approval -- there is no guarantee
`/kit:execute` runs in the same session, or even the same day, as `/kit:spec`. The
re-check needs to run at the point build ACTUALLY starts, which is `/kit:execute`'s own
entry gate, not `/kit:spec`'s exit. This also means the re-check re-fires every time
`/kit:execute` is invoked against a spec (e.g. resumed after an interruption), which is
the more conservative (never-miss) reading of "the first point real scope is concrete".

## 2026-07-02 `escalate` re-classifies the whole spec file's raw text, not a section

Context: the goal contract says "read the spec file, run the same classify_core logic
on its content -- Problem/Decision/Tasks text".
Decision: `escalate` runs `classify_core` over `cat <spec-file>` unfiltered (the whole
file), not an extracted `## Problem`/`## Decision`/`## Tasks` slice.
Why: `classify_core`'s flag-scoring regexes are simple case-insensitive substring
matches (`grep -qE`) with no line-anchoring; a keyword anywhere in the spec (Problem,
Decision, Task Breakdown, Failure modes, an inline code block) already trips the same
flags the SPEC's Problem/Decision/Tasks prose would. Slicing sections would add parsing
surface (heading regex, section boundaries) for zero behavioral gain, and would risk a
false HOLD if the auth/migration language landed in, say, `## Edge Cases` instead of
`## Decision`. Whole-file is simpler and strictly more conservative (catches more, never
less) -- in the spirit of "when in doubt, heavier" that already governs
`classify_core`.

## 2026-07-02 `escalate` is a pure advisory function; the caller does the mutation

Context: SPEC-094 AC1 needs `escalate` to be a deterministic, side-effect-free
classifier callable from tests in isolation (mirrors `classify`/`explain`/`check`,
none of which touch the gate-ledger or any spec file).
Decision: `escalate` only prints `ESCALATE <cur> -> <heavier>` or `HOLD <cur>` and
exits 0. It never calls `gate-ledger.sh`, never edits a spec file's `Lane:` header. All
three re-plan actions (`start --amend`, bump the spec header, `action` log line) are
documented as the CALLER's responsibility in `commands/execute.md`, run only on the
`ESCALATE` branch.
Why: keeps the up-only re-plan auditable at the call site (the orchestrator session
that ran `/kit:execute` is the one that decided to amend), and keeps `escalate` unit-
testable with a bare spec-file fixture and no ledger fixture required for AC1-AC3.

## 2026-07-02 Downgrade guard reused verbatim, not re-implemented

Context: guardrail -- "confirm it still blocks and reuse `lane_rank`, don't weaken it".
Decision: `escalate` calls the exact same `lane_rank()` function `lane_check` (the
`check` verb) already calls; no new rank table, no new comparison logic. The only new
comparator is `sr -gt cr` (strictly heavier) vs. `lane_check`'s `cr -lt sr` (strictly
lighter) -- same inequality, read from the opposite side, because `check` flags an
UNDER-sized human choice while `escalate` looks for an OVER-due bump.
Why: two independent rank tables would be exactly the kind of drift the "reuse, don't
invent a new lane" guardrail exists to prevent; reusing `lane_rank` means a future rank
change (e.g. a new lane tier) updates both `check` and `escalate` from one edit.
