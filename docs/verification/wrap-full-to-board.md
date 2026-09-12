# Full-lane candidates file a board row; backfill builds inline

Follow-up to `wrap-build-lanes.md`. That change gave step 7b a `wrap.build_lanes` list and
excluded two lanes from an inline build whatever the list said. Both exclusions routed to
`_meta/backlog-staging.md`, which has no consumer: one estate board holds 248 rows staged
since May and has drained none.

## The change

1. **`backfill` builds inline when listed.** The classifier calls backfill brownfield
   operating-layer documentation (`lib/classify/lane-classify.sh:127`), so an inline build
   carries the same risk as `tiny`, `normal`, or `bug`. Only `full` stays excluded.
2. **A `full` candidate files a QUEUED BOARD ROW, never a staged row.** `commands/wrap.md`
   step 7b calls `bin/board capture "<title> #tags" -b "<notes>" --backlog-file
   <home>/_meta/BACKLOG.md`. The goal draft at `.claude/goals/<slug>.md` is still written and
   the row's notes name it, because that draft is the pointer `/kit:assign` expects.
3. **No new verb.** `board capture` already files a row with the repo's own id prefix and
   mints past both the board file and its git history (`sync_core.next_id` with a path calls
   `history_max_id`, which fetches origin first, best effort, once per repo per process). An
   `add` verb on `lib/board/backlog.sh` would have been a second minting path beside it.
4. **The report closure is `(lane=full, filed: <repo> <ID-NNN>, goal drafted: <path>)`.**
   `lib/wrap/report-lint.sh` accepts `filed:` as a third closure alongside `verified:` and
   `staged`, and REFUSES `lane=full` carrying `staged`.
5. `kit.toml`, `lib/config/module-registry.md`, and `docs/CHANGELOG.md` say the same thing.
   Every `staged: build_lanes excludes <lane>` form is gone, asserted by two `chk_no` cases.

## Green run

- Command: `bash tests/test-wrap.sh`
- Exit: 0
- Output: `test-wrap: all 342 passed` (335 before this change, seven new assertions)
- Verdict: PASS

The seven new assertions inside that run:

| Case | Fixture `**Built:**` value or check | Expected | Got |
|---|---|---|---|
| backfill builds inline | `cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=backfill, verified: bash tests/test-cron.sh, b2c3d4e)` | exit 0 | exit 0 |
| full filed on a board | `... (lane=full, filed: ops-toolkit ID-901, goal drafted: .claude/goals/cron-fire.md)` | exit 0 | exit 0 |
| full closed as staged | `... (lane=full, staged: build_lanes excludes full)` | exit 1, names the board row | exit 1, `closes a full-lane candidate as 'staged'` |
| full staged with a draft | `... (lane=full, staged + goal drafted: .claude/goals/cron-fire.md)` | exit 1 | exit 1 |
| capture wired | `commands/wrap.md` contains `bin/board capture` | present | present |
| exclusion form dropped | `commands/wrap.md` contains `build_lanes excludes` | absent | absent |
| exclusion form dropped | `kit.toml` contains `build_lanes excludes` | absent | absent |

Every pre-existing lane case (`lane=tiny, verified:`, `lane=normal, verified:`,
`lane=bug, verified:`, `lane=normal, staged + goal drafted:`, `lane=normal, staged:
build_candidates off`, a lane with no closure, one bad bullet among good) still passes, which
is the backward-compatibility claim for every lane but `full`.

### The `board capture` reuse, proven against a real board

A throwaway git repo with a `WK`-prefixed board, one live row `WK-12`, and `WK-40` present
only in git history (added in one commit, removed in the next):

```
$ bash bin/board capture "teach digest a --since flag #tooling" \
    -b "intent: reuse dgst ledger; precedent: tools/digest; lane=full; source: wrap 7b" \
    --backlog-file "$d/_meta/BACKLOG.md"
board sync: no [sync] apps configured in .../.kit.toml
filed: WK-41
note: no github spoke configured (or sync skipped); row is on the board
```

The board then reads:

```
| WK-41 | teach digest a --since flag #tooling | intent: reuse dgst ledger; precedent: tools/digest; lane=full; source: wrap 7b | queued |
| WK-12 | an older row | prose | shipped |
```

`WK`, not `ID`: the prefix comes from the board. `41`, not `13`: the mint cleared the
history-only `WK-40`. The row is the kanban shape at `queued`. Nothing else on the board moved.

## Negative control

Produced with `lib/gate/negctl.sh` after the change was committed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/filed:/XXXXX:/g' lib/wrap/report-lint.sh
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation blinds the lint to the `filed:` closure, so the full-lane row that now passes
reads as a lane with no closure. The suite goes red, so the new cases constrain the rule they
name.

## Reproduce

```bash
cd ~/.claude/dwarves-kit
bash tests/test-wrap.sh
KIT_CONFIG_OPERATOR=$(mktemp -d) bash tests/run-all.sh
```

`test-config-registry` fails without `KIT_CONFIG_OPERATOR` pointed at an empty dir: AC9 pins
`KIT_CONFIG_ROOT` but not the operator dir, so the machine's real
`~/.config/dwarves-kit/kit.toml` leaks in. Pre-existing, unrelated to this change, recorded
the same way in `wrap-build-lanes.md`.

## What this does not cover

The lint reads a report. It cannot see whether `board capture` actually ran, whether the id it
reports exists on the named board, or whether the goal draft is at the path claimed. The
`full`-files-a-row rule lives in `commands/wrap.md` prose because the command is the executor
and there is no shell verb between it and the candidate. The lint's half is narrower and
mechanical: `lane=full` may not close as `staged`, and any lane owes some closure.
