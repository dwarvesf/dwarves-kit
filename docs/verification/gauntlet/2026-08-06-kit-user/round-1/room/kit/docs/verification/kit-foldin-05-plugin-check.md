# Verification: kit-foldin SG-05, plugin-check

Proof of done for porting `ops-toolkit/tools/cc-plugin-check/` to
`dwarves-kit/tools/plugin-check/`. Work-type: spec-feature / behavioral (a CLI tool). The
canonical mega-goal proof narrative lives at `docs/proof/kit-foldin-plugin-check.md`; this
file is the kit ship-gate artifact (green run + negative control + reproduce).

## 1. Green, captured

The real primary flow is the freshness verdict over a plugin state dir, exercised by the
tool's own hermetic suite (stubbed `claude`, real micro-git repos backing the sha compare;
27 assertions covering every verdict path). The fresh/stale run-table (the named NC for
this sub-goal) is assertions [3] (fresh -> `current`) and [4] (stale -> `OUTDATED`).

```
Command: cd tools/plugin-check && bash tests/smoke.sh
Exit: 0
Verdict: PASS

  [3] status: ponytail (single-plugin mp, clone HEAD == installed sha) shows current (AC2)
    ok: ponytail current (sha proven)
  [4] status (AC3 negative control): superpowers pinned-old in fixture -> OUTDATED
    ok: OUTDATED row present for pinned-old superpowers
  ...
  smoke: all 27 passed
```

## 2. Negative control (revert -> RED -> restore)

To prove the green is not trivially green, staleness detection was disabled in
`bin/plugin-check` (the `OUTDATED` verdict branch was replaced with `current`), the suite
re-run, then the change reverted.

```
Command (broken): replace `echo -e "OUTDATED\tsha differs from upstream"` with `echo -e "current\t"` in verdict(), then bash tests/smoke.sh
Exit: 1
Verdict: RED (expected)

  [4] status (AC3 negative control): superpowers pinned-old in fixture -> OUTDATED
    FAIL: AC3 OUTDATED missing
  smoke: 23 passed, 4 FAILED
```

The stale-fixture assertion [4] flips to FAIL the moment the verdict logic stops
distinguishing stale from fresh, so the green run genuinely exercises staleness detection.

```
Command (restored): git checkout -- tools/plugin-check/bin/plugin-check && bash tests/smoke.sh
Exit: 0
Verdict: PASS (smoke: all 27 passed); working tree identical to HEAD (git status clean)
```

## 3. Reproduce

```bash
cd dwarves-kit/tools/plugin-check
bash tests/smoke.sh          # 27/27, includes the fresh [3] + stale [4] run-table
```

## Done-gate: no hardcoded ops path

```
Command: grep -rn 'workspace/tieubao' tools/plugin-check/
Exit: 1 (no matches)
Verdict: PASS
```
