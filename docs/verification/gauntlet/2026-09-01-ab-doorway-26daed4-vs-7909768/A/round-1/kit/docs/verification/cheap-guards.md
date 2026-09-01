# Proof of done: two cheap guardrails on the autonomous run queue (ID-461, SPEC-224)

2026-08-01. Acceptance: an unattended run opens a DRAFT PR with a provenance footer by default and
`--ready` opens a normal one; a self-reported per-row tool-call ceiling stops a row with the shared
reason `spend_ceiling`; a queue-wide ceiling aborts remaining rows after the current one ships;
every mechanism has a healthy negative control; SPEC-221's guards are untouched. Lane: full. Spec:
`docs/specs/SPEC-224-cheap-guards.md`.

## Green run

Command: `bash tests/test-cheap-guards.sh`
Exit: 0
Output: `=== 19/19 passed, 0 failed ===`
Verdict: PASS. Four sections (draft default, per-row ceiling, queue-wide ceiling, `_status_num` +
backward compat), each carrying its own negative control, plus the B3 clamp check from the security
review.

Command: `bash tests/test-runaway-guards.sh` (regression: SPEC-221, the guards this sits beside)
Exit: 0
Output: `=== 44/44 passed, 0 failed ===`
Verdict: PASS. The runaway guards are unchanged; the new clauses only APPEND to the typed line.

Command: `bash tests/test-notes-sanitization.sh` (regression: SPEC-223, same typed-line surface)
Exit: 0
Output: `=== 52/52 passed, 0 failed ===`
Verdict: PASS. The sanitizer's typed-line contract is intact.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 746 / 746`
Verdict: PASS. Includes the duplicate-SPEC-number guard and the `docs/FEATURES.md` freshness pin
(the pin went RED first when SPEC-224 added spec-refs to command rows; regenerating drove it GREEN).

Command: `bash tests/test-docs-wiring.sh`
Exit: 0
Output: `=== 22/22 passed ===`
Verdict: PASS.

## Negative controls, one per mechanism

The load-bearing half. Each is the HEALTHY case that must NOT trip its guard.

| Mechanism | Negative control | Asserted result |
|---|---|---|
| Draft default | `--ready` (A2) | the typed `/goal` line carries NO draft clause, a normal PR |
| Per-row ceiling | a run reporting `TOOL_CALLS: 3` under a ceiling of 100 (B2) | reaches `done`, never labelled `spend_ceiling` |
| Queue-wide ceiling | a batch under the total (C2) | every row runs to `done` |
| Backward compat | both ceilings unset, a run reporting `TOOL_CALLS: 9999` (D2) | never trips, and the typed line carries NO `TOOL_CALLS` clause |

## Revert-to-RED (the tests fail when the guard is broken)

Proof the assertions actually bind, not just pass.

| Guard broken | Edit | Result |
|---|---|---|
| Draft default | remove the `[ "$QUEUE_PR_READY" != 1 ]` guard so the clause is unconditional | A2 NC goes RED: `--ready` now types a `--draft` clause. `17/18 passed, 1 failed`. Restored -> GREEN. |
| Per-row ceiling | invert the comparison `-ge` -> `-lt` in `_launch_once` | B1 goes RED: the over-ceiling run no longer trips `spend_ceiling`, it falls through to the wall-clock and journals `malformed_exit_signal` instead. `17/18 passed, 1 failed`. Restored -> GREEN. |
| Clamp (security fix) | disable the 9-digit clamp in `_status_num` | B3 goes RED: a 30-digit self-report errors the `-ge` compare, the ceiling silently disables, and the row journals `malformed_exit_signal` instead of `spend_ceiling`. `18/19 passed, 1 failed`. Restored -> GREEN. |

Captured output (draft-default revert):

```
  FAIL A2 NC: --ready types NO draft clause (the escape hatch) -- got: /goal p  ... When you open a
  pull request, make it a DRAFT (gh pr create --draft) and append this provenance footer ...
=== 17/18 passed, 1 failed ===
  (restored) ->
  PASS A2 NC: --ready types NO draft clause (the escape hatch)
```

Captured output (ceiling-trip revert):

```
  PASS B1: a run over the ceiling stops (stalled)
  FAIL B1: the stop names the shared reason spend_ceiling (expected 'spend_ceiling', got 'malformed_exit_signal')
=== 17/18 passed, 1 failed ===
```

## Reproduce

```
cd <repo>
bash tests/test-cheap-guards.sh          # the feature
bash tests/test-runaway-guards.sh        # SPEC-221 regression
bash tests/test-meta.sh                  # spec-number + FEATURES freshness
```

## Review round

Two fresh-context reviewers ran on the uncommitted diff (this touches the unattended runner and
PR-opening).

- Architecture (`kit:code-reviewer`): SHIP, 9/10. Independently re-verified the claim-lease scope-out
  against the merged `_beat`/reaper code and confirmed the verdict/reason reuse is the right seam.
  Two LOW findings, both explicitly "not worth touching now".
- Security (`kit:security-reviewer`): HAS ISSUES, two MEDIUM + one LOW, all fixed:
  - MEDIUM: an oversized self-reported `TOOL_CALLS` errored the `-ge` compare (disabling the per-row
    ceiling) and overflowed the queue-wide accumulator (spurious batch abort). Fixed by a 9-digit
    clamp at the `_status_num` source, covering both call sites (queue.sh). Test B3 + its
    revert-to-RED prove it.
  - LOW: the provenance footer leaked the full journal path (home dir + username) into the PR body.
    Fixed by footering the basename only.
  - The design question on stall-ladder inheritance was answered in SPEC-224 DEC-006 (per-attempt
    cap, wall-clock semantics; cumulative bound is the queue-wide ceiling), no code change.
  Confirmed clean: typed-line injection (argv-safe `send-keys -l --`, slug `_slug_ok`-validated,
  clauses appended after the SPEC-223 untrusted fence), ceiling-vs-wall-clock composition (a run
  cannot evade both), bash 3.2 compatibility.

## Scope decision recorded here

Claim-leases (the third idea on board row ID-461) were SCOPED OUT. SPEC-221's `<slug>.beat` presence
IS the in-flight claim (queue.sh header + DEC-003) and its reaper is the lazy expiry, so a separate
`claimed_at` lease would be the redundant lock DEC-003 already rejected. Decided from the merged
code, not the survey's guess. Full reasoning: SPEC-224 `## Design` + DEC-001.
