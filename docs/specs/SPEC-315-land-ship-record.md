# SPEC-315: wrap land records the ship gate

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
Type: spec-feature
**Proof:** `docs/verification/land-ship-record.md`; `tests/test-wrap.sh`, the land ship-gate record block.

## Problem

`bin/wrap land <worktree>` squash-merges a PR but never appends a `| GATE | ship | ran |`
line to the landed branch's run ledger. `/kit:ship` (`commands/ship.md` Step 8) does, in the
exact same shape: `bash lib/gate/gate-ledger.sh record <rid> Ship ran "shipping pr=#<N>"`.
`/kit:wrap` step 8 (`commands/wrap.md`) decides whether to invoke `/kit:retro` by grepping the
run ledgers for `shipping pr=#<n>` naming any PR number merged in step 3: a hit means run the
retro now, no hit means skip it as a `SKIPPED` bullet. A spec cycle shipped through `land`
instead of `/kit:ship` therefore never trips that grep, so `/kit:retro` never fires for it, even
though a real spec cycle merged.

## Contract

- Right after `cmd_land`'s tree-verify reads `OK` (the `_tree_verify` case's `OK)` branch, and
  before any tidy step (origin branch delete, main-checkout pull, worktree removal, local
  branch delete), `land` derives the run id for the landed branch and, conditionally, records
  the ship gate for it in the exact ledger line `/kit:ship` writes:
  `| GATE | ship | ran | shipping pr=#<n>`.
- **Derivation reuses `gate-ledger.sh`'s own `rid` verb**, run with the worktree still on disk
  and still checked out on the landed branch (the removal step runs later in `cmd_land`, so the
  branch is still live at this point): `(cd "$wt" && bash "$GATE_LEDGER_SH" rid)`. This is the
  identical branch-to-rid rule `rid()` already applies (strip up to the branch's first `/`, then
  `runid()`'s alnum/`.`/`_`/`-` normalization) -- `land` never reimplements a second slug rule,
  per the task brief's constraint.
- **Record only when the rid already started a run.** `land` calls
  `bash "$GATE_LEDGER_SH" show <rid>` first; a nonzero exit (no ledger file for that rid) means
  no grill/spec/etc was ever recorded for it, so a plain ad-hoc `land` of a tiny/hand-made
  branch with no spec cycle behind it writes nothing. Only a rid with an existing ledger file
  gets the `Ship ran` line appended.
- **Never fails the land.** If rid derivation comes back empty (an unexpected git state this
  late -- tree-verify already required a real, non-default branch) or the `record` call itself
  exits nonzero (a permission error, an unresolvable ledger root, disk full), `land` prints one
  line naming the failure and continues exactly as it would without this feature; the record
  attempt never changes `cmd_land`'s own exit code, at any of its existing return points.
- Output shape:
  - recorded: `     recorded ship gate for <rid> (pr=#<n>)` (stdout, matches the existing
    indented report-line style of the rest of `cmd_land`)
  - no prior ledger for the rid: no line at all -- a normal ad-hoc land, not a failure
  - record attempt failed: `     ship-gate record FAILED for <rid> (pr=#<n>); record it by hand`
    (stderr)

## Picture

```
 wrap.sh land <worktree>
          |
          v
   push branch, adopt/open PR, squash-merge
          |
          v
   _tree_verify(wt, def, tip, mergeSha)
          |
   MISMATCH / other --------> return 3 (unchanged; ship-gate record never runs)
          |
         OK
          |
          v
   land_rid = (cd <worktree> && gate-ledger.sh rid)   [worktree still on disk,
          |                                            still checked out on the landed branch]
          v
   land_rid empty? --yes--> skip silently, continue to the existing tidy steps
          |
          no
          v
   gate-ledger.sh show <land_rid>   [does a ledger file exist for this rid already?]
          |
     no file (exit != 0) --------> skip silently: ad-hoc land, no prior run to attribute this to
          |
       file exists
          |
          v
   gate-ledger.sh record <land_rid> Ship ran "shipping pr=#<n>"
          |                    \
       exit 0                exit != 0
          |                      \
          v                       v
   print "recorded ..."    print "... FAILED ..." (stderr)
          |                       |
          +-----------+-----------+
                      |
                      v
   existing tidy: delete origin branch (leased), pull main --ff-only,
   remove worktree, delete local branch  <-- unaffected either way
```

## Design

Design-bearing: this wires a new cross-subsystem call (`wrap.sh` -> `gate-ledger.sh`) with a
deliberate silent-failure contract, so the approach and its rejected alternatives are recorded
here rather than collapsed to `obvious`. The state walk (derive rid -> check prior ledger ->
record) is the same one `## Picture` above already draws at the tree-verify-`OK` branch; it is
not repeated here. What Picture does not show is WHY each fork resolves the way it does:

Chosen approach and alternatives considered:

| Approach | Why not / why |
|---|---|
| Re-implement the slug rule inline in `wrap.sh` (strip a `type/` prefix, then normalize) | Rejected outright: `wrap.sh` already computes a *different* slug for worktree-directory naming at `cmd_start` (`${branch##*/}`, the last path segment, not `rid()`'s first-slash strip). Reimplementing `rid()`'s exact rule a third time is exactly the "divergent slug rule" the task brief forbids -- a future change to `rid()`'s normalization would silently desync from a hand-copied rule here. |
| Extract rid derivation into a new shared `lib/gate/rid.sh` sourced by both `gate-ledger.sh` and `wrap.sh` | Considered. Correct in principle, but changes `gate-ledger.sh`'s internal structure (a public function boundary it does not have today) for a single call site, and adds a new file to review under the enforcement-surface escalation rule (`lib/` changes route through `/kit:review-team`). Over-engineered for a leaf addition; rejected. |
| **Chosen: shell out to the existing `bash lib/gate/gate-ledger.sh rid` verb, cwd'd into the still-live worktree** | Reuses the verb byte-for-byte -- zero duplicated logic, and any future change to `rid()`'s normalization is picked up automatically. The worktree is guaranteed to still exist and still be on the landed branch at this point in `cmd_land` (removal happens several steps later), so `(cd "$wt" && ... rid)` reads the same branch `rid()` would read if it were invoked as part of the original session. |
| Record unconditionally (skip the `show` prior-ledger check) | Rejected: the task brief requires recording "only when that rid already has a run log", so a random tiny-lane or hand-made branch with no spec cycle behind it does not fabricate a `Ship ran` line that would make `/kit:wrap` step 8's retro grep fire for work nobody speced. |
| Fail the land when the record call fails | Rejected: the ship-gate record is a nice-to-have telemetry line for the retro-trigger grep, not a correctness gate for the merge itself (the merge is already tree-verified by the time this code runs). Failing `land` over a ledger-write hiccup would turn a successful, verified merge into a reported failure over an unrelated subsystem. |

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| rid derivation returns empty (unexpected this late; tree-verify already required a real, non-default branch) | `land_rid` is empty after the `(cd "$wt" && ... rid)` subshell | treated as "no rid": skip recording entirely, `land` proceeds through its existing tidy steps unaffected |
| No prior ledger for the rid (ad-hoc/hand-made land, no spec cycle) | `gate-ledger.sh show <rid>` exits nonzero | skip recording silently; this is the intended, common case for a non-spec land, not an error |
| `gate-ledger.sh record` itself fails (ledger root unresolvable, permission denied, disk full) | nonzero exit from the `record` call | print one `FAILED` line to stderr naming the rid and PR number; `cmd_land`'s own exit code is untouched, and every downstream tidy step still runs |
| Test-suite corpus pollution (this code is the FIRST place `tests/test-wrap.sh` invokes `gate-ledger.sh`, and every existing `land` test now exercises it too) | a test run without an isolated ledger root would read/write the real machine's `~/.local/state/dwarves-kit/logs` corpus | `tests/test-wrap.sh` exports `KIT_LEDGER_DIR` at a `$TMPD`-scoped path once, near its existing `KIT_CONFIG_OPERATOR` pin, so every `$WRAP` invocation in the file (not only the new land cases) resolves an isolated ledger root |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: the land ship-gate record | `lib/wrap/wrap.sh` | after tree-verify reads `OK`, `land` derives the rid via the existing `rid` verb, checks for a prior ledger via `show`, and records `Ship ran "shipping pr=#<n>"` only then; a record failure never changes `land`'s exit code at any existing return point |
| T2: tests | `tests/test-wrap.sh` | an isolated `KIT_LEDGER_DIR` exported once for the whole suite; new cases: a rid with a seeded ledger gets the `Ship ran` line and the reported "recorded" line, a rid with no ledger writes nothing and reports nothing, a `record` call forced to fail (a read-only ledger file) still exits `land` 0 and prints the `FAILED` line |
| T3: docs | `commands/wrap.md` (Step 3's land bullet), `docs/CHANGELOG.md` `[Unreleased]` COMPAT, `docs/FEATURES.md` (regenerated via `lib/registry/feature-registry.sh generate`) | the land bullet names the new ship-gate record and its "only when a prior ledger exists, never fails the land" behavior |
| T4: proof | `docs/verification/land-ship-record.md`, `docs/implementation-notes/land-ship-record.md` | the green `tests/test-wrap.sh` and `tests/run-all.sh --changed` runs, the negative-control block, and the delta-from-spec notes |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Existing ledger, happy path | seed `runs/<rid>.log` with a `spec ran` line for the landed branch's rid before calling `land` | `land` exits 0; output includes `recorded ship gate for <rid> (pr=#<n>)`; the ledger file gains a `| GATE | ship | ran | shipping pr=#<n>` line |
| No prior ledger | no ledger file exists for the rid before calling `land` | `land` exits 0 exactly as before this change; output names neither `recorded ship gate` nor `FAILED`; no ledger file is created for the rid |
| `record` call fails | seed a ledger file for the rid, then `chmod 444` it so the append fails | `land` still exits 0 (or whatever the happy-path exit already is); output includes `ship-gate record FAILED for <rid> (pr=#<n>); record it by hand` on stderr; the land's other postconditions (branch deleted, worktree removed, main pulled) hold exactly as the pre-existing happy-path test already checks |
| Existing land tests unaffected | every pre-existing `land` test in the file (`ok`, `knobkeep`, `basekeep`, `dirty`, `ondef`, `blocked`) | all pass unchanged now that `KIT_LEDGER_DIR` is exported suite-wide; none of them seed a ledger for their rid, so each is also a live instance of the "no prior ledger" case |

Negative control: `lib/gate/negctl.sh` mutates the new `land_rid`/`show`/`record` block in
`cmd_land` (for example, dropping the `show` prior-ledger guard so a plain ad-hoc land starts
recording unconditionally, or reversing the exit-code check on `record` so a real failure
prints "recorded" instead of "FAILED"). The suite must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.

## After state

`bin/wrap land <worktree>` now leaves the same `| GATE | ship | ran | shipping pr=#<n>` trail
`/kit:ship` leaves, for any rid that already started a run (grill, spec, spec-validate, or any
other phase recorded before the land). `/kit:wrap` step 8's retro-trigger grep now fires for a
spec cycle shipped through `land` exactly as it already does for one shipped through
`/kit:ship`. A hand-made, non-spec land (no prior ledger for its rid) is unaffected: it still
writes nothing to the gate ledger, exactly as before this change.

Not covered: a rid whose branch name changed between the run's start and the land (the rid at
land time is derived from the branch `land` actually pushes and merges, which is correct for
`land`'s own use, but a renamed branch would not retroactively fix an earlier session's
ledger). Not covered: retroactively back-filling a `Ship ran` line for a branch already landed
before this change shipped -- only landings from this point forward gain the record.

## Decision Log

- Chose to shell out to the existing `gate-ledger.sh rid` verb (cwd'd into the still-live
  worktree) over reimplementing its slug rule or extracting a new shared library, per the task
  brief's explicit "do not re-implement a divergent slug rule" constraint. See the Design
  table above for the full comparison.
- Chose to gate the record on a prior ledger file (`show` exit code) rather than recording
  unconditionally, so a plain tiny/hand-made land never fabricates a `Ship ran` line for work
  that never ran a spec cycle.
- Chose to never fail `land` over a record failure: the record is a telemetry line for a
  downstream retro-trigger grep, not a correctness gate on the already-tree-verified merge.
- Discovered while writing the test plan: this is the first place `tests/test-wrap.sh` ever
  invokes `gate-ledger.sh`, so every pre-existing `land` test would otherwise touch the real
  machine's ledger corpus. Fixed by exporting `KIT_LEDGER_DIR` at a `$TMPD`-scoped path once,
  suite-wide, alongside the existing `KIT_CONFIG_OPERATOR` pin.
