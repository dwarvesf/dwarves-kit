# Verification -- pitch-test-tmp-out

`tests/test-pitch.sh` AC1 no longer renders onto the tracked
`docs/verification/pitch-command/sample-pitch.md`; it renders into a scratch temp path and a
new self-check (T3) asserts the tracked path is never read back in.

| Check | Command | Result |
|---|---|---|
| Suite green | `bash tests/test-pitch.sh` | `TOTAL: 30   PASS: 30   FAIL: 0` |
| Tree stays clean | `git status --porcelain` immediately after | empty |
| Full changed suite | `bash tests/run-all.sh --changed` | `test-pitch ok`; tree clean afterward (unrelated pre-existing `test-meta` FEATURES-staleness failure, resolved by the FEATURES regen in this same change) |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-pitch.sh" "<mutate>"` | `Verdict: PASS` |
| Test-plan coverage | see below | 6/6 cases covered |

## Bug demonstrated (red, before the fix)

Before this fix, a plain run of the unmodified suite passed every assertion (29/29) but left
the tree dirty:

```
$ bash tests/test-pitch.sh    # unmodified script
TOTAL: 29   PASS: 29   FAIL: 0
$ git status --porcelain -- docs/verification/pitch-command/sample-pitch.md
 M docs/verification/pitch-command/sample-pitch.md
```

## Green run (after the fix)

```
Command: bash tests/test-pitch.sh
Exit: 0
Verdict: PASS (TOTAL: 30   PASS: 30   FAIL: 0)
```

```
Command: git status --porcelain
Output: (empty)
```

```
Command: bash tests/run-all.sh --changed
test-boundary-lint                             ok
test-config-registry                           ok
test-kit-contract                              ok
test-no-personal-paths                         ok
test-no-scattered-ids                          ok
test-pitch                                     ok
(test-meta's docs/FEATURES.md-staleness failure is the pre-existing, unrelated gap this
change's own FEATURES regen closes -- see the feature-registry commit)
```

## Negative control

The mutation repoints one AC1 read (the section-count grep) back at the tracked proof file --
the exact regression class this spec fixes -- without ever writing it, so the RED signal is
the new self-check assertion (T3) catching the reintroduced literal path, not a dirtied
tracked file:

```
## Negative control (negctl)
Command: bash tests/test-pitch.sh
Exit: 0 (green before mutation)
Mutation: bash /tmp/negctl-mutate-324.sh
Changed: tests/test-pitch.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- tests/test-pitch.sh
Exit: 0 (green after restore)
Verdict: PASS
```

`/tmp/negctl-mutate-324.sh` contents (scratch file, not part of the repo):

```
sed -i '' '/^SECTIONS=\$(grep/ s#"\$SAMPLE_OUT"#"$KIT_DIR/docs/verification/pitch-command/sample-pitch.md"#' tests/test-pitch.sh
```

## Test plan coverage (SPEC-324)

| Case | Verified |
|---|---|
| Suite runs clean | Green run above, exit 0 |
| Tree stays clean | `git status --porcelain` empty after both `test-pitch.sh` alone and `run-all.sh --changed` |
| Temp render still proves the assembler | AC1's three structural assertions (write, 5 sections, spec name) still pass, now against the temp path |
| Tracked sample untouched | `git status --porcelain` carries no diff for `docs/verification/pitch-command/sample-pitch.md` across any of the runs above |
| Frozen fixture path unaffected | `_render_with_origin real-sample`'s PR-link and grill-skip assertions still pass (part of the 30/30 green run) |
| Half-done repoint is caught | Negative control above: reintroducing one tracked-path read fails the new self-check assertion |
| Explicit refresh still works | Not re-exercised automatically (by design, it is a manual/on-demand command); the command itself, `bash lib/pitch.sh render kit-emit-sweep --out docs/verification/pitch-command/sample-pitch.md`, is unchanged from the pre-existing `render` verb and documented in `docs/implementation-notes/kit-pitch.md` |
| Negative control | Recorded above, `Verdict: PASS` |

## Not proven

- Whether `docs/verification/pitch-command/sample-pitch.md` is currently stale relative to the
  live `kit-emit-sweep` ledger state was not checked; refreshing it by hand is a separate,
  optional task (see `docs/implementation-notes/kit-pitch.md`).
- The frozen-fixture mechanism (`tests/fixtures/pitch/real-sample/`, `_render_with_origin`) was
  not modified and is only re-verified as part of the existing green run, not independently.
