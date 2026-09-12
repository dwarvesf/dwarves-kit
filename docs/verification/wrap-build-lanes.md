# wrap.build_lanes: step 7b builds the lanes the operator lists

`/kit:wrap` step 7b hardcoded one buildable lane. `tiny` built inline; `normal`, `full`, `bug`,
and `backfill` staged a row and drafted a goal. The staging side has no consumer: one operator
board holds 248 rows staged since May and none has ever drained. A normal-lane enhancement is
usually one worker and one test away from done, so the drafting cost bought nothing.

## The change

`wrap.build_lanes`, a space-separated list of the lanes step 7b builds INLINE. Default `"tiny"`,
which is the behavior before the key existed, byte-identical for an adopter who edits nothing.

1. `kit.toml` gains the key under `[wrap]` next to `build_candidates`, `[impl]` scoped.
2. `commands/wrap.md` reads it with `kit_config_get_root wrap.build_lanes "tiny"` in the step -1
   config block, and step 7b's sizing paragraph splits on the list rather than on `tiny`.
3. An inline build of a non-`tiny` lane carries the guards the lane would owe elsewhere: a
   worktree at `<home>/.claude/worktrees/<slug>` on its own branch, never the default branch; a
   dispatched worker (Sonnet default, Opus for security, money, or a data model); one quoted
   verification command; a PR left for step 3's own-PR path, which merges only green. The home
   repo's ship-gate proof still applies and wrap never overrides it.
4. `full` and `backfill` never build inline even when listed. They owe a spec or a root-cause
   record. Wrap stages them and reports `(lane=<lane>, staged: build_lanes excludes <lane>)`.
5. `lib/wrap/report-lint.sh` accepts `verified:` on any lane, keeps the two existing `staged`
   forms, accepts the new exclusion form, and now REQUIRES a closure: an item naming a lane owes
   `verified:` or a `staged` form. A lane token alone says the candidate was sized and nothing
   about what became of it.
6. `lib/config/module-registry.md` gains the row and the root-only table entry, which
   `tests/test-config-registry.sh` AC10 asserts equals the real `kit_config_get_root` call sites.

## Green run

- Command: `bash tests/test-wrap.sh`
- Exit: 0
- Output: `test-wrap: all 335 passed (326 before this change, nine new assertions)`
- Verdict: PASS

The nine new assertions inside that run:

| Case | Fixture `**Built:**` value | Expected | Got |
|---|---|---|---|
| normal built inline | `wake-probe ENHANCE tools/alert-triage: ... (lane=normal, verified: bash tests/test-alert.sh, #418)` | exit 0 | exit 0 |
| bug built inline | `cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=bug, verified: bash tests/test-cron.sh, a1b2c3d)` | exit 0 | exit 0 |
| lane excluded | `cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, staged: build_lanes excludes full)` | exit 0 | exit 0 |
| lane with no closure | `cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal)` | exit 1, names the missing closure | exit 1, `names a lane with no closure` |
| one bad bullet among good | bullet 1 `lane=normal, verified: ...`, bullet 2 `lane=bug` alone | exit 1, names `item 2` | exit 1, `item 2` |
| knob wired | `commands/wrap.md` contains `kit_config_get_root wrap.build_lanes` | present | present |
| default shipped | `kit.toml` contains `build_lanes = "tiny"` | present | present |

The pre-existing lane cases (`lane=tiny, verified:`, `lane=normal, staged + goal drafted:`,
`lane=normal, staged: build_candidates off`, and a suffix with no `ENHANCE`/`NEW` token) still
pass unchanged, which is the backward-compatibility claim.

- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output: `ok` (via `tests/run-all.sh`, line `test-meta ok`)
- Verdict: PASS

- Command: `bash tests/run-all.sh`
- Exit: 1
- Output: `run-all: 138 suites run, 1 skipped for missing tooling`, with
  `run-all: FAILED -> test-config-registry` and
  `run-all: TIMED OUT at 300s -> test-orchestrate-wavefront`
- Verdict: PASS with two explained anomalies, neither caused by this change:
  - `test-config-registry` fails on `wrap.drain_staged ships as false` and
    `wrap.drain_staged ignores a project .kit.toml`. AC9 pins `KIT_CONFIG_ROOT` on the
    default probe but not `KIT_CONFIG_OPERATOR`, so the machine's real
    `~/.config/dwarves-kit/kit.toml` (which sets `drain_staged = true`) leaks in. Re-run with
    a neutral operator dir: `KIT_CONFIG_OPERATOR=$(mktemp -d) bash tests/test-config-registry.sh`
    gives `=== 50/50 passed ===`. Ambient machine config, pre-existing, no `build_lanes` row
    is in AC9's key list.
  - `test-orchestrate-wavefront` hit the runner's 300s ceiling, which run-all itself says is
    not an assertion failure. Standalone: `bash tests/test-orchestrate-wavefront.sh` exits 0
    with `ALL PASS` and zero `FAIL` lines.

## Negative control

Produced with `lib/gate/negctl.sh` after the change was committed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: perl -pi -e "s/lane=\[a-z\]\+/lane=ZZZZZZ/" lib/wrap/report-lint.sh
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation blinds the lane detector, so an item carrying `lane=normal` and nothing else lints
clean. The suite goes red, so the new cases constrain the rule they name.

## Reproduce

```bash
cd ~/.claude/dwarves-kit
bash tests/test-wrap.sh
KIT_CONFIG_OPERATOR=$(mktemp -d) bash tests/test-config-registry.sh
bash tests/test-orchestrate-wavefront.sh
```

## What this does not cover

The lint reads a report. It cannot see whether the build actually ran in a worktree, whether the
PR exists, or whether the operator's `build_lanes` value contains a lane the classifier can
return. A typo like `build_lanes = "tny"` silently stages everything, which is the safe
direction and the reason it is not validated. The `full`/`backfill` exclusion lives in
`commands/wrap.md` prose, not in code, for the same reason the whole step lives there: the
command is the executor and there is no shell verb between it and the build.
