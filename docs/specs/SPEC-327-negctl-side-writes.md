# SPEC-327: negctl restores tracked writes the red run itself makes

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
Type: bug-fix / behavioral
**Proof:** `docs/verification/negctl-side-writes.md`; `tests/test-proof-negctl.sh`, the new
side-effect / retry-safety / HEAD-absent restore cases.

## Problem

`lib/gate/negctl.sh` computes its restore set once, right after `mutate_cmd` runs (line 124:
`restore_files` collects `git diff HEAD --name-only -z`, with rename detection left at git's
default -- see the `--no-renames` fix folded into the Contract below), and never revisits it.
Step 4's RED
run (`run_test`, the mutated `test_cmd`) executes *after* that capture. When `test_cmd` itself
writes to a tracked file as a side effect of running (a test script that renders live output
onto a committed fixture, not the mutation under test), that write lands after the restore set
was already frozen, so step 5's `restore()` never checks it out. Step 6's `after` snapshot then
differs from `before`, and the run reports `Verdict: FAIL: tree differs from the pre-run
snapshot after restore` for a control whose actual signal (mutation went RED, as required) was
genuine.

This is not hypothetical. `docs/implementation-notes/pitch-test-tmp-out.md` (lines ~20-29, the
delta notes for #784, `fix(pitch): stop AC1 from dirtying the tracked sample-pitch.md`) hit
exactly this while validating the fix to `tests/test-pitch.sh`, which used to render its live
sample straight onto the committed `docs/verification/pitch-command/sample-pitch.md` on every
run. The note names the mechanism precisely: "negctl.sh's restore set is captured right after
the mutate command runs (before the RED test executes), so it never restores files the test-cmd
itself dirties mid-run", calls it "a real negctl limitation (not a bug in this fix)", and routes
around it by mutating a *read* instead of the *write* that would have reproduced it. That
workaround was correct for that one spec, but it means negctl still cannot run a real mutation
against any test suite that writes a tracked fixture as part of executing, until this gap closes.

A first pass at this spec proposed replacing `restore_files` wholesale with a fresh, superset
capture and restoring the whole thing in one batched `git checkout HEAD --` call. A validator
round proved that shape unsafe with two scratch-repo probes (folded into the Contract below):
`git checkout <commit> -- <paths...>` aborts the *entire* call the instant one path doesn't
resolve at that commit, and the widened restore set can itself mask a genuinely vacuous mutation
when `NEGCTL_RED_ATTEMPTS` > 1. Both are addressed below.

## Assumption (unchanged, now stated explicitly)

Mutate mode already assumes negctl is the sole writer to `$root` for the duration of a run: it
has no way to attribute a concurrent process's edit versus the test's own, because both show up
identically in `git diff HEAD`. This was always true (a shared, concurrently-touched checkout
was already an unsupported use of mutate mode) and this spec does not change it. An operator on
a shared checkout should use `--base-ref` mode instead (it extracts from the object store and
never touches the working tree, so it is immune to this whole class of issue).

## Contract

Five distinct changes below (points 1-5), each closing one gap a validation round named, plus the
`--no-renames` fix folded into every capture's own definition. Terminology used below:

- **MUTATE_SET**: today's `restore_files`, captured once via `git diff HEAD --no-renames --name-only -z`
  right after `mutate_cmd` runs (line 124). **Unchanged**: still captured at the same point,
  still restored via the existing single batched `git checkout HEAD -- "${MUTATE_SET[@]}"` call,
  still the source for the `Changed: ...` / "mutation changed no tracked file" check. This is the
  set the validator's "restore CAPTURE 1 exactly as today" instruction protects.
- **BASELINE_DIFF** (new): `git diff HEAD --no-renames --name-only -z`, captured once right after the
  step-2 "green before mutation" `run_test()` call, before `mutate_cmd` runs at all.
- **SIDE_EFFECT_SET** (new): computed fresh, every time `restore()` runs (see below), as
  `git diff HEAD --no-renames --name-only -z` (a live call, not a stored snapshot) with every path already in
  MUTATE_SET removed. This is "whatever is tracked-different from `HEAD` right now, beyond what
  the mutation itself already accounted for" -- necessarily including anything `test_cmd` wrote
  while going RED, and (see Not covered) anything a prior red-loop attempt already left behind.

Every capture above passes **`--no-renames`**. Without it, a staged `git mv` (a rename) collapses
a delete-then-add pair into a single rename entry, and `--name-only` reports only the *new* path
for that entry -- the old path's deletion never appears in the list at all. A mutation or a
test-cmd side effect that renames a tracked file would then have its old path silently skipped by
every set above: never restored, never even considered for the `HEAD`-existence partition.
`--no-renames` forces git to report the raw delete-then-add pair as two ordinary name-only
entries instead, so both halves show up and get restored (or fail-by-name'd) like any other path.

**1. Accurate wording for the mutation-changed check (was: mislabeled CAPTURE 1).** MUTATE_SET is
captured after both the baseline green run *and* `mutate_cmd`, so if `test_cmd` already writes a
tracked file on the pristine baseline run (before any mutation), that path is cumulatively
present in MUTATE_SET too -- it was never purely "the mutation's own change." The `Changed: ...`
line and the "mutation changed no tracked file" check now report and gate on
`MUTATE_SET \ BASELINE_DIFF` (set difference), not raw MUTATE_SET, so a baseline-dirtying test
harness can no longer make a mutation that changed nothing read as "Changed: <file>" just because
that file was already dirty before the mutation ran. When `BASELINE_DIFF` is non-empty, negctl
also prints one line, `Baseline side write: <files> (test-cmd wrote tracked file(s) before any
mutation ran)`, so a reader sees why the two sets diverge. MUTATE_SET itself, and what gets
restored under that name, are untouched by this change -- it only sharpens what "Changed" means.

**2. Restore side-effect writes safely (was: unconditional superset restore, proven to abort the
whole restore on one HEAD-absent path -- Critical 1).** The recompute-and-restore step moves
*inside* `restore()` itself (see point 3 for why), and never blindly replaces MUTATE_SET or
checks the superset out in one call:

- `restore()` first runs the existing, unmodified `git checkout -q HEAD -- "${MUTATE_SET[@]}"`
  (unchanged: same command, same paths, same failure handling).
- It then computes SIDE_EFFECT_SET (defined above) and partitions it in two, by asking git
  whether each path exists in the `HEAD` tree: `git cat-file -e HEAD:<path>` (exit 0 = exists).
  - **SIDE_EFFECT_HEAD** (exists at `HEAD`, e.g. a tracked fixture `test_cmd` overwrote while
    going RED -- the #784/pitch shape): restored via a *second*, separate batched call,
    `git checkout -q HEAD -- "${SIDE_EFFECT_HEAD[@]}"`. Every path in this call is guaranteed (by
    construction) to resolve at `HEAD`, so this call can never hit the whole-call-abort failure
    Critical 1 found. `Side effect: <files>` is printed when this set is non-empty.
  - **SIDE_EFFECT_NEW** (does not exist at `HEAD` -- a brand-new tracked file `test_cmd` `git
    add`ed while running, the exact shape probe C used): **never** passed to `git checkout`
    (there is no `HEAD` blob to restore from), and **never** `git rm`ed or `git clean`ed --
    negctl does not delete anything it did not put there, and misclassifying a real operator file
    as safe-to-delete is a strictly worse failure than leaving it dirty. Instead, negctl calls
    `fail("test-cmd added new tracked file(s) beyond the mutation that cannot be restored from
    HEAD: <files>; left in place, never auto-removed")` and prints `Side effect (unrestorable):
    <files>`. The run still reports the specific, named reason instead of a generic
    "tree differs" (though that generic check, unchanged, still fires too as a second guard --
    `fail()` keeps only the first message).
- A restoration failure on an existing-at-`HEAD` side-effect path (permission, disk full, same
  class as an existing MUTATE_SET restore failure) still calls the existing
  `fail("restore failed: ...")` -- same message shape as today, scoped to the smaller
  `SIDE_EFFECT_HEAD` list when that's what failed.

**3. Move the recompute inside `restore()`, so the `EXIT` trap covers it too.** Today,
`restore()` is both called explicitly (after the red loop) and registered as the `EXIT` trap
target (for an interrupted run, e.g. Ctrl-C). If SIDE_EFFECT_SET were computed once, externally,
between the red loop and the explicit `restore()` call, an interrupt landing in that narrow
window would fire the trap against a stale (pre-recompute) set. Computing SIDE_EFFECT_SET fresh
*inside* `restore()` itself means every invocation -- explicit or trap-triggered -- recomputes
from the live tree and restores/fails-by-name identically. The existing `restore_done` guard
(no-op on a second call) is unchanged.

`restore()` today has an early return, `[ "${#restore_files[@]}" -gt 0 ] || return 0`, that skips
everything -- including this recompute -- whenever MUTATE_SET is empty (a mutation that changed
no tracked file, which still runs the red loop rather than aborting). That return must be dropped
(or narrowed to guard only the MUTATE_SET checkout call, not the function as a whole), so the
SIDE_EFFECT_SET recompute always runs regardless of whether MUTATE_SET itself is empty. This also
closes the narrowest interrupt window of all: a Ctrl-C landing between `mutate_cmd` finishing and
MUTATE_SET's own capture (line 124) fires the `EXIT` trap while `restore_files` is still unset --
today's early return would then restore nothing at all. With the return dropped, that same
trap-triggered call still recomputes SIDE_EFFECT_SET fresh from the live tree (in this narrow
case, SIDE_EFFECT_SET is simply the *entire* current diff, since MUTATE_SET is empty) and
restores/fails-by-name against it exactly as any other invocation would.

**4. Retry-loop safety (was: a widened restore can mask a vacuous mutation under
`NEGCTL_RED_ATTEMPTS` > 1 -- Critical 2).** The probe: attempt 1 (green) writes a tracked file as
a side effect; that leftover state alone makes attempt 2 come back non-zero -- a RED that is an
artifact of attempt 1's own residue, not evidence the mutation did anything, exactly what the
header's "a genuinely vacuous mutation stays green on every attempt and still FAILs" promises
never happens. Fix: **after every red-loop attempt that comes back green and is *not* the last
permitted attempt**, negctl computes the same delta used for SIDE_EFFECT_SET
(`git diff HEAD --no-renames --name-only -z` minus MUTATE_SET) immediately, before looping again. A non-empty
delta means this "green" attempt already left tracked dirt beyond the mutation baseline, so the
next attempt would not be testing the same premise (the mutation, and only the mutation, applied
to a clean-otherwise tree) as attempt 1 did. negctl calls `fail("attempt <n> of <N> was green but
left tracked dirt beyond the mutation (<files>); retries are unsafe against a polluted tree")`
and breaks out of the loop immediately -- no further attempts run against a tree it can no longer
vouch for. (A green *final* attempt needs no such check: it already falls through to the existing
"test stayed green under the mutation (the check is vacuous)" `fail()`, unchanged, and `restore()`
still cleans up both MUTATE_SET and whatever that attempt left behind exactly as point 2
describes.)

**5. bash 3.2 empty-array safety.** negctl.sh runs under `/bin/bash` on a stock Mac (`#!/usr/bin/env
bash`, and macOS ships bash 3.2 as `/bin/bash`), and `set -uo pipefail` is already in effect
(line 47). Bash 3.2's `set -u` treats `"${arr[@]}"` on an array with zero elements as an *unset*
parameter and aborts with "unbound variable" -- fixed in bash 4.4+, but not on the version this
script must run under. The existing code already guards `restore_files` this way (the
`[ "${#restore_files[@]}" -gt 0 ]` checks around lines 110 and 156); every *new* array this spec
introduces -- `BASELINE_DIFF`, the retry-loop delta array, `SIDE_EFFECT_HEAD`, `SIDE_EFFECT_NEW`
-- must be expanded the same way: a `[ "${#arr[@]}" -gt 0 ]` length check before any `"${arr[@]}"`
expansion (matching the codebase's existing style), never a bare expansion assumed safe because
"it's just an array." `restore()` running from the `EXIT` trap makes this more than cosmetic: a
crash there on an empty-array unbound-variable error skips the restore entirely and leaves the
tree dirty, exactly the hazard the whole script exists to prevent.

**Untracked-file rule (unchanged, kept exactly as the task brief requires):** `git diff HEAD
--no-renames --name-only` only ever lists paths already known to the index (tracked, or newly
staged); a
`test_cmd` side effect that creates or removes a genuinely untracked file stays invisible to
every capture above and still surfaces only through the existing `before`/`after` `snapshot()`
comparison (`--untracked-files=all`), which still fails the run exactly as it does today. Nothing
in points 1-5 touches that path.

No new CLI flags, no new usage line. `--base-ref` mode is untouched (all five points above are
scoped to the `root`/`test_cmd`/`mutate_cmd` mutate-mode branch). Every existing printed line
stays byte-identical whenever `BASELINE_DIFF` and `SIDE_EFFECT_SET` are both empty -- the common
case every existing proof doc that already quotes negctl's output depends on
(`docs/verification/land-ship-record.md`, `docs/implementation-notes/pitch-test-tmp-out.md`,
`tests/test-proof-negctl.sh`'s own line-shape assertions).

## Picture

```
 negctl.sh <root> <test-cmd> <mutate-cmd>
          |
   refuse if root dirty                                          (unchanged)
          |
          v
   before = snapshot()
   run_test() must exit 0                                         (green before mutation)
          |
          v
   BASELINE_DIFF = diff HEAD --no-renames --name-only     <-- NEW: any tracked write test-cmd makes
          |                                       even before any mutation runs
          v
   mutate_cmd runs
          |
          v
   MUTATE_SET = diff HEAD --no-renames --name-only         (unchanged capture point / unchanged contents)
   "Changed: ..." reports MUTATE_SET \ BASELINE_DIFF          <-- NEW: accurate wording
   that set empty? --> fail "mutation changed no tracked file"
          |
          v
   red loop, up to NEGCTL_RED_ATTEMPTS attempts:
     run_test()
     red (nonzero)?  -----------------------------------------> break, fall through
     green, and NOT the last permitted attempt?
        delta = (diff HEAD --no-renames --name-only) \ MUTATE_SET                       <-- NEW
        delta non-empty? --> fail "attempt N left tracked dirt beyond the
                                    mutation (<files>); retries are unsafe"; break
        delta empty?     --> loop again (same premise as attempt 1 still holds)
     green, and IS the last permitted attempt --> fall through (vacuous check below)
          |
          v
   all attempts came back green? --> fail "... vacuous ..." (unchanged message)
          |
          v
   restore()   <-- NOW self-contained: recomputes SIDE_EFFECT_SET on EVERY call,
          |         including a Ctrl-C-triggered EXIT-trap call, and even when
          |         MUTATE_SET is empty (the old early-return no longer skips steps 2-4)
          |
          |   1. MUTATE_SET non-empty? --> git checkout HEAD -- MUTATE_SET   (unchanged)
          |   2. SIDE_EFFECT_SET = (diff HEAD --no-renames --name-only, live) \ MUTATE_SET
          |      for each path: git cat-file -e HEAD:<path> ?
          |        exists   --> SIDE_EFFECT_HEAD (restorable)
          |        absent   --> SIDE_EFFECT_NEW  (not restorable from HEAD)
          |   3. git checkout HEAD -- SIDE_EFFECT_HEAD   (2nd batched call; every path resolves,
          |      so this call can never hit the whole-call-abort failure)
          |      "Side effect: <files>" printed when non-empty
          |   4. SIDE_EFFECT_NEW non-empty?
          |      --> fail "...cannot be restored from HEAD: <files>; left in place,
          |                  never auto-removed" (no git rm / git clean, ever)
          |      --> "Side effect (unrestorable): <files>" printed
          v
   after = snapshot(); after != before? --> fail "tree differs from the pre-run snapshot"
          |                                  (unchanged; still the untracked-leftover catch-all,
          |                                   now also a second guard behind point 4's named fail)
          v
   run_test() again, must exit 0                                   (unchanged: green after restore)
          |
          v
   print Verdict: PASS | FAIL: <first reason recorded>
```

## Design

Design-bearing: the task brief named two candidate fixes ("restore them too" or "refuse by
name"); a validator round then proved the first naive shape of "restore them too" unsafe with
two scratch-repo probes. Both rounds of choice-and-rejection are recorded here.

| Approach | Why not / why |
|---|---|
| Single batched `git checkout HEAD -- ` over the full superset (MUTATE_SET + every SIDE_EFFECT_SET path) in one call -- **this spec's original, now-rejected shape** | Proven broken by a validator probe: `git checkout <commit> -- <paths...>` aborts the *entire* call the moment one path doesn't resolve at that commit. A red run that `git add`s a brand-new tracked file (a plausible test-harness shape, not only the fixture-overwrite shape #784 hit) makes the whole restore a no-op, leaving the *mutation still applied* on the operator's tree -- strictly worse than today's narrower-but-working restore, and a direct violation of the script's own "a tool that mutates the working tree must FAIL CLOSED" header contract. |
| Refuse by name whenever the tree carries anything beyond MUTATE_SET, restoring nothing extra | Rejected for the reason given in the first design pass: it hard-fails the exact valid #784/pitch case, where the extra path is a legitimate, `HEAD`-restorable fixture write. |
| **Chosen: restore MUTATE_SET exactly as today (unchanged first call); partition anything beyond it into HEAD-existing (restored via a second batched call) and HEAD-absent (never checked out, never `git rm`/`git clean`, failed by name)** | Two checkout calls instead of one costs nothing meaningful, and each call is now guaranteed by construction to only ever name paths that resolve at the commit it targets, so neither call can hit the whole-call-abort failure mode. A HEAD-absent path is real, unrestorable dirt the operator must see and clean up by hand -- reported by name, never silently discarded or force-removed (`git rm`/`git clean` could delete an operator's own untracked work if the classification were ever wrong, so the fix never reaches for either). |
| Reset the tree to the mutation baseline (MUTATE_SET-only state) between *every* red-loop attempt, green or not | Considered for the retry-safety fix. Rejected as unneeded cost: it would run a checkout (with the same HEAD-existence filtering) after every attempt regardless of outcome, when the actual hazard is narrow -- only a green, *non-final* attempt that leaves new tracked dirt beyond the mutation baseline can corrupt the next attempt's premise. Detecting exactly that condition and failing by name is cheaper and equally fail-closed. |
| **Chosen: after each non-final green attempt, check the MUTATE_SET-relative delta; a non-empty delta fails by name and stops further attempts** | Directly closes the probe-A hazard (a green attempt's side write making a *later* attempt spuriously RED) without adding a reset-and-retry cycle to every iteration; the loop stops the first moment the multi-attempt premise (every attempt sees the same mutation-only tree) is known to be violated, rather than after the fact. |

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| `test_cmd` overwrites a tracked fixture only while RED, and that path still exists at `HEAD` (the #784/pitch shape) | appears in SIDE_EFFECT_SET; `git cat-file -e HEAD:<path>` succeeds -> SIDE_EFFECT_HEAD | restored via the second batched `git checkout HEAD --` call; reported via `Side effect: <files>` |
| `test_cmd` (or a red-loop attempt) `git add`s a brand-new tracked file that has no `HEAD` blob (probe C's shape) | appears in SIDE_EFFECT_SET; `git cat-file -e HEAD:<path>` fails -> SIDE_EFFECT_NEW | never passed to any `git checkout` call (prevents the whole-call-abort regression); never `git rm`/`git clean`d; `fail()` names the path(s) explicitly, `Side effect (unrestorable): <files>` printed |
| Restoring a SIDE_EFFECT_HEAD path itself fails (permission, disk full) | the second batched checkout call returns nonzero | existing `fail "restore failed: ..."` shape, scoped to this smaller list -- no new failure shape |
| A green, non-final red-loop attempt leaves tracked dirt beyond MUTATE_SET (probe A's shape: masks a vacuous mutation as RED on a later attempt) | the MUTATE_SET-relative delta, checked once per non-final green attempt inside the loop | `fail("attempt <n> ... retries are unsafe against a polluted tree")`; loop breaks immediately, no further attempts run |
| `test_cmd` already writes a tracked file on the pristine baseline (pre-mutation) run | `BASELINE_DIFF`, captured right after step 2 | subtracted from MUTATE_SET before deciding "did the mutation change anything"; printed as `Baseline side write: <files>`; a baseline-introduced *brand-new* tracked file is **not** specially guarded against the HEAD-absent restore-abort risk described above -- out of scope, see Not covered |
| `test_cmd` creates or removes a genuinely untracked file | invisible to every `git diff HEAD` capture; only `snapshot()` (`--untracked-files=all`) catches it | unchanged: `after != before` still fires `fail "tree differs from the pre-run snapshot after restore"` |
| An interrupted run (Ctrl-C) between the red loop finishing and the normal `restore()` call | the `EXIT` trap fires `restore()` | unaffected by timing: SIDE_EFFECT_SET is now computed *inside* `restore()` from the live tree at call time, so a trap-triggered call restores/fails-by-name identically to an explicit one |
| A concurrent writer touches `$root` during the run | undetectable by design -- `git diff HEAD` cannot attribute an edit to negctl's own steps versus an outside process | out of scope by the stated Assumption; point a shared checkout at `--base-ref` mode instead |
| A new array (`BASELINE_DIFF`, the retry-delta array, `SIDE_EFFECT_HEAD`, `SIDE_EFFECT_NEW`) is empty and gets bare-expanded (`"${arr[@]}"`) under bash 3.2's `set -u` | `/bin/bash` (macOS's stock 3.2) treats that as an unbound variable and aborts -- most dangerously from inside `restore()`, which can run from the `EXIT` trap | every new array is length-checked (`[ "${#arr[@]}" -gt 0 ]`) before any bare expansion, matching the existing `restore_files` guard style; the suite is run under `/bin/bash` explicitly, not just whatever `bash` resolves to on `$PATH` |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: BASELINE_DIFF + accurate "Changed" wording | `lib/gate/negctl.sh` | `BASELINE_DIFF` captured once right after the step-2 green run; `Changed: ...` and the "mutation changed no tracked file" check both read `MUTATE_SET \ BASELINE_DIFF`; when that difference is empty the printed line is the exact, unchanged `Changed: <no tracked file>` string (T4d pins this); a `Baseline side write: <files>` line prints only when `BASELINE_DIFF` is non-empty; has its own negative control (T4d's, below) |
| T2: retry-loop safety guard | `lib/gate/negctl.sh` | after every non-final green red-loop attempt, the MUTATE_SET-relative delta is checked; non-empty delta calls `fail()` by name and breaks the loop before another attempt runs; a final green attempt is unaffected (existing vacuous `fail()` still fires); the delta array is length-checked before any `"${arr[@]}"` expansion |
| T3: restore() recompute + two-group restore | `lib/gate/negctl.sh` | `restore()` recomputes `SIDE_EFFECT_SET` from a live `git diff HEAD --no-renames --name-only -z` on every call (explicit or `EXIT`-trap-triggered), including when MUTATE_SET is empty (the early `[ "${#restore_files[@]}" -gt 0 ] || return 0` no longer skips the recompute); partitions it via `git cat-file -e HEAD:<path>`; restores `SIDE_EFFECT_HEAD` in a second batched checkout; never checks out, `git rm`s, or `git clean`s `SIDE_EFFECT_NEW`, and `fail()`s naming it instead; MUTATE_SET's own restore call is untouched; `SIDE_EFFECT_HEAD`/`SIDE_EFFECT_NEW` are both length-checked before any bare expansion |
| T4: tests | `tests/test-proof-negctl.sh` | new cases, one per gap above: (a) a tracked fixture overwritten only while RED restores cleanly, `Verdict: PASS`, `Side effect:` line names it; (b) a red-loop attempt `git add`s a brand-new tracked file with `NEGCTL_RED_ATTEMPTS=1` -- MUTATE_SET still restores, the new file is named in a `fail()` and left in place, `Verdict: FAIL`, tree otherwise clean; (c) `NEGCTL_RED_ATTEMPTS>1`, attempt 1 green + writes a tracked file, attempt 2 red only because of that leftover -- run must `fail("... retries are unsafe ...")`, never `Verdict: PASS`; (d) `test-cmd` writes a tracked file on the un-mutated baseline run and `mutate-cmd` changes nothing else -- negctl prints the exact string `Changed: <no tracked file>` and fails as "mutation changed no tracked file", not masked by the baseline write; every pre-existing case (vacuous, dirty-refuse, untracked-leftover FAIL, staged+unstaged restore, `--base-ref` mode) keeps passing unmodified |
| T5: docs | `lib/gate/negctl.sh` usage header (steps 3/5 comment block, lines 24-34); `docs/CHANGELOG.md` `[Unreleased]` fix entry; `docs/FEATURES.md` regenerated via `lib/registry/feature-registry.sh generate` | the usage header names BASELINE_DIFF, `--no-renames`, the two-group restore, the dropped early return, and the retry-loop guard; `docs/FEATURES.md` regen runs and is a no-op if the registry carries no `negctl` entry (confirmed absent today by a repo grep) -- checked in either way so a future entry can't go stale silently |
| T6: proof | `docs/verification/negctl-side-writes.md`, `docs/implementation-notes/negctl-side-writes.md` | delta-from-spec notes credit `docs/implementation-notes/pitch-test-tmp-out.md` as the discovery source; verification doc records all four new negative controls (T4's a/b/c/d) plus a `/bin/bash`-specific run, the full green suite, and `run-all.sh --changed` |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Side-effect write during the RED run restores cleanly | `test-cmd` overwrites a second, already-`HEAD`-tracked file only on the RED (post-mutation) run, mirroring the `#784` shape | `Verdict: PASS`; tree clean after; output includes `Side effect: <second file>` |
| No side effect (regression) | the suite's existing `mkrepo` fixture (`add()`/`mul()`, no side-effect write) | byte-identical to today: `Verdict: PASS`, no `Side effect:`/`Baseline side write:` line, every existing assertion in the file still passes unmodified |
| HEAD-absent side-effect file: restore-or-fail-by-name, never abort the whole restore (Critical 1's shape) | the RED run `git add`s a brand-new tracked file (no `HEAD` blob); `NEGCTL_RED_ATTEMPTS=1` | `Verdict: FAIL`, naming the new file as unrestorable; **MUTATE_SET's own file is still restored** (the regression this replaces: today's naive superset restore would abort entirely and leave the mutation applied); the new file itself is left in place, never `git rm`ed |
| Retry-safety: a green attempt's side write must not mask a vacuous mutation (Critical 2's shape) | `NEGCTL_RED_ATTEMPTS=2`; attempt 1 is green and additionally writes a tracked file; attempt 2 comes back red *only because* of that leftover file | `Verdict: FAIL: attempt 1 of 2 was green but left tracked dirt beyond the mutation (...); retries are unsafe against a polluted tree`; the run never reports `Verdict: PASS`; loop stops after attempt 1, attempt 2 never runs |
| T4(d): baseline side write reflected accurately | `test-cmd` writes a tracked file even on the un-mutated baseline run, and `mutate-cmd` changes nothing else | negctl prints the exact, unchanged string `Changed: <no tracked file>` (not "Changed: <the baseline file>") and `fail "the mutation changed no tracked file"` fires -- proving the check reads `MUTATE_SET \ BASELINE_DIFF`, not raw MUTATE_SET; `Baseline side write: <file>` also printed |
| Untracked leftover still FAILs | `mutate-cmd` creates a new untracked file (existing case) | unchanged: `Verdict: FAIL: tree differs from the pre-run snapshot after restore` |
| `--base-ref` mode unaffected | existing base-ref test cases | untouched: none of T1-T3 touch the `--base-ref` branch |

Negative control, one per new mechanism (each must independently turn its own T4 case red):

- **Baseline-diff subtraction (T4d):** mutate `lib/gate/negctl.sh` so the `Changed: ...` / vacuous
  check reads raw MUTATE_SET again instead of `MUTATE_SET \ BASELINE_DIFF`. T4d's case must flip
  from the correct `Changed: <no tracked file>` to wrongly reporting the baseline file as the
  mutation's own change (`Changed: <baseline file>`, no `fail`), proving the subtraction is
  load-bearing.
- **Side-effect restore (T4a):** mutate `lib/gate/negctl.sh` so `restore()` skips the
  `SIDE_EFFECT_HEAD` checkout entirely (restores only MUTATE_SET, i.e. today's unfixed
  behavior). T4a's case must revert to `Verdict: FAIL: tree differs from the pre-run snapshot
  after restore`.
- **HEAD-absent safety (T4b):** mutate `lib/gate/negctl.sh` so the two-group partition is
  removed and `restore()` goes back to one batched `git checkout HEAD --` over the full
  unfiltered superset. T4b's case must show MUTATE_SET's own file *not* restored (the
  whole-call-abort regression reproduced), proving the partition is load-bearing, not cosmetic.
- **Retry-safety (T4c):** mutate `lib/gate/negctl.sh` so the post-attempt delta check inside the
  red loop is removed (retries proceed unconditionally, as before this spec). T4c's case must
  flip to `Verdict: PASS` -- proving that, without the guard, the exact vacuous-masked-as-red
  hazard the validator's probe A found reappears.

## Verification

`bash tests/test-proof-negctl.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.
`/bin/bash tests/test-proof-negctl.sh` exits 0 too -- explicitly under macOS's stock bash 3.2,
not whatever `bash` resolves to first on `$PATH`, since that is the version whose `set -u`
treats an empty array expansion as an unbound-variable error (point 5 of the Contract).

## After state

`negctl.sh` restores MUTATE_SET exactly as before, and additionally restores any tracked file the
RED run itself wrote, as long as that file still exists at `HEAD` -- so a test suite with an
incidental tracked-fixture side effect (the `#784` shape) gets a valid `Verdict: PASS` instead of
a spurious `tree differs` FAIL. A red run that stages a brand-new tracked file no longer silently
aborts the entire restore (leaving the mutation applied); it is named and left in place, and the
run fails loudly instead. A green, non-final retry attempt that leaves tracked dirt can no longer
manufacture a false RED on the next attempt and mask a vacuous mutation as `Verdict: PASS`. The
untracked-file-is-always-a-FAIL rule is unchanged throughout.
`docs/implementation-notes/pitch-test-tmp-out.md`'s "a real negctl limitation (not a bug in this
fix)" note is closed by this change; a future spec in that shape no longer needs to route the
mutation around the write.

Not covered:

- negctl's final confirmatory green run (after the `before`/`after` snapshot comparison already
  happened) can still leave the tree dirty again as an unreported side effect of that last
  `run_test()` call -- predates this fix, sits on a different step, out of scope.
- A brand-new tracked path that ends up **inside MUTATE_SET itself** -- whether `mutate_cmd`
  directly stages one (confirmed by hand: `git mv lib.sh lib2.sh` as the mutation puts
  `lib2.sh`, which has no `HEAD` blob, straight into MUTATE_SET) or the baseline run does before
  any mutation runs -- is restored via MUTATE_SET's unchanged, unfiltered batched call and hits
  the exact whole-call-abort class this spec fixes for the *beyond-MUTATE_SET* path. This
  predates this spec entirely (reproduced against the pre-fix script too, independent of
  `--no-renames`) and is left open here because the task brief and both validator probes are
  scoped to the red-run side-effect path, not MUTATE_SET's own restore. A future spec would
  apply the identical `git cat-file -e HEAD:<path>` partition to MUTATE_SET's own capture. The
  `git mv` case above also confirms `--no-renames` does what it's for: `Changed:` correctly
  names both `lib.sh` and `lib2.sh` instead of silently dropping the deleted half -- the
  restore failure that follows is this pre-existing, separately-scoped gap, not a new one.
- A concurrent writer to `$root` during the run: out of scope by the stated Assumption; use
  `--base-ref` mode on a shared checkout.
- The retry-loop safety guard (point 4) compares tracked **paths** only, not content. A red-loop
  attempt that writes again to a path already inside MUTATE_SET (the mutation's own file) is
  invisible to the delta check -- it isn't a *new* path, so a further, undetected change there
  between attempts is not flagged, even though it could equally corrupt the "every attempt sees
  the same tree" premise. A write to a gitignored file is invisible to every capture in this
  spec, not only the retry guard: `git diff HEAD` never reports a path git isn't tracking, so a
  side effect landing there passes both the retry guard and the final restore silently. Neither
  case is addressed here; both are narrower instances of the same path-only, tracked-only
  visibility this whole script has always had.

## Decision Log

- Chose to restore MUTATE_SET via its existing, unmodified call and treat anything beyond it as a
  separate, `HEAD`-existence-filtered restore, over the original single-superset-checkout shape,
  after a validator probe proved the single-call shape aborts entirely on one HEAD-absent path.
- Chose to never `git rm`/`git clean` a HEAD-absent side-effect path, only `fail()` by name: the
  cost of a wrong "safe to delete" classification (an operator's own file) outweighs the
  inconvenience of a manual cleanup after a named, loud failure.
- Chose to fail-by-name and stop retrying on a polluted non-final attempt, over resetting the
  tree to the mutation baseline before every attempt: cheaper, and the hazard only exists on a
  green, non-final attempt in the first place.
- Chose to move the SIDE_EFFECT_SET recompute inside `restore()` itself (rather than compute it
  once, externally, before the explicit call), so the `EXIT` trap's own invocation (an
  interrupted run) restores/fails-by-name identically to the normal path.
- Chose to fix the `Changed: ...` wording (subtract `BASELINE_DIFF`) rather than defer it to "Not
  covered": the extra capture and set-subtraction is cheap, and the accuracy gap it closes
  (a mutation that changed nothing reading as "Changed: <file>" because the baseline run already
  dirtied that file) is real, not speculative.
- Left the untracked-file rule exactly as is, and left a `BASELINE_DIFF`-introduced HEAD-absent
  file unfixed: both are scoped out per the task brief and the validator's own probes, named
  explicitly under Not covered rather than silently dropped.
- Added `--no-renames` to every `git diff HEAD` capture after realizing a staged `git mv` would
  otherwise collapse a delete-then-add pair into one rename entry and hide the deleted path from
  every set this spec defines, not only the ones it fixes.
- Dropped `restore()`'s early return for an empty MUTATE_SET rather than special-casing around
  it, so the SIDE_EFFECT_SET recompute is unconditional: simpler than two code paths, and it also
  closes the interrupt window between `mutate_cmd` finishing and MUTATE_SET's own capture.
- Named the retry guard's path-only blind spot (a rewrite of an already-MUTATE_SET path, or any
  write to a gitignored file) under Not covered instead of extending the guard to cover it: both
  are narrower instances of a visibility limit this whole script has always had, not new gaps
  this fix introduces.
- Pinned the exact `Changed: <no tracked file>` string for T4d and gave T1 its own negative
  control, so the `BASELINE_DIFF` subtraction is exercised and provably load-bearing, not merely
  descriptive prose.
- Required every new array this spec introduces to be length-checked before expansion, matching
  the codebase's existing `restore_files` guard style, because bash 3.2 (macOS's `/bin/bash`)
  treats a bare empty-array expansion under `set -u` as an unbound-variable abort -- and a crash
  inside `restore()`, which can run from the `EXIT` trap, would skip the restore it exists to
  guarantee.
