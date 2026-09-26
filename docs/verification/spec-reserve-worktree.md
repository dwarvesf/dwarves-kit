# Proof of done: `spec-next.sh reserve` keys claims by repository

2026-09-26. Spec: `docs/specs/SPEC-318-spec-reserve-worktree.md`. Lane: full. Files: `lib/spec/spec-next.sh`, `tests/test-spec-reserve.sh`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

Acceptance: every worktree of one repo shares one reservation key, the physical path of the repo's common git dir, so two worktrees reserving at once get different numbers. Two repos with the same folder name keep separate counters. `_scan_numbers` lists `docs/specs` in every git worktree. Legacy folder-name lines parse, never count, and expire at the TTL.

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Unit suite | `bash tests/test-spec-reserve.sh` | 0 | PASS, 65/65 |
| Sibling suites | `bash tests/test-spec-next-pr-scan.sh`, `test-kri-wiring.sh`, `test-multiplexer.sh` | 0 | PASS |
| Changed suites | `bash tests/run-all.sh --changed` | 0 | PASS, 12/12 |
| Negative control | `lib/gate/negctl.sh` (below) | 0 | PASS |
| Real two-worktree run | scratch repo under `$TMPDIR` (below) | 0 | PASS, 042 and 043 |

## Green run

```
Command: bash tests/test-spec-reserve.sh
Exit: 0
Output: PASS T20 the two numbers differ
        PASS T21 repo 2 ignores repo 1's claims despite the shared folder name (006)
        PASS T22 a live legacy line is not counted (006)
        PASS T23 next from worktree a sees worktree b's spec file (010)
        Passed: 65 / 65
        spec-reserve green.
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output: run-all: --changed against 60de8b18: 5 changed files -> 12 suites (7 named, the rest always-on)
        run-all: all 12 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Before the fix the same suite read `Passed: 55 / 65`: T1, T20 (three asserts), T21 (two), T22, T23 (two) failed.

## Negative control

The mutation puts the old key back (`basename "$ROOT"`).

```
## Negative control (negctl)
Command: bash tests/test-spec-reserve.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's|^REPO="$(cd .*|REPO="$(basename "$ROOT")"|' lib/spec/spec-next.sh
Changed: lib/spec/spec-next.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/spec/spec-next.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Recorded run (real git worktrees, scratch ledger)

A scratch repo `$S/scratch` with `SPEC-041-seed.md`, two linked worktrees `alpha` and `beta` under `.claude/worktrees/`, `reserve` from both in parallel. `SPEC_RESERVE_FILE` points at a scratch ledger so the machine ledger stays untouched.

```
--- new code, parallel reserve from alpha and beta
alpha: 042
beta: 043
2026-09-26T13:11:14Z | RESERVE | num=042 repo=/private/var/folders/.../sr-real.woNt/scratch
2026-09-26T13:11:14Z | RESERVE | num=043 repo=/private/var/folders/.../sr-real.woNt/scratch
--- old code (HEAD~1), same setup, fresh ledger
beta: 042
alpha: 042
2026-09-26T13:11:14Z | RESERVE | num=042 repo=beta
2026-09-26T13:11:14Z | RESERVE | num=042 repo=alpha
```

The old code reproduces the observed bug: one number, two worktree-slug keys. The new code writes one key and two numbers.

## Not covered

Two machines drawing numbers for one repo each keep their own ledger; only the open-PR scan links them. Legacy lines already in `spec-reservations.log` (the four `num=315` claims) stop counting at once and expire within 24 hours; a claim whose spec file exists in any worktree still reads as taken through the scan.
