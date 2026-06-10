# SPEC-069: Quality follow-ups: boardless detection, review escalation, colors

Status: SHIPPED
Date: 2026-06-10
Lane: normal (classified: normal)
Type: spec-feature / behavioral
Board: ID-058

## Problem

The operator's 5-question retro after the quality wave found:

1. Board-tracking lived as PROSE (AGENTS step 0), and prose rules lose to long-context
   attention decay: a whole wave ran un-boarded until the operator caught it. The kit's
   own doctrine says important things are DETECTED, not remembered.
2. All reviews were single-agent single-lens; the multi-lens machinery (review-team)
   existed but nothing said WHEN it is owed. Two drafts shipped to review with 2 HIGH
   findings each, both in lib/hooks surfaces.
3. The adherence audit found a shipped run with an un-disposed plan phase (spec-064's
   think) that nothing surfaced.
4. codebase-memory exists but intake never points at it for unfamiliar code areas.
5. plan/progress/trace are monochrome; the operator wants the walk visible at a glance.

## Decision

1. **Boardless-run detector** (lane-telemetry): when the cwd repo has `_meta/BACKLOG.md`,
   every run ledger whose `repo=` matches the cwd repo and whose rid is NOT referenced in
   the board file counts as boardless: headline `boardless: N` + a named list in
   `misfires` (the S1 surface). Detection, never a block.
2. **Shipped-incomplete detector** (lane-telemetry): a run with a ship gate whose
   `progress` is not `complete` is listed in `misfires` (the spec-064 think class).
3. **ship-gate advisory line**: after the gates check passes, if the repo board exists
   and the branch slug appears nowhere in it, print one advisory line (never block).
4. **Review escalation rule** (WORKFLOW + AGENTS prose): a run touching `lib/` or
   `hooks/` owes the multi-lens review (`/kit:review-team`), not a single lens; the two
   2-HIGH drafts are the evidence.
5. **grill orientation**: unfamiliar code area -> query codebase-memory before blind grep.
6. **TTY-gated colors** for plan/progress (gate-ledger) and trace flags + report headline
   (lane-telemetry): green disposed, bold-yellow pointer, dim pending, red MISFIRE flags.
   Colors emit ONLY when stdout is a TTY and NO_COLOR is unset, so the 300+ piped test
   pins stay byte-identical.
7. **Retro-patch**: spec-064's think recorded with an honest retro-note (done at intake
   of this run).

## Acceptance criteria

- AC1: a fixture run ledger with repo=X and no board reference -> `boardless: 1` +
  named in misfires; referenced -> 0.
- AC2: a fixture shipped run missing a phase -> listed shipped-incomplete in misfires.
- AC3: piped output of plan/progress/report/trace is byte-identical to pre-change
  (suites prove it by passing unchanged).
- AC4: WORKFLOW/AGENTS carry the escalation rule; grill carries the codebase-memory line;
  ship-gate carries the advisory.

## Test plan

Fixture tests for AC1/AC2 (temp board + temp logs); the existing 300+ piped assertions
ARE the AC3 proof (no-color-when-piped); meta pin for AC4 wiring. Negative control:
reference the rid in the fixture board -> boardless drops to 0.

## Verification

- `tests/test-hooks.sh`: 316/316 (311 + detector tests, false-positive guard, seam pins,
  bidirectional PTY color tests: escape bytes present under a PTY, zero when piped).
- `tests/test-meta.sh`: 426/426; `tests/test-e2e.sh`: 20/20.
- Live: the detectors' first run flagged the real pre-discipline history (spec-061/062/063
  boardless; spec-061/062 shipped-incomplete); PTY render verified (12 escape bytes, bold
  step line, green/yellow/dim marks).

## Review

Date: 2026-06-10. **Multi-lens (3 parallel reviewers), the escalation rule this spec adds,
applied to itself.** Each lens caught a class the others missed, which is the rule's
justification in one run:

- Security 7/10 FIX-FIRST: unquoted grep patterns let a metachar slug silently no-op the
  advisory (S1) + missing `--` (S2). Fixed: `grep -qF --` at all 3 sites + row-anchored
  advisory match (also A5).
- Architecture 6/10 FIX-FIRST: HIGH, `_shipped_incomplete`'s cross-lib call breaks the
  read/write seam -> dispositioned option (c): explicit INTENTIONAL SEAM comment + an
  agreement pin (both sides carry the literal `complete`); MEDIUM, `_boardless` basename
  broke inside `.claude/worktrees/<branch>` -> fixed via `--git-common-dir`; LOW color
  duplication accepted (variable sets differ).
- Test-coverage 7/10 SHIP: color path untested + no false-positive guard -> both added;
  my first PTY test was itself unfalsifiable (always-true assert) and was rewritten
  bidirectional (PTY >= 1 escape byte, piped == 0).

Post-fix: hooks 316/316, meta 426/426, e2e 20/20. Verdict: SHIP.
