# Verification: wrap follow-through (SPEC-310)

`/kit:wrap follow` (or `[wrap] follow_through = "lanes"`) builds the pass's in-lane leftovers after the report and prints a second, linted `## Follow-through:` report. `follow all` also takes full-lane candidates to a draft PR that wrap never merges. Step 0's foreign-activity stop now covers only writes to the main checkout.

Headless change: prose in `commands/wrap.md`, one resolver verb, one lint change. The capture is text output, no image.

## Green run

| Check | Command | Exit | Output |
|---|---|---|---|
| Wrap suite | `bash tests/test-wrap.sh` | 0 | `test-wrap: all 976 passed` (follow-mode resolution, the unknown-value fallback, step 0 and step 10 contracts, every follow-through lint fixture) |
| Config registry | `bash tests/test-config-registry.sh` | 0 | `=== 56/56 passed ===` (the root-only key set matches `kit_config_get_root` callers) |
| Structure | `bash tests/test-meta.sh` | 0 | `All meta tests passed.` (FEATURES projection fresh) |
| Sample first report | `bash lib/wrap/report-lint.sh first-report.md` | 0 | `report-lint: clean (0 warn(s))`; carries the off-mode FYI row and a `REPORTED ... lane=full` item |
| Sample second report | `bash lib/wrap/report-lint.sh second-report.md` | 0 | `report-lint: clean (0 warn(s))`; no Seam line, a preamble line before the heading, `BUILT ... lane=full ... #764 DRAFT` paired with `a. REVIEW #764` |
| Same second report, `REVIEW` changed to `DECIDE` | `sed ... \| bash lib/wrap/report-lint.sh` | 1 | `item 3 is a full-lane build that is not a '#<pr> DRAFT' named by a 'REVIEW #<pr>' item in Needs you` |
| Resolver, shipped default | `bin/wrap follow-mode` | 0 | `off none` |
| Resolver, override | `bin/wrap follow-mode lanes` / `bin/wrap follow-mode all` | 0 | `lanes tiny,normal,bug,backfill` / `all tiny,normal,bug,backfill,full` on the operator's machine config |

## Negative control

Each control ran after the change was committed, with `T="bash tests/test-wrap.sh"`. Exact mutate commands: SPEC-310 `## Verification`.

```
=== NC1 step 0 revert
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- commands/wrap.md
Exit: 0 (green after restore)
Verdict: PASS
=== NC2 knob default on
Exit: 0 / Exit: 1 / Restore: git checkout HEAD -- kit.toml / Exit: 0
Verdict: PASS
=== NC3 silent fallback
Exit: 0 / Exit: 1 / Restore: git checkout HEAD -- lib/wrap/wrap.sh / Exit: 0
Verdict: PASS
=== NC4 pairing dropped
Exit: 0 / Exit: 1 / Restore: git checkout HEAD -- lib/wrap/report-lint.sh / Exit: 0
Verdict: PASS
=== NC5 draft no longer skipped
Exit: 0 / Exit: 1 / Restore: git checkout HEAD -- lib/wrap/wrap.sh / Exit: 0
Verdict: PASS
```

NC1 restores the old "leave that repo alone" bullet. NC2 ships the knob as `lanes`. NC3 silences the unknown-value line. NC4 lets any full-lane build pass. NC5 lets a draft through `_pr_gate`. Each went RED and came back green after restore.

## Test plan coverage

| Row | Run / skip reason |
|---|---|
| 1 | Wrap suite: `wrap.follow_through ships as off`, follow-mode default/operator/project; NC2 |
| 2 | Wrap suite: follow-mode lanes, all, glob, unknown override, second argument |
| 3 | Wrap suite: unknown value runs as off, one named line; NC3 |
| 4 | Wrap suite: step 0 literals, old phrase absent; NC1 |
| 5 | Wrap suite: step 10 literals and the line-order check |
| 6 | Wrap suite: follow-through lint fixtures (Seam, preamble, Built, permission, FYI tag, off-mode row) |
| 7 | Wrap suite: DRAFT/REVIEW pairing fixtures (decoy, two items, REVIEWED, trailing number, outside Needs you); NC4 |
| 8 | Wrap suite: existing `merge: a draft skips` case; NC5 |
| 9 | Wrap suite, config registry, meta: all green |
| 10 | Sample first and second reports linted above |
| 11 | NC1 to NC5 above |

## Gates

| Phase | Verdict |
|---|---|
| Validate (three lenses) | NEEDS REVISION x3, one design-record BLOCK; all folded or rejected, SPEC-310 "Review disposition" |
| Review (security, test coverage, architecture, advisor) | FIX-THEN-SHIP, SHIP, SHIP, NOT SOLVED; the landing path was rewritten in `1e74386` |

## Not proven

- Step 10 end to end is model-executed prose: drafting the work set, dispatching background workers, the check wait, `wrap merge --pr`, and the second report have not run in a real `/kit:wrap follow` session. The next real wrap with `follow` is that run.
- The full-lane worker (`follow all`) has never run unattended. Its merge refusal rests on the draft skip (NC5) and on the lead removing the worktree; an operator who runs `wrap land` or `wrap merge --pr` on the draft by hand readies and merges it, which is their call.
- Whether an FYI row is finishable work stays a model judgment; the prose gives one worked example.
