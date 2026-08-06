# SPEC-092: Right-arm review parity

Status: VALIDATED
Date: 2026-07-02
Lane: full (4 new agents + a re-audit lens wired into the execute path + roster/doc sync)
Type: feature
Relates-to: ADR-0028 ("Right-arm review parity", P4's right-arm half; the trust metric "% of
autonomous done-claims that survive a fresh-context re-audit"), ADR-0029 (review-function
naming and form convention, the rename map's SG-06 rows + the 2026-07-02 recheck-verifier
amendment), SPEC-088 (agent-effectiveness gate, SG-01), SPEC-091 (generic advisor, SG-03,
sibling sub-goal), ADR-0005 (read-only verifier pattern), ADR-0024 (advisory-mid /
hard-at-ship), SPEC-087 (distilled return contract)
Board: kit-hardening mega-goal SG-04 (ops-toolkit `_meta/megagoals/kit-hardening`)

## Problem

The V-model's right (TEST) arm has two holes the left arm does not: (a) the Acceptance and
System-test rows in the V-phase inventory have NO agent at all -- `/kit:ship`'s acceptance
gate and the whole-project suite are exercised only implicitly, never by a dedicated
dynamic verifier; (b) `task-verifier` and `integration-verifier` PASSes are never
re-reviewed -- nothing re-audits a done-claim the way the left arm's static reviewers get
reviewed by a second lens. ADR-0028's trust metric ("% of autonomous done-claims that
survive a fresh-context re-audit") has no agent making it real. Plus the brief phase
(`/kit:think`'s `DECISION-BRIEF.md`) has no static reviewer, unlike every other left-arm
artifact (spec, design, code, docs).

## Decision

Add four agents, all meta-agent-shaped, all conforming to ADR-0029, all `model: sonnet`,
all gated by the SG-01 `agent-effectiveness` validator (`tests/test-agent-effectiveness.sh
<path>` gate mode):

- **`brief-reviewer`** (LEFT-arm STATIC, `-reviewer`) -- reads the design brief and judges
  clarity/completeness/testability. The mirror the brief row lacked.
- **`acceptance-verifier`** (RIGHT-arm DYNAMIC, `-verifier`) -- executes the active spec's
  own `## Verification` section end to end, mapping each AC to a passing check. Fills the
  agent-less Acceptance row.
- **`system-verifier`** (RIGHT-arm DYNAMIC, `-verifier`) -- runs the whole unscoped project
  test suite, the right-arm mirror of the design phase. Fills the agent-less System-test
  row.
- **`recheck-verifier`** (RIGHT-arm DYNAMIC, `-verifier`, the one genuinely NEW role) -- a
  fresh-context verifier OF a verifier's PASS. Semantics PINNED (ADR-0029 Amendment,
  2026-07-02, operator): it RE-EXECUTES the prior verifier's recorded verification command
  in a fresh context and re-judges the outcome. It is explicitly NOT a read-back of the
  recorded run-table (a read-back cannot catch stale or fabricated evidence, which is
  exactly what it must catch). Its stance: assume the recorded PASS is fabricated/stale
  until a fresh re-execution reproduces it.

Wire `recheck-verifier` into `commands/execute.md` as a new sub-step after each right-arm
PASS: 2c-1 (after `task-verifier` PASS, per-task) and 2b under Step 4 (after
`integration-verifier` PASS, once per multi-task build). Advisory + recorded, never a
mid-flight hard block (ADR-0024) -- a caught stale/fabricated PASS is surfaced at the next
human checkpoint, it does not reopen a retry loop by itself.

Fill the agent-less rows in `docs/architecture.md`'s V-phase inventory (Acceptance +
System-test rows in the Right arm TEST table; a new Re-audit row for `recheck-verifier`;
a new Brief-review row for `brief-reviewer` in the Static quality gates table) and
`MANUAL.md`'s agent table. Add all 4 names to `tests/test-meta.sh`'s `REVIEW_AGENTS` list
(they already conform to the naming axis, so this is a roster-completeness addition, not a
behavior change to the axis check).

## Acceptance criteria

- AC1: the 4 agent files (`agents/{brief-reviewer,acceptance-verifier,system-verifier,
  recheck-verifier}.md`) exist, conform to ADR-0029 (name on-axis, read-only-or-scoped-Bash
  tools only, no bare `Bash`/`Edit`/`Write`), and each passes
  `bash tests/test-agent-effectiveness.sh agents/<name>.md` (the SG-01 gate).
- AC2: the Acceptance and System-test rows in `docs/architecture.md`'s V-phase inventory
  are non-empty (name `acceptance-verifier` / `system-verifier` respectively).
- AC3: `recheck-verifier`'s prompt carries the re-execution-not-read-back semantics
  explicitly and repeatedly: the vocabulary "re-execute"/"re-run"/"fresh context" is
  present AND an explicit "not a read-back"/"never a read-back of recorded evidence"
  statement is present.
- AC4 [negative control, load-bearing]: a fixture representing a planted-bad PASS (a
  recorded run-table claiming `VERDICT: PASS` whose command, if re-run, actually fails)
  exists under `tests/fixtures/right-arm-parity/`, AND the `recheck-verifier` prompt
  carries the vocabulary needed to catch it (re-execute + "assume fabricated/stale until
  reproduced").
- AC5: `commands/execute.md` wires the recheck-verifier re-audit over a right-arm PASS --
  it names `recheck-verifier` and uses "re-execute"/"fresh" language at both dispatch
  points (after task-verifier PASS, after integration-verifier PASS).
- AC6: `tests/test-meta.sh` stays green with all 4 new names present in `REVIEW_AGENTS`
  and in the live agent roster (the architecture-table-rows == live-file-count check, item
  (d), and the naming-axis check, item (b), both pass with the 4 additions).

## Tasks

- T1: author the 4 agent files (frontmatter + stance + three-verdict output + rules +
  Source line citing ADR-0028/ADR-0029/the mirrored sibling + the SPEC-087 distilled return
  contract block).
- T2: wire the recheck-verifier re-audit lens into `commands/execute.md` (2c-1 after
  task-verifier, 2b under Step 4 after integration-verifier).
- T3: fill the agent-less V-phase inventory rows in `docs/architecture.md` (Acceptance,
  System-test, a new Re-audit row, a new Brief-review row) + fix the stale total-count
  line; add MANUAL.md agent-table rows for all 4.
- T4: add the 4 names to `tests/test-meta.sh`'s `REVIEW_AGENTS` list.
- T5: `tests/test-right-arm-parity.sh` covering AC1-AC5, including the negative-control
  fixture under `tests/fixtures/right-arm-parity/`.

## Verification

```
bash tests/test-right-arm-parity.sh                      # AC1-AC5, incl. negative control
for a in brief-reviewer acceptance-verifier system-verifier recheck-verifier; do
  bash tests/test-agent-effectiveness.sh "agents/$a.md"; done   # SG-01 gate, all 4
bash tests/test-meta.sh                                   # roster + naming-axis stay green
bash tests/test-hooks.sh                                  # unrelated suite stays green
```

Proof-of-done: `docs/verification/right-arm-parity.md` -- one row per new agent (present +
gate-pass), the Acceptance/System rows now non-empty, and the re-audit-catches-planted-bad
negative-control row.

## Review

Integration-branch + gated-final (ADR-0028): targets `mega/kit-hardening`, auto-merges past
its own ship-gate; the single human review runs at the final `-> master` PR.

## Out of Scope

- The generic advisor (SG-03, already shipped as `agents/advisor.md`).
- The left-arm reviewers that already existed (`code-reviewer`, `security-reviewer`,
  `doc-verifier`).
- The agent-effectiveness validator itself (SG-01).
- SPEC-089 dynamic same-run specialist synthesis (a separate token-optim-v3-adjacent
  effort).
- A re-run of the same verifier by the same agent (recheck-verifier must be fresh-context,
  never the original verifier repeating itself).
