# Proof of done: docs-wiring for kit-run-integrity (01-05) + a no-orphan check (SPEC-135)

Sub-goals 01-05 of the `kit-run-integrity` mega-goal (gate-outcome emit, wavefront
spec-reservation, advisory coverage-delta, advisory mutation-smoke, generated proof-table,
plus the SPEC-133 reconcile and SPEC-134 security hardening) were merged to master with
**zero mentions** in `AGENTS.md` or `WORKFLOW.md` -- verified by grep against the merged
tree at `a9a2e55` before this branch made any edit. This sub-goal (06, the final, HELD
sub-goal) is docs-only: it reflects the FINAL merged state in the docs an agent would
actually read, distinguishes each surface's real enforcement level instead of certifying
everything "wired" on the weakest reading (the TIER-4 advisor's explicit ask), and adds one
new read-only no-orphan check proving each surface has a live call site.

## Acceptance criteria -> confirmation

| # | Acceptance criterion | Test | Result |
|---|---|---|---|
| 1 | AGENTS.md + WORKFLOW.md mention all of 01/02/03/04/05 | `test-kri-wiring.sh` doc-presence block | PASS |
| 2 | WORKFLOW.md states plainly which are hook-enforced vs prose-invoked-optional vs operator-invocable, and names coverage-delta a heuristic | `test-kri-wiring.sh` doc-presence block | PASS |
| 3 | ADR-0024 names OUTCOME and MUTATION as additive marker types | `test-kri-wiring.sh` doc-presence block | PASS |
| 4 | docs/verification/README.md states the OUTCOME column is ship-boundary-only today | `test-kri-wiring.sh` doc-presence block | PASS |
| 5 | Every one of 01/02/03/04/133/134's live call sites is found by a fixed-string grep against the real source file | `test-kri-wiring.sh` no-orphan-sweep block | PASS (11/11 call sites) |
| 6 | The sweep is not a rubber stamp: a planted over-claim is caught | `test-kri-wiring.sh` AC-NEG block | PASS |
| 7 | No regression | `test-docs-wiring.sh` + `test-meta.sh` | PASS (22/22, 667/667) |
| 8 | HELD for Han: PR opened, not merged | `gh pr view` | PASS (see PR body / HELD note) |

## Confirmation run-table

| Run | Command | Exit | Verdict |
|---|---|---|---|
| new check, green | `bash tests/test-kri-wiring.sh` | 0 | PASS (31/31 assertions) |
| negative control | `WORKFLOW.md` "Advisory measurement gates" section temporarily reverted (section deleted in a throwaway copy) | 1 | RED-as-expected: 6 doc-presence assertions fail (SPEC-130/131/132 mentions, the section header, PROSE-INVOKED, HEURISTIC) |
| restore | original `WORKFLOW.md` restored, re-run | 0 | PASS (31/31, back to green) |
| cross-platform | `/bin/bash tests/test-kri-wiring.sh` (bash 3.2.57, macOS system bash) | 0 | PASS (31/31) |
| no-regression: docs-wiring sibling | `bash tests/test-docs-wiring.sh` | 0 | PASS (22/22, ADR-0032 sweep unaffected) |
| no-regression: meta suite | `bash tests/test-meta.sh` | 0 | PASS (667/667) |
| doc-verifier | `kit:doc-verifier` dispatched against the diff | -- | PASS, see Run detail |

## Run detail

### New check, green (31/31)

```
Command: bash tests/test-kri-wiring.sh
Exit: 0
Verdict: kit-run-integrity no-orphan wiring check green.
=== 31/31 passed ===
```
Covers: doc-presence for all five surfaces in AGENTS.md + WORKFLOW.md, the honest
enforcement-level vocabulary (HOOK-ENFORCED / PROSE-INVOKED / HEURISTIC / "Han's call"),
ADR-0024's additive-marker addendum, docs/verification/README.md's ship-boundary-only
honesty note, 11 live-call-site greps (01 x3, 02 x3, 03 x1, 04 x1, 133 x1, 134 x2), and the
load-bearing negative control.

### Negative control (delete the Advisory measurement gates section -> RED -> restore)

To prove the sweep is load-bearing, not decorative, `WORKFLOW.md`'s new "## Advisory
measurement gates" section (03/04's home, lines 433-455) was excised in an isolated scratch
copy (pure-Python slice, no shell `cp` involved -- this shell aliases `cp -i`, which
otherwise hangs on an overwrite prompt), swapped in for the real file, and the check
re-run against it:

```
Command: bash tests/test-kri-wiring.sh   (WORKFLOW.md with the new section deleted)
Exit: 1
=== 25/31 passed ===
```
Six assertions FAIL, exactly the ones scoped to that section: `WORKFLOW.md mentions
coverage-delta (03, SPEC-130)`, `WORKFLOW.md mentions mutation-smoke (04, SPEC-131)`,
`WORKFLOW.md has an Advisory measurement gates section`, `WORKFLOW.md names 03/04
PROSE-INVOKED (not hook-enforced)`, `WORKFLOW.md names coverage-delta a heuristic`,
`WORKFLOW.md names advisory->block promotion as Han's call, not taken`. The other 25
assertions (01/02/05's mentions live elsewhere in the file, the full no-orphan sweep, and
the AC-NEG block itself) stay green, confirming the failures are scoped precisely to the
deleted content, not a global break. The real file was then restored byte-for-byte
(verified via `git diff --stat WORKFLOW.md` producing no output) and the suite re-run,
returning to 31/31 green -- confirming the doc-presence assertions are genuinely reading
the file, not passing unconditionally.

### The load-bearing AC-NEG (built into every run, not a one-off manual step)

```
PLANTED_CLAIM: "coverage-delta and mutation-smoke are hook-enforced push blockers"
FALSE_COROLLARY checked: "03/04 are hook-enforced push blockers"
Precondition: WORKFLOW.md does NOT contain the false corollary (confirmed absent) -> PASS
Sweep verdict on the false corollary: orphan (not found) -> the sweep correctly reports
  the planted over-claim is NOT substantiated by the docs -> PASS
```

### No-orphan sweep detail (11 live call sites)

| Surface | Corpus file | Fixed string matched |
|---|---|---|
| 01 start | `hooks/ship-gate.sh` | `outcome "$SLUG" ship start` |
| 01 end (caught) | `hooks/ship-gate.sh` | `outcome "$SLUG" ship end caught=true` / `caught=false` |
| 02 dispatch call | `lib/queue/orchestrate.sh` | `_wave_reserve_spec` + `reserved_spec="$(_wave_reserve_spec)"` |
| 02 implementation | `lib/spec/spec-next.sh` | `reserve) reserve ;;` |
| 03 invocation | `commands/review-team.md` | `bash lib/gate/coverage-delta.sh check` |
| 04 invocation | `commands/verify.md` | `bash lib/gate/mutation-smoke.sh run` |
| 133 reconcile | `lib/gate/proof-table-gen.py` | `elif marker == "OUTCOME" and len(parts) >= 4:` |
| 134 confinement | `lib/gate/proof-table-gen.py` | `runs_root = os.path.realpath(...)` + the `resolved_out != runs_root` guard |

### Cross-platform

```
Command: /bin/bash tests/test-kri-wiring.sh
Exit: 0
Verdict: 31/31 passed (macOS system bash 3.2.57; no bashisms beyond the kit's existing
portable-shell contract -- no `set -e`, no associative arrays, no `[[ ]]`-only syntax
outside guarded blocks).
```

### No-regression

```
Command: bash tests/test-docs-wiring.sh
Exit: 0
Verdict: 22/22 passed (the ADR-0032 mega-goal-delegate no-orphan sweep, unaffected by
this branch's edits to a different section of the same files).

Command: bash tests/test-meta.sh
Exit: 0
Verdict: 667/667 passed.
```

### Doc-verifier (kit:doc-verifier, dispatched against this branch's diff)

Dispatched read-only against `git diff a9a2e55..HEAD` to independently confirm every claim
added to `AGENTS.md`/`WORKFLOW.md` matches the real code (function names, file paths, hook
points, exit-code/enforcement claims), and to spot-check `tests/test-kri-wiring.sh`'s
grep assertions against the real corpus files.

```
VERDICT: PASS
Claims checked: 22 (AGENTS.md/WORKFLOW.md/ADR-0024/docs/verification/README.md claims re:
5 surfaces, enforcement levels, function/file names, hook points, test-kri-wiring.sh
assertions)
Contradictions: 0
```
Independently confirmed against live source: `lib/gate/gate-ledger.sh`'s `outcome()` is an
additive marker ignored by `check()`/`override()`/`descent()`, emitted only from
`hooks/ship-gate.sh` with `caught=true` on block / `caught=false` on clean pass -- matches
the "HOOK-ENFORCED, ship-boundary-only" claim exactly. `lib/gate/coverage-delta.sh` and
`lib/gate/mutation-smoke.sh` both hard-comment "ADVISORY BY CONTRACT", always exit 0, with their
only call sites inside `commands/review-team.md` and `commands/verify.md` Step 6b --
matches "PROSE-INVOKED-ONLY" exactly. `lib/queue/orchestrate.sh`'s `_wave_reserve_spec` calls
`spec-next.sh reserve` and injects the reserved number into the dispatch prompt -- matches
the SPEC-128 claim. `lib/gate/proof-table-gen.sh`/`.py` have no automatic caller anywhere except
tests/docs -- matches "operator/skill-invocable, no automatic caller". Independently ran
`bash tests/test-kri-wiring.sh` (31/31) and spot-checked several fixed-string greps directly
against source -- all matched.

## Rollback

Docs-only + one new read-only test file; revert is `git revert` on the two commits
(`961d91a` docs, `48cfc1e` test+CI). No state, no migration, nothing to roll back beyond
the file diff itself.

## Reproduce

```
git clone git@github.com:dwarvesf/dwarves-kit.git
cd dwarves-kit && git checkout feat/kri-06-docs-wiring
bash tests/test-kri-wiring.sh
bash tests/test-docs-wiring.sh
bash tests/test-meta.sh
```
