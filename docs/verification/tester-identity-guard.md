# Verification log: fixture-dir guard before the tester git identity

Branch `fix/test-git-identity-guard`, base 0853226 (origin/master).

| Item | Detail |
|---|---|
| Incident | 2026-09-13: a shared checkout's `.git/config` carried `user.name=tester` / `user.email=t@t.dev`; three commits landed under that identity before a worker noticed and rewrote them |
| Root cause | Four tests run `git -C "$d" config user.email t@t.dev; git -C "$d" config user.name tester` right after `git -C "$d" init`, inside a `mkrepo()` that does `local d="$1"` with no check that `$1` is non-empty; a failed `mktemp -d` or an unset var under a subshell leaves `$d` empty, and `git -C ""` targets the caller's cwd, the real repo |
| Fix | One line in each of the four `mkrepo()` helpers, between `init` and the identity `config` pair: `[ -n "$d" ] && [ -d "$d" ] \|\| { echo "fixture dir missing" >&2; exit 1; }` |
| Files | `tests/test-cheap-guards.sh:76`, `tests/test-queue.bats:41`, `tests/test-runaway-guards.sh:87`, `tests/test-notes-sanitization.sh:165` |
| Board row | ID-873 (this branch) |

## Green run

Command: `bash tests/test-cheap-guards.sh`
Exit: 0
Output (excerpt): `=== 23/23 passed, 0 failed ===`

Command: `bats tests/test-queue.bats`
Exit: 0
Output (excerpt): `1..24` ... `ok 24 W5 wait bad-slug and missing-slug -> exit 64`, 0 `not ok` lines

Command: `bash tests/test-runaway-guards.sh`
Exit: 0
Output (excerpt): `=== 44/44 passed, 0 failed ===`

Command: `bash tests/test-notes-sanitization.sh`
Exit: 0
Output (excerpt): `=== 52/52 passed, 0 failed ===`

Command: `bash tests/test-meta.sh`
Exit: 0
Output (excerpt): `Passed: 852 / 852` / `All meta tests passed.`

Verdict: PASS (all five green, no regression from the added guard line).

## Negative control

Mutation: a scratch copy of `tests/test-cheap-guards.sh` with `mkrepo()`'s `local d="$1"`
forced to `local d=""`, simulating a failed `mktemp -d` / an unset caller var. Run from an
isolated non-repo tmp cwd (never the real checkout), with the real repo's local git identity
snapshotted before and after.

Command: `bash <scratch-copy-of-test-cheap-guards.sh>` (run with cwd = a throwaway `mktemp -d`
outside any git repo)
Exit: 1
Output (excerpt):
```
mkdir: : No such file or directory
fixture dir missing
```
Real repo's `git config --local user.email` before: empty. After: still empty (unchanged).

Verdict: RED-as-expected (guard fires, script exits 1 before the identity `config` pair ever
runs), and the real repo's identity is provably untouched.

## Deliberately not done

`git -C "$d" init` itself still runs before the guard (it lands on line before the check, per
the incident's exact culprit being the `config` pair, not `init`); on an existing repo `git
init` is idempotent and does not touch identity or history, so this is not the vector the
incident hit. The guard is placed to block the specific damage (identity clobber), not to make
`mkrepo()` fully side-effect-free under an empty `$d`.

No shared `fixture_repo()` helper was introduced; the four `mkrepo()` copies stay independent
per the task's "smallest guard" instruction. A future dedup (one shared helper sourced by all
four files) is the natural follow-up if a fifth test grows the same shape.
