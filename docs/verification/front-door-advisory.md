# Verification -- front-door-advisory

`ship-gate.sh` now prints an `[advisory] [front-door]` line when a push changes a path a skill lists in `metadata.front_door` without touching that skill's folder. It calls `lib/gate/front-door-advisory.sh`, which runs `skill-manifest check --base <merge base>` and keeps only the front-door diff class. It never blocks, and stays silent without the binary or without a `front_door` skill.

## Green run

```
Command: REAL_SKILL_MANIFEST=<built skill-manifest> bash tests/test-front-door-advisory.sh
Exit: 0
Output:
  ok - A1 drifted front door warns, names cli/x.go and skill foo
  ok - A2 front door + skill updated together is silent
  ok - A3 clean diff is silent
  ok - A4 SKILL_MANIFEST_BIN missing is silent
  ok - A4b no binary on PATH is silent
  ok - A6 repo with no skills is silent
  ok - A7 other problem classes are not surfaced
  ok - B1 hook prints the advisory and allows the push
  ok - B2 hook is silent on a clean diff
  ok - C1 real skill-manifest drift is warned
  ok - C1b real skill-manifest is silent once the skill moved
  pass=15 fail=0
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time ; bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
  run-all: 52 suites run, 0 skipped for missing tooling (one red: test-meta-docs-registry, FEATURES.md stale; regenerated)
  Passed: 120 / 120   All meta tests passed.
Verdict: PASS
```

## Negative control

```
Command: sed 's/changed since/CHANGED-SINCE-BROKEN/' lib/gate/front-door-advisory.sh; bash tests/test-front-door-advisory.sh
Exit: 1
Output:
  NOT ok - A1 expected a front-door warning, got:
  NOT ok - A5 expected a warning via PATH, got:
  NOT ok - A7b expected 1 drift line, got:
  NOT ok - B1 rc=0 stderr:
  NOT ok - C1 real binary:
  pass=10 fail=5
Verdict: PASS (detection broken -> five cases red; script restored -> 15 of 15 green)
```

## Not proven

- The hook prints on stderr like the other `[advisory]` lines. A PreToolUse hook's stderr on an allowed (exit 0) push does not reach the operator or the model, so the line lands in the hook's output only; the push log gets an `ADVISORY | front-door` row.
- A cold `skill-manifest` wrapper that must `go build` on first run adds that time to the first push.
- Only the default `skills/` folder is scanned; a repo with skills elsewhere gets no advisory.
