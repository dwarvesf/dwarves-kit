# Proof of done: safety-gate find delete-verb gap

Verdict: PASS

Origin: a live incident, not a hypothetical. On 2026-07-08 a disk-cleanup batch ran
`find <bun-global-root> -mindepth 1 -delete` against `~/.cache/.bun`, a path that reads
like a cache but was the bun global install root. It wiped the `omp` (oh-my-pi) cockpit.
The gate did not fire: it keys each rule on its segment's binary, and that segment's
binary was `find`, not `rm`. Discovered 2026-07-17 when the binary turned up missing.

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | the exact incident command blocks | probe: `find ~/.cache/.bun -mindepth 1 -delete` -> exit 2 | PASS |
| AC2 | `-exec rm` is caught too, not just `-delete` | probe D2 -> exit 2 | PASS |
| AC3 | regenerable artifacts stay deletable (no false positive) | probe D3 `find node_modules ... -delete` -> exit 0 | PASS |
| AC4 | non-delete find is untouched | probes D4 (`-exec gofmt`), D5 (read-only find) -> exit 0 | PASS |
| AC5 | the rm rule is unaffected by the refactor | control `rm -r -f src` -> exit 2 across all 3 control steps | PASS |
| AC6 | fail-closed on a find with no path operand | `targets_all_safe` with zero operands returns non-zero -> block | PASS |
| AC7 | no regression in the suite | `tests/test-hooks.sh` 471/471 | PASS |

## Implementation

- `hooks/safety-gate.sh` -- new `find)` arm: sets a delete flag on `-delete`, or on
  `-exec`/`-execdir`/`-ok`/`-okdir` paired with an `rm` token; collects find's leading
  path operands (the tokens before the first primary) and blocks unless every one is
  allowlisted.
- `hooks/safety-gate.sh` -- extracted the build-artifact allowlist out of the `rm` arm
  into `targets_all_safe()`, so `rm` and `find` share ONE definition of "regenerable".
  The rm arm collapses to a single guarded call; its behavior is unchanged (AC5).
- `tests/test-hooks.sh` -- D1-D5 pinned as permanent regression tests.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-hooks.sh` (before fix) | 1 | 469/471 -- D1 + D2 FAIL (the gap, reproduced) |
| `bash tests/test-hooks.sh` (after fix) | 0 | 471/471 -- all green, no regression |
| `bash -n hooks/safety-gate.sh` | 0 | syntax OK |
| negative control (revert -> RED -> restore) | 0 | incident flips 2 -> 0 -> 2; see below |

## Run detail

Red baseline, before the fix existed (only the two new pins fail, nothing else moves):

```
  FAIL D1: find -delete on a home path blocks (expected exit 2, got 0)
  FAIL D2: find -exec rm blocks (expected exit 2, got 0)
  PASS D3: find -delete on an allowlisted artifact is allowed (exit 0)
  PASS D4: find -exec without rm is allowed (exit 0)
  PASS D5: read-only find is allowed (exit 0)
Passed: 469 / 471
```

Green, after:

```
  PASS D1: find -delete on a home path blocks (exit 2)
  PASS D2: find -exec rm blocks (exit 2)
  PASS D3: find -delete on an allowlisted artifact is allowed (exit 0)
  PASS D4: find -exec without rm is allowed (exit 0)
  PASS D5: read-only find is allowed (exit 0)
Passed: 471 / 471
```

Negative control. The hook file is reverted to its pre-fix blob and the SAME probes
re-run, so the RED is produced by the absence of the fix, not by a changed harness.
The sha is printed each step to prove the file actually changed (a first attempt used
`git stash` on an already-clean file, silently did NOT revert, and produced a false
PASS; the sha line is what caught it and is why it stays in the script):

```
### STEP 1 -- fix in place (HEAD)
  sha: 09e9fc716a81
  incident: find -delete             exit=2 (want 2)
  control: recursive-force rm        exit=2 (want 2)
  control: find on artifact          exit=0 (want 0)
### STEP 2 -- NEGATIVE CONTROL: revert hook to pre-fix (HEAD~1)
  sha: a60f39d4c23d  <- must differ from step 1
  incident: find -delete             exit=0 (want 0)     <-- RED: the gap is real
  control: recursive-force rm        exit=2 (want 2)
  control: find on artifact          exit=0 (want 0)
### STEP 3 -- RESTORE (HEAD)
  sha: 09e9fc716a81  <- must match step 1
  incident: find -delete             exit=2 (want 2)
  control: recursive-force rm        exit=2 (want 2)
  control: find on artifact          exit=0 (want 0)
### tree clean?
(clean)
```

## Reproduce

```bash
cd ~/workspace/<owner>/dwarves-kit
bash tests/test-hooks.sh                 # 471/471

# negative control: pin the payloads in a file, not on the command line, or the
# live gate fires on the harness testing it.
bash docs/verification/find-delete-gate-negctl.sh
```

## Known residual (not closed by this change)

The allowlist still treats a bare relative `.cache` as regenerable, so `rm -rf .cache`
is permitted. Run from `$HOME` that is the same class of mistake this fix addresses,
reached by a different path. Left as-is deliberately: the entry exists for project-local
`.cache` build dirs, and narrowing it is a separate judgment call with its own false-positive
cost. Flagged for the operator rather than silently changed.
