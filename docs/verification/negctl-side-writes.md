# Verification -- negctl-side-writes

`lib/gate/negctl.sh` recomputes its restore set live inside `restore()` instead of freezing it
right after `mutate_cmd`, so a tracked file the RED run itself writes gets restored (when it
exists at `HEAD`) instead of tripping a spurious "tree differs" FAIL, and a green retry attempt's
own leftover write can no longer mask a vacuous mutation as `Verdict: PASS`.

| Check | Command | Result |
|---|---|---|
| Suite green | `bash tests/test-proof-negctl.sh` | `test-proof-negctl: all 27 passed` |
| Suite green under bash 3.2 | `/bin/bash tests/test-proof-negctl.sh` | `test-proof-negctl: all 27 passed` (macOS's stock `/bin/bash`, GNU bash 3.2.57) |
| Tree stays clean | `git status --porcelain` after each run above | empty |
| Full changed suite | `bash tests/run-all.sh --changed` | `run-all: all 16 suites passed, 0 skipped for missing tooling` |
| negctl on its own suite | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-proof-negctl.sh" "<mutate the retry guard away>"` | `Verdict: PASS` |
| Test-plan coverage | see below | 6/6 spec cases covered, plus their 4 per-mechanism negative controls |

## Bug demonstrated (red, before the fix)

The exact shape `#784`/SPEC-324 hit and routed around
(`docs/implementation-notes/pitch-test-tmp-out.md`, lines ~20-29): a `test-cmd` that overwrites a
tracked fixture only while RED. Reproduced here against the actual pre-fix script (`git show
<fix-commit>^:lib/gate/negctl.sh`), same scratch-repo shape `tests/test-proof-negctl.sh` case
[19] now uses:

```
$ bash /tmp/negctl-prefix.sh "$TMP" "bash test-sidewrite.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak"
## Negative control (negctl)
Command: bash test-sidewrite.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak
Changed: lib.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib.sh
Delta: 
Delta:  M fixture.md
Exit: 0 (green after restore)
Verdict: FAIL: tree differs from the pre-run snapshot after restore (untracked leftovers or a file git cannot restore)
RC=1
$ git status --porcelain
 M fixture.md
```
A genuine control (the mutation went RED, exactly as required, which alone should have earned
`Verdict: PASS`) reported FAIL instead, because `fixture.md` was written by `test-sidewrite.sh`
itself after the restore set was already frozen, leaving the tree dirty (`fixture.md` still `M`).

## Green run (after the fix)

```
[19] T4a: a tracked fixture overwritten only while RED restores cleanly (side effect)
  ok: side-effect fixture restored, Side effect: line printed, tree clean
```
Same scenario, same mutation, now `Verdict: PASS` with a `Side effect: fixture.md` line naming
what else was restored.

## Two validator-round criticals, each independently proven closed

**Critical 1 -- a naive superset restore aborts entirely on one HEAD-absent path.** The first
pass at this fix simply replaced `restore_files` with a fresh superset and restored it in one
batched call. A validator probe (a red run that `git add`s a brand-new tracked file) proved that
call aborts the instant one path doesn't resolve at `HEAD`, restoring *nothing* -- worse than
today's narrower-but-working restore, since the mutation stays applied. Reproduced by hand here
against a real `git mv`, independent of the test suite:

```
$ git mv lib.sh lib2.sh   # staged rename as the mutation
$ git diff HEAD --name-only            # WITHOUT --no-renames
lib2.sh                                # lib.sh's deletion is hidden
$ git diff HEAD --no-renames --name-only
lib.sh
lib2.sh                                # both halves now visible -- --no-renames confirmed working
```
`lib2.sh` has no `HEAD` blob (it is the rename's destination), so restoring it via
`git checkout HEAD --` is inherently impossible -- this is T4b's exact shape, and the fix
partitions it out (fails by name, leaves it in place) instead of letting it abort the whole
restore call. `tests/test-proof-negctl.sh` cases [21]/[22] cover this directly: [21] proves the
fix restores `lib.sh` (MUTATE_SET) while failing `new-file.txt` by name; [22] reconstructs the
pre-fix naive single-call restore (`mk_naive_negctl`, anchored on the `restore() {` /
`trap restore EXIT` boundaries) and proves it leaves `lib.sh` un-restored, reproducing the exact
regression the partition prevents.

**Critical 2 -- a widened restore can mask a vacuous mutation under `NEGCTL_RED_ATTEMPTS>1`.** A
green, non-final retry attempt that itself writes a tracked file can make the *next* attempt come
back red purely because of that leftover, not because the mutation did anything -- defeating the
header's own "a genuinely vacuous mutation stays green on every attempt and still FAILs" promise.
Cases [23]/[24]: [23] proves the fix stops retrying and fails by name the moment a green attempt
leaves tracked dirt; [24] disables that guard and proves the same vacuous mutation (a bare
comment appended to `lib.sh`, no behavioral effect at all) now wrongly reports `Verdict: PASS`.

## Test plan coverage (SPEC-327)

| Case | Verified |
|---|---|
| T4a: side-effect write during RED restores cleanly | [19] `Verdict: PASS`, `Side effect: fixture.md`, tree clean |
| T4a negative control | [20]: disabling the side-effect restore reverts to `tree differs` FAIL |
| T4b: HEAD-absent side effect fails by name, MUTATE_SET still restores | [21] `Verdict: FAIL` naming `new-file.txt`; `lib.sh` restored |
| T4b negative control | [22]: the naive single-call restore aborts; `lib.sh` stays mutated |
| T4c: a green retry attempt's side write stops further retries | [23] `Verdict: FAIL: attempt 1 of 3 ... retries are unsafe against a polluted tree` |
| T4c negative control | [24]: without the guard, the same vacuous mutation wrongly reports `Verdict: PASS` |
| T4d: baseline side write excluded from `Changed`, exact wording pinned | [25] `Changed: <no tracked file>` (not the baseline file), `Baseline side write: fixture.md` |
| T4d negative control | [26]: without the `BASELINE_DIFF` subtraction, `Changed: fixture.md` is wrongly printed |
| No regression | [1]-[18], the full pre-existing suite, pass unmodified (byte-identical output where nothing new fires) |
| `--no-renames` visibility | manual `git mv` demonstration above: both halves of a staged rename now appear in `Changed:` |

## Not proven / not covered

- A brand-new tracked path that lands **inside MUTATE_SET itself** (the `git mv` demonstration
  above, or a baseline-run write that stages a new file) still hits the pre-existing
  whole-call-abort class on MUTATE_SET's own restore call, which this spec deliberately left
  unfiltered ("restore CAPTURE 1 exactly as today," per the validator round). Confirmed this
  predates the fix (reproduced identically against the pre-fix capture, independent of
  `--no-renames`) and is out of scope here; see the spec's Not covered section.
- The retry guard's path-only comparison (a rewrite of an already-MUTATE_SET path, or any write
  to a gitignored file) is not exercised by a dedicated test; named under Not covered in the
  spec as a narrower instance of a visibility limit the whole script has always had.
