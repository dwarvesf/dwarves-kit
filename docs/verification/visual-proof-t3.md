# Proof of done: visual proof upgrade, T3 (contract + verify capture step)

## What changed

- `lib/gate/proof-gate.sh`: `contract` gains one `visual:` line naming the expected
  artifact, emitted only when `proof.visual` resolves true through
  `kit_config_get` (project `.kit.toml` > operator > kit-root, the same read the
  gate uses). A frozen keyword table maps the task text to a row (ui page, ui
  flow, bot message, tui, report, generated file, else none); the artifact text
  mirrors the DECISION-BRIEF "What each task type owes" table. With the flag off
  the output is byte-identical to master's, proven against the real
  `origin/master` copy of the script below.
- `commands/verify.md`: new Step 7b, "Visual capture", gated on `proof.visual`,
  spelling out the per-lane capture set (tiny: nothing; normal: one capture per
  changed screen or the text output; full: the set the `visual:` line names) and
  routing every image through `bin/proof-asset put`.
- `tests/test-proof-contract-visual.sh`: spec cases 21 and 22 plus two pins, a
  `visual: none` row-miss and the verify.md wiring.

## Green run

```
Command: bash tests/test-proof-contract-visual.sh
Exit: 0
Output:
=== case 21: visual on, a ui task names its artifact ===
PASS visual: line names desktop and 400px screenshots (visual: before + after screenshots, desktop and 400px)
=== extra: visual on, a non-visual task -> visual: none ===
PASS non-visual task gets visual: none
=== case 22: visual off, byte-identical to origin/master ===
PASS project visual=false: contract output identical to master
PASS no .kit.toml at all: contract output identical to master
=== R10: commands/verify.md carries the opt-in capture step ===
PASS verify.md gates the capture step on proof.visual and points at bin/proof-asset put
ALL PASS (5/5)
Verdict: PASS
```

## Negative control

The new test file run inside a detached `git worktree` of `origin/master`
(shared object store, master's `lib/gate/proof-gate.sh` and
`commands/verify.md` on disk), this worktree untouched:

```
Command: git worktree add --detach /tmp/vp-t3-negctl.*/repo origin/master &&
         cp tests/test-proof-contract-visual.sh <repo>/tests/ &&
         bash <repo>/tests/test-proof-contract-visual.sh
Exit: 1
Output:
=== case 21: visual on, a ui task names its artifact ===
FAIL want a visual: line naming desktop and 400px screenshots, got []
=== extra: visual on, a non-visual task -> visual: none ===
FAIL want 'visual: none', got []
=== case 22: visual off, byte-identical to origin/master ===
PASS project visual=false: contract output identical to master
PASS no .kit.toml at all: contract output identical to master
=== R10: commands/verify.md carries the opt-in capture step ===
FAIL verify.md lost the proof.visual-gated capture step
3/5 FAILED
```

Red for the right reason: the three new-behavior checks fail on master while the
two byte-identity pins hold (master compared to master is identical by
construction). The temp worktree was removed after the run.
Result: RED as expected

## Changed-scope suite

```
Command: bash tests/run-all.sh --changed origin/master
Exit: 1
Output:
run-all: --changed against 1b449c06: 6 changed files -> 21 suites (16 named, the rest always-on)
... (19 suites ok, including test-no-scattered-ids, test-hooks, test-proof-captured-output,
     test-proof-contract-visual) ...
test-meta                                      FAIL (rc=1)
      !   FAIL docs/FEATURES.md is fresh (check verb, SPEC-219)
      |   Passed: 901 / 902
run-all: FAILED -> test-meta
run-all: 21 suites run, 0 skipped for missing tooling
```

`test-meta`'s single failure is the `docs/FEATURES.md` freshness pin. The same
check already fails on a clean `origin/master` checkout (the committed file was
generated with a spec file that no longer exists; the `/kit:start` row drifts
+74 vs +73). On this branch the generated projection also gains the references
SPEC-385 and the new test file legitimately add, but `docs/FEATURES.md` is T5's
owned file in the spec's Tasks table: every parallel worker's new test file
drifts it, so it is regenerated once at integration, not per branch. Flagged for
the lead; no edit made here.

## Final green run

```
Command: bash tests/test-proof-contract-visual.sh
Exit: 0
Output:
=== case 21: visual on, a ui task names its artifact ===
PASS visual: line names desktop and 400px screenshots (visual: before + after screenshots, desktop and 400px)
=== extra: visual on, a non-visual task -> visual: none ===
PASS non-visual task gets visual: none
=== case 22: visual off, byte-identical to origin/master ===
PASS project visual=false: contract output identical to master
PASS no .kit.toml at all: contract output identical to master
=== R10: commands/verify.md carries the opt-in capture step ===
PASS verify.md gates the capture step on proof.visual and points at bin/proof-asset put
ALL PASS (5/5)
Verdict: PASS
```
