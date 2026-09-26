# Verification -- negctl-side-writes

`lib/gate/negctl.sh` recomputes its restore set live inside `restore()` instead of freezing it
right after `mutate_cmd`, so a tracked file the RED run itself writes gets restored (when it
exists at `HEAD`) instead of tripping a spurious "tree differs" FAIL, and a green retry attempt's
own leftover write can no longer mask a vacuous mutation as `Verdict: PASS`. A follow-up critique
round then closed two more gaps in the same mechanism: step 6's own confirmatory run can now no
longer leave the tree dirty on a genuine `PASS`, a SIGINT mid-checkout can no longer abandon the
restore partway through, and MUTATE_SET's own restore no longer aborts whole on a HEAD-absent
path (a `git mv` as the mutation, not only a test-cmd side effect).

| Check | Command | Result |
|---|---|---|
| Suite green | `bash tests/test-proof-negctl.sh` | `test-proof-negctl: all 33 passed`, stable across repeated runs |
| Suite green under bash 3.2 | `/bin/bash tests/test-proof-negctl.sh` | `test-proof-negctl: all 33 passed` (macOS's stock `/bin/bash`, GNU bash 3.2.57), stable across repeated runs |
| Tree stays clean | `git status --porcelain` after each run above | empty |
| Full changed suite | `bash tests/run-all.sh --changed` | all changed suites passed |
| negctl on its own suite | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-proof-negctl.sh" "<mutate the retry guard away>"` | `Verdict: PASS` |
| Test-plan coverage | see below | 6/6 original spec cases plus 5 round-3 fixes, each with its own passing case and its own red negative control |

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

## Round 3: post-ship critique, two more invariant failures closed

A fresh critique+review round probed the shipped round-2 code directly and found two of its own
stated invariants false, plus a real test-coverage gap (a mutation pass proved stripping
`--no-renames` or restoring the old early return both left the round-1/2 suite fully green).

**P1 (HIGH) -- step 6's own green run left the tree dirty even on `Verdict: PASS`.** Reproduced
against the round-2 script (`test-alwayswrite.sh`, which writes a tracked fixture on every call
including the baseline and the final confirmatory check):

```
=== RED (item 1, PASS rc=0 case, round-2 negctl.sh) ===
## Negative control (negctl)
...
Restore: git checkout HEAD -- fixture.md lib.sh
Exit: 0 (green after restore)
Verdict: PASS
RC=0
--- tree after (should show fixture.md dirty despite PASS = BUG) ---
 M fixture.md
```
`Verdict: PASS`, `RC=0`, and the tree was still dirty. Fixed by re-running `restore()`
unconditionally (`restore_done=0; restore >/dev/null`) right after step 6; the same scenario now
ends `git status --porcelain` empty. `tests/test-proof-negctl.sh` case [25] (T4d) exercises the
same mechanism directly: the hand `git checkout -- fixture.md` cleanup that used to mask this
(then at line 298) is gone, so its own `clean "$REPO"` assertion now checks it for real.

**P2 (MEDIUM) -- a SIGINT mid-checkout left `lib.sh` dirty.** `restore_done=1` was set at
`restore()`'s entry, before the checkout ran; a signal landing during the checkout meant no
further attempt would ever run (the guard already read "done"). Reproduced with a slow-git shim
(`checkout` sleeps 2s) and a process-group `kill -INT`, 1.0s after launch, against the round-2
script:

```
=== RED: pre-round3 (no signal-block) ===
## Negative control (negctl)
...
Exit: 1 (under mutation, RED expected)
--- tree state after ---
 M lib.sh
```
The run was killed (rc=130) mid-checkout and `lib.sh` stayed mutated. With `trap '' INT TERM HUP`
as `restore()`'s first line, the identical interrupt now leaves the tree clean and the run
reports `Verdict: PASS` (the ignored signal also propagates to the forked `git`/shim child, so
even the shim's own `sleep` runs to completion). `tests/test-proof-negctl.sh` cases [31]/[32]
carry this permanently, generously margined (2s shim delay, 1.0s signal delay), stable across
repeated runs on both bash 3.2 and default bash.

**Found while dogfooding this very fix: cases [31]/[32] are nesting-unsafe by construction, now
guarded.** Running `bash lib/gate/negctl.sh "$PWD" "bash tests/test-proof-negctl.sh" "<mutate the
retry guard>"` (the "negctl on its own suite" proof) reproduced a real, repeatable failure: step
6's own `test-cmd` run is the entire `test-proof-negctl.sh` suite, and by step 6 the OUTER
negctl's own step-5 `restore()` has already run `trap '' INT TERM HUP` *in the outer process*.
SIGINT/TERM/HUP ignored dispositions are inherited across `fork`/`exec`, and POSIX is explicit
that a non-interactive shell can never un-ignore a signal it inherited as already ignored -- so
the INNER suite's own case [32] (which removes the `trap ''` line from ITS OWN copy under test)
still could not reproduce the bug: the signal was already neutralized three process-generations
up, before the inner mutated copy ever got a chance to matter. Confirmed the mechanism directly:

```
$ bash -c 'trap "" INT TERM HUP; bash -c '"'"'trap "touch marker" INT; kill -INT $$; sleep 0.2'"'"''
$ ls marker 2>/dev/null || echo "marker never created -- SIGINT was inherited-ignored"
marker never created -- SIGINT was inherited-ignored
```
Fixed by detecting this empirically (an inherited ignore does not show in `trap -p`, so it must
be tested, not assumed): before running [31]/[32], a disposable `bash -c` child sets its own
`trap ... INT`, signals itself, and checks whether the trap fired. If not, [31]/[32] are skipped
with a named reason instead of asserting a result a poisoned ambient disposition can no longer
prove either way. Re-ran the exact dogfood scenario twice more after the fix: `Verdict: PASS`
both times, tree clean, and a direct (non-nested) run of the suite still exercises [31]/[32] for
real (confirmed: `ok: checkout survives a SIGINT mid-restore` / `ok: without the trap, the
interrupted checkout leaves lib.sh mutated`, both printed on a direct run).

**P2 (MEDIUM) -- MUTATE_SET's own restore could still abort whole.** Round 2 explicitly scoped
this out as "pre-existing." Closed in round 3 by unifying the partition: MUTATE_SET and the
beyond-set are now walked in one loop, by `git cat-file -e HEAD:<path>`, into one checkout call.
Re-running the exact `git mv` demonstration from round 2 against the round-3 script:

```
$ bash lib/gate/negctl.sh "$TMP" "bash test.sh" "git mv lib.sh lib2.sh"
...
Changed: lib.sh, lib2.sh
Exit: 1 (under mutation, RED expected)
Side effect (unrestorable): lib2.sh
Restore: git checkout HEAD -- lib.sh lib2.sh
Verdict: FAIL: new tracked file(s) with no HEAD blob cannot be restored: lib2.sh; left in place, never auto-removed
$ ls "$TMP"        # lib.sh IS present again
lib.sh  lib2.sh  test.sh
```
`lib.sh` (MUTATE_SET's own file) is restored; only `lib2.sh` (no `HEAD` blob) is named and left
in place. Cases [27]/[28] carry this: [27] is the fixed behavior; [28] strips `--no-renames` and
shows `lib.sh`'s deletion becomes invisible to both `Changed:` and the restore set entirely
(`lib.sh` never comes back -- worse than a named failure).

**Coverage gap -- an empty MUTATE_SET used to skip the side-effect restore.** The old early
return (`[ "${#restore_files[@]}" -gt 0 ] || return 0`) exited before the beyond-set was ever
computed. No case in the round-1/2 suite drove MUTATE_SET to empty while a side effect existed,
so restoring that line kept the suite green. Cases [29]/[30] close it: an inert mutation with
`test-retrywriter.sh` at the default `NEGCTL_RED_ATTEMPTS=1` empties MUTATE_SET while the retry
writer still leaves `fixture.md` dirty; [29] proves the fixed script restores it anyway
(`Side effect: fixture.md`, tree clean); [30] restores the old early-return line and shows
`fixture.md` staying dirty.

**P4 (LOW) -- a bare `Delta: ` line.** An empty `before`/`after` snapshot diffed against a
non-empty one produced a content-free `Delta: ` line ahead of the real one (visible in the P1
reproduction above, historically). The filter now excludes an exactly-empty marker line.

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
| `--no-renames` visibility | [27]/[28]: both halves of a staged rename appear in `Changed:` with the flag, only the new half without it |
| P1: step 6's own write gets swept up | [25] (T4d), with its masking hand-cleanup removed so `clean "$REPO"` checks it for real |
| P2: MUTATE_SET's own HEAD-absent path no longer aborts the whole restore | [27] positive; [22] (T4b's original negative control) still reproduces the pre-unification naive shape |
| P2: SIGINT mid-checkout | [31]/[32], slow-git shim + process-group signal, generously margined, stable under both bashes |
| Coverage gap: empty MUTATE_SET must still run the side-effect restore | [29]/[30], `test-retrywriter.sh` at `ATTEMPTS=1` |
| P4: no bare `Delta: ` line | visible fixed in every case above that hits the tree-differs path (e.g. [27]'s `Delta: A  lib2.sh`, no blank line ahead of it) |

## Not proven / not covered

- The retry guard's path-only comparison (a rewrite of an already-MUTATE_SET path, or any write
  to a gitignored file) is not exercised by a dedicated test; named under Not covered in the
  spec as a narrower instance of a visibility limit the whole script has always had.
- A concurrent writer to `$root` during the run remains out of scope by the spec's stated
  Assumption; `--base-ref` mode is the documented alternative for a shared checkout.
