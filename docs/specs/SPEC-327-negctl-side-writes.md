# SPEC-327: negctl restores tracked writes the red run itself makes

**Status:** DRAFT (contract only; no code in this PR)
Lane: full
Type: bug-fix / behavioral
**Proof:** `docs/verification/negctl-side-writes.md`; `tests/test-proof-negctl.sh`, the new
side-effect restore case.

## Problem

`lib/gate/negctl.sh` computes its restore set once, right after `mutate_cmd` runs (line 124:
`restore_files` collects `git diff HEAD --name-only -z`), and never revisits it. Step 4's RED
run (`run_test`, the mutated `test_cmd`) executes *after* that capture. When `test_cmd` itself
writes to a tracked file as a side effect of running (a test script that renders live output
onto a committed fixture, not the mutation under test), that write lands after the restore set
was already frozen, so step 5's `restore()` never checks it out. Step 6's `after` snapshot then
differs from `before`, and the run reports `Verdict: FAIL: tree differs from the pre-run
snapshot after restore` for a control whose actual signal (mutation went RED, as required) was
genuine.

This is not hypothetical. `docs/verification/pitch-test-tmp-out.md` (the proof for #784,
`fix(pitch): stop AC1 from dirtying the tracked sample-pitch.md`) hit exactly this while
validating the fix to `tests/test-pitch.sh`, which used to render its live sample straight onto
the committed `docs/verification/pitch-command/sample-pitch.md` on every run. The note names the
mechanism precisely: "negctl.sh's restore set is captured right after the mutate command runs
(before the RED test executes), so it never restores files the test-cmd itself dirties
mid-run", calls it "a real negctl limitation (not a bug in this fix)", and routes around it by
mutating a *read* instead of the *write* that would have reproduced it. That workaround was
correct for that one spec, but it means negctl still cannot run a real mutation against any test
suite that writes a tracked fixture as part of executing, until this gap closes.

## Contract

- After the red-run loop finishes (after the existing vacuous-mutation check at
  `[ "$rc_red" -eq 0 ]`, before the `restore` call), negctl re-runs the identical capture
  (`git diff HEAD --name-only -z`, same command, same NUL-delimited read loop) and **replaces**
  `restore_files` with this second, cumulative list rather than appending to or leaving the
  first one. `git diff HEAD` always reports every tracked-vs-HEAD difference live at the moment
  it runs, regardless of when each difference was introduced, so the second capture is
  automatically a superset: it carries `mutate_cmd`'s own changes (still present, since nothing
  reverted them yet) plus any tracked file `test_cmd` wrote while going RED.
- A path present in the second capture but absent from the first is reported on its own line,
  `Side effect: <files>` (same comma-joined style as the existing `Changed:` line). Nothing is
  printed when the two lists match, which is every case in the suite today -- that output stays
  byte-identical.
- `restore()` runs against the recomputed (superset) list, so a real side-effect tracked write
  is checked out back to `HEAD` exactly as a `mutate_cmd` write already is. A restore failure on
  one of these paths (permission, whatever) still calls the existing `fail()` -- no new failure
  path, an existing one now covers a larger file set.
- The `Changed: <no tracked file>` / `fail "the mutation changed no tracked file"` check (right
  after `mutate_cmd`, line 126-131) keeps reading the **first**, mutate-only capture, untouched:
  it answers "did the mutation itself do anything", a question the later recompute must not
  retroactively answer on its behalf.
- The untracked-file rule is unchanged and unreachable by this fix: `git diff HEAD --name-only`
  only ever lists paths already known to the index (tracked, or newly staged); a `test_cmd` side
  effect that creates or removes a genuinely untracked file stays invisible to `restore_files`
  either way, and still surfaces only through the existing `before`/`after` `snapshot()`
  comparison (`--untracked-files=all`), which still fails the run exactly as it does today. This
  spec touches nothing about that path -- the task brief's "keep the existing rule" holds by
  construction, not by a new guard.
- No new CLI flags, no new usage line. `NEGCTL_RED_ATTEMPTS`, `--base-ref` mode, and every
  existing printed line stay byte-identical whenever there is no side-effect write -- the
  common case every existing proof doc that already quotes negctl's output depends on
  (`docs/verification/land-ship-record.md`, `docs/verification/pitch-test-tmp-out.md`,
  `tests/test-proof-negctl.sh`'s own line-shape assertions).

## Picture

```
 negctl.sh <root> <test-cmd> <mutate-cmd>
          |
   refuse if root dirty                                    (unchanged)
          |
          v
   before = snapshot(); run_test() must exit 0              (unchanged: green before mutation)
          |
          v
   mutate_cmd runs
          |
          v
   restore_files = diff HEAD --name-only   <-- CAPTURE 1 (mutate_cmd's own tracked changes)
   "Changed: ..." printed; empty --> fail "mutation changed no tracked file"
          |
          v
   red loop: run_test() up to NEGCTL_RED_ATTEMPTS times
          |
    all attempts green? --yes--> fail "vacuous" (verdict already set; run continues below)
          |
        a real RED
          |
          v
   #########################################################################
   # NEW: CAPTURE 2 = diff HEAD --name-only (same command, run again now)  #
   # side_effect = CAPTURE 2 minus CAPTURE 1                               #
   # restore_files := CAPTURE 2 (superset: mutation + test-cmd side writes)#
   # side_effect non-empty? --> print "Side effect: <files>"               #
   #########################################################################
          |
          v
   restore()  git checkout -q HEAD -- "${restore_files[@]}"   (now covers CAPTURE 2 in full)
   restore failure --> fail "restore failed: ..."              (existing path, larger file set)
          |
          v
   after = snapshot(); after != before? --> fail "tree differs from the pre-run snapshot"
          |                                  (still the ONLY guard for untracked leftovers)
          v
   run_test() again, must exit 0                              (unchanged: green after restore)
          |
          v
   print Verdict: PASS | FAIL: <first reason>
```

## Design

Design-bearing: the task brief names two candidate fixes ("restore them too" or "refuse by
name"), so the choice and its rejection are recorded here rather than collapsed to `obvious`.

| Approach | Why not / why |
|---|---|
| **Refuse by name**: when CAPTURE 2 carries a path CAPTURE 1 doesn't, `fail("test-cmd wrote to tracked file(s) beyond the mutation: <names>")` and leave those files dirty (never restore them) | Rejected. It turns a genuinely valid control (the mutation went RED, exactly as required) into a hard FAIL purely because the test harness has an incidental tracked-fixture write -- the #784/pitch case exactly. Every caller would first have to go fix the harness (as #784 did, by routing the mutation around the write) before negctl could ever run there, which is a much bigger ask than the negative control itself is supposed to make. It also leaves the operator with a dirtier tree than before the run -- the stray `git checkout --` by hand the whole script's docstring (lines 6-8) says it exists to make unnecessary. |
| Restore CAPTURE 1's files only, then separately `git checkout HEAD --` each newly-seen path from CAPTURE 2 as a second, distinct `restore()` pass | Rejected as unnecessary complexity: `git checkout HEAD -- <paths>` already accepts the full superset list in one call; a second pass buys nothing except a second place `fail()` could fire differently for the same underlying operation. |
| **Chosen: recompute `restore_files` from a second, identical `git diff HEAD --name-only -z` capture taken after the red loop, and restore against that (superset) list** | The recompute reuses the exact same command already used for CAPTURE 1 -- no new git plumbing, no new failure shape. Because `git diff HEAD` is a live snapshot, not a delta since CAPTURE 1, the second call is automatically inclusive of everything CAPTURE 1 already found (nothing un-does a mutation mid-run) plus whatever `test_cmd` added while going RED. One `restore()` call, one `fail()` path, unchanged. |

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| `test_cmd` writes a tracked fixture only when it goes RED (the #784/pitch shape) | CAPTURE 2 carries a path CAPTURE 1 doesn't | included in the recomputed `restore_files`; restored by the existing `restore()` call; reported via the new `Side effect:` line |
| Restoring a side-effect path itself fails (permission, disk full) | `git checkout -q HEAD -- "${restore_files[@]}"` returns nonzero | existing `fail "restore failed: ..."` path fires exactly as it does for a mutate-only file today -- no new failure shape, same message, now over a possibly larger `${restore_files[*]}` |
| `test_cmd` creates or removes a genuinely untracked file | invisible to both `git diff HEAD` captures; only `snapshot()` (`--untracked-files=all`) catches it | unchanged: `after != before` still fires `fail "tree differs from the pre-run snapshot after restore"`; this spec adds no exemption for untracked paths |
| A vacuous mutation (`rc_red -eq 0` on every attempt) also happens to leave a tracked side-effect file dirty | `fail "... vacuous ..."` already fired on the exit code, independent of any file write | `restore()` still runs unconditionally afterward (the script does not short-circuit on a set `fail`), so the recomputed superset still gets checked out and the tree still ends clean; the reported verdict stays the vacuous FAIL, unrescued by any file write, since `fail()` never downgrades an already-set FAIL |
| The recompute itself silently returns fewer paths than CAPTURE 1 (a mutation's own change got reverted mid-test) | `restore_files` becomes CAPTURE 2, which is still whatever's live now; a path CAPTURE 1 named but CAPTURE 2 doesn't is already at `HEAD` and needs no restore | no special-case needed: `git checkout HEAD --` on an already-clean path is a no-op, not an error |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: recompute-and-restore fix | `lib/gate/negctl.sh` | after the red loop and vacuous check, a second `git diff HEAD --name-only -z` capture replaces `restore_files`; a `Side effect: <files>` line prints only when the two captures differ; `restore()` and every downstream check run against the recomputed list unchanged in shape |
| T2: tests | `tests/test-proof-negctl.sh` | new case: a `test-cmd` that additionally writes a second tracked file only while RED under the given mutation ends `Verdict: PASS`, tree clean, `Side effect:` line names that file; existing cases (vacuous, dirty-refuse, untracked-leftover FAIL, staged+unstaged restore) keep passing unmodified, proving no regression |
| T3: docs | `lib/gate/negctl.sh` usage header (steps 3/5 comment block, lines 24-34), `docs/CHANGELOG.md` `[Unreleased]` fix entry; `docs/FEATURES.md` regenerated via `lib/registry/feature-registry.sh generate` only if the registry actually carries a `negctl` entry (it does not today, per a repo grep -- likely a no-op) |
| T4: proof | `docs/verification/negctl-side-writes.md`, `docs/implementation-notes/negctl-side-writes.md` (delta from this spec, crediting `docs/verification/pitch-test-tmp-out.md` as the discovery source) |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Side-effect write during the RED run restores cleanly | `test-cmd` writes a second tracked file only on the RED (post-mutation) run, mirroring the `#784` shape | `Verdict: PASS`; tree clean after; output includes a `Side effect: <second file>` line |
| No side effect (regression) | the suite's existing `mkrepo` fixture (`add()`/`mul()`, no side-effect write) | byte-identical to today: `Verdict: PASS`, no `Side effect:` line, every existing assertion in the file still passes unmodified |
| Side-effect restore itself fails | the second tracked file is made unwritable/unrestorable before the run (e.g. its directory permissions blocked) | `Verdict: FAIL: restore failed: ...`, matching the existing restore-failure message shape |
| Untracked leftover still FAILs | `mutate-cmd` creates a new untracked file (existing case) | unchanged: `Verdict: FAIL: tree differs from the pre-run snapshot after restore` |
| Vacuous mutation with an incidental side write | `test-cmd` stays green on every attempt AND writes a tracked file regardless | `Verdict: FAIL: test stayed green under the mutation (the check is vacuous)`; tree still ends clean (restore still ran) |
| `--base-ref` mode unaffected | existing base-ref test cases | untouched: this fix only changes the mutate-mode branch (`root`/`test_cmd`/`mutate_cmd` path), never the `--base-ref` branch |

Negative control: `lib/gate/negctl.sh` dogfoods itself via `bash tests/test-proof-negctl.sh`
against a mutation that removes the second capture (for example, deleting the `restore_files`
reassignment so it stays at CAPTURE 1). The new side-effect test case must go RED -- it reverts
to today's `Verdict: FAIL: tree differs from the pre-run snapshot after restore` once the
recompute is removed.

## Verification

`bash tests/test-proof-negctl.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.

## After state

`negctl.sh` now treats any tracked file the RED run itself writes as part of the restore set, so
a test suite with an incidental tracked-fixture side effect (the `#784` shape) gets a valid
`Verdict: PASS` instead of a spurious `tree differs` FAIL, without weakening the
untracked-file-is-always-a-FAIL rule. `docs/verification/pitch-test-tmp-out.md`'s
"a real negctl limitation (not a bug in this fix)" note is closed by this change; a future spec
in that shape no longer needs to route the mutation around the write.

Not covered: negctl's final confirmatory green run (step 6, after the `before`/`after` snapshot
comparison already happened) can still leave the tree dirty again as an unreported side effect
of that last `run_test()` call -- that gap predates this fix, sits on a different step, and is
out of scope here; only the RED-run restore-set gap named in the task brief is addressed.

## Decision Log

- Chose to recompute `restore_files` from a second, identical `git diff HEAD --name-only -z`
  capture taken after the red loop, over a stricter refuse-by-name path, because the concrete
  real-world case (`#784`, `docs/verification/pitch-test-tmp-out.md`) is a legitimate
  test-harness fixture write, not evidence the negative control itself is broken.
- Kept the mutate-only (first) capture as the source for the "did the mutation change anything"
  check, unmodified, so that diagnostic keeps asking exactly the question it always has.
- Left the untracked-file rule exactly as is: this spec is scoped to the tracked-file
  restore-set gap named in the task brief, not the whole restore surface.
- Left the step-6 residual-dirt gap (the final green run can still write tracked-or-untracked
  side effects unreported) out of scope: a different step, not named in the task brief, and
  fixing it would change what `Verdict: PASS` is allowed to mean beyond this spec's contract.
