# Proof of done: the backlog watcher + self-answer grill mode (ID-457 pilot, SPEC-217)

2026-07-31. Acceptance: an operator-tagged `#auto` queued row reaches the shipped queue's
TSV contract and nothing else does; every question an unattended grill answers for itself
lands on the debt ledger. Lane: full. Spec: `docs/specs/SPEC-217-self-grill-watcher.md`.

## Green run

Command: `bash bin/queue watch` (the real `_meta/BACKLOG.md` of this repo, dry-run default)
Exit: 0
Output: `[watch] 0 rows to enqueue (0 skipped).`
Verdict: PASS. This is the honest current state AND the estate-level negative control: no
row on the real board carries `#auto` yet, so the loop is armed by nobody. Tagging a row is
an operator decision this PR deliberately does not make.

Command: `bash lib/queue/watch-board.sh --repo-root <copy of the real board with ID-457 armed> --repo-name dwarves-kit --journal <temp>`
Exit: 0
Output:
```
[watch] ID-457 -> _meta/megagoals/pilot/POINTER_PROMPT.md (slug dwarves-kit__ID-457)
[watch] plan written to ~/.local/state/dwarves-kit/logs/watch-board-plans/plan.YCkgmx
[watch] 1 row(s) to enqueue, 0 skipped. Dry-run: re-run with --apply (cap --max 1).
```
Verdict: PASS. The positive case runs against the REAL board's bytes and row shape, with one
row armed on a COPY, so the real board is never mutated and no row is armed in git.

Command: `bash tests/test-self-grill-watcher.sh`
Exit: 0
Output: `=== 38/38 passed, 0 failed ===`
Verdict: PASS. Covers the happy path, all five skip classes, the three dedup rules, the
mock-seam assertions (dry-run never invokes the queue; `--apply` passes the plan file and the
budget cap), and the grep-checked mechanical half of the self-answer contract.

Command: `bats tests/test-queue.bats` (regression on the shipped queue, whose
`_pointer_allowlist_reason` this branch repaired)
Exit: 0
Output: 14/14 ok, including `T5 from-boards-pointer-allowlist` and `T7 from-boards-symlink-escape`
Verdict: PASS

Command: `bash tests/test-meta.sh` then `bash tests/test-docs-wiring.sh`
Exit: 0, 0
Output: `Passed: 732 / 732`; `=== 22/22 passed ===`
Verdict: PASS. Pre-existing failures elsewhere (`tests/test-bin-forwarders.sh` bin census,
`tests/test-kit-contract.sh` lib/bench gaps) are unchanged by this branch and touch no file
in this diff.

## NEGATIVE CONTROL (revert -> RED -> restore)

Two controls, one per load-bearing behavior.

### A. The marker filter is what selects rows

Command: replace `_has_auto "$line" || continue` with a no-op, then re-run the suite
Exit: 1
Output: `=== 32/38 passed, 6 failed ===`; the untagged rows now reach the plan:
```
FAIL check3: ID-003 (pointer, no marker) not planned
FAIL check5: ID-005 (#automation lookalike) not planned
FAIL check15b: zero-#auto board plans nothing (got: [watch] ID-101 -> ...)
FAIL check15d: an empty plan never invokes the queue, even with --apply (expected '0', got '1')
```
Verdict: RED as intended. Without the marker, a board with zero `#auto` rows would enqueue
work and open a window. That is exactly the failure the guardrail exists to prevent.

Command: `git checkout -- lib/queue/watch-board.sh` then re-run
Exit: 0
Output: `=== 38/38 passed, 0 failed ===`
Verdict: restored GREEN.

### B. The borrowed realpath pass is what stops a symlink escape

Command: replace `hard="$(_pointer_allowlist_reason "$repo" "$pointer")"` with `hard=""`,
then re-run the suite
Exit: 1
Output: `=== 36/38 passed, 2 failed ===`
```
FAIL check18b: the watcher REFUSES the symlink-escape pointer (got: [watch] ID-007 -> _meta/megagoals/pilot/SNEAK.md ...)
FAIL check18c: the symlink row never reaches the plan
```
Verdict: RED as intended, and it proves the check is load-bearing rather than decorative:
check18's own precondition asserts parse-board's lexical containment ACCEPTS that same
symlinked pointer. Without the borrowed pass, a symlink planted inside an allow-listed
directory but pointing outside the repo would be read into an unattended session's prompt.

Command: `git checkout -- lib/queue/watch-board.sh` then re-run
Exit: 0
Output: `=== 38/38 passed, 0 failed ===`
Verdict: restored GREEN.

## Reproduce

```
cd <repo>
bash bin/queue watch                     # dry-run over the real board
bash tests/test-self-grill-watcher.sh    # the full suite, including both controls' targets
bats tests/test-queue.bats               # the shipped queue, unregressed
```

## What is NOT proven here

Self-answer mode's model behavior. It is prose in `commands/grill.md`, so a test could only
assert the prose, which is what the `## Test plan` tier declares and what the suite's
Section B actually does (mode present, marker present, ledger verb present, reconciliation
present). The behavioral proof is the first real `#auto` row draining end to end, which is
the pilot follow-up: no row is tagged today, on purpose.
