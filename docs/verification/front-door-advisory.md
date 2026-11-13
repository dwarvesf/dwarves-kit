# Verification -- front-door-advisory

`ship-gate.sh` now reports a skill front-door drift: a push that changes a path a skill lists in `metadata.front_door` without touching that skill's folder. `lib/gate/front-door-advisory.sh` runs `skill-manifest check --base <merge base>`, bounded at `FRONT_DOOR_TIMEOUT_S` (default 5), and keeps only the front-door diff class. The hook calls it from `_floor_check`, after every blocking check, only when the pushed commit is HEAD, and the lines ride the exit-0 `systemMessage` (framed as data, cut at 300 chars). It never blocks, and stays silent without the binary or without a `front_door` skill.

## Green run

```
Command: REAL_SKILL_MANIFEST=<built skill-manifest> PATH=/bin:/usr/bin:$PATH /bin/bash tests/test-front-door-advisory.sh
Exit: 0
Output:
  ok - A1 drifted front door warns, names cli/x.go and skill foo
  ok - A3 clean diff is silent
  ok - A4 SKILL_MANIFEST_BIN missing is silent
  ok - B1 hook relays the advisory in the systemMessage and allows the push
  ok - B2 hook is silent on a clean diff
  ok - B3 hanging binary is cut after 1s (took 1s), silent, exit 0
  ok - B3b hook with a hanging binary returns in 2s, allows the push
  ok - B3c default cap keeps the hook under the 30s budget (took 5s)
  ok - B4 DO NOT SHIP verdict still blocks (rc=2), advisory absent
  ok - B4b missing full-lane gates still block (rc=2), advisory absent
  ok - B5 pushing a ref other than HEAD is silent
  ok - B6 long path is cut at 300 chars (longest line 300)
  ok - C1 real skill-manifest drift is warned
  pass=22 fail=0
Verdict: PASS
```

The same file passes 22 of 22 under the default `bash` and under Apple `/bin/bash` 3.2.57 (hook and script both run by 3.2 in the second run).

```
Command: bash tests/test-codex-hooks.sh ; bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
  94 passed, 0 failed
  Passed: 120 / 120   All meta tests passed.
Verdict: PASS
```

## Negative control

```
Command: replace the watchdog (sleep "$secs"; kill "$pid") with (sleep 0; true) in lib/gate/front-door-advisory.sh; bash tests/test-front-door-advisory.sh
Exit: 1
Output:
  NOT ok - B3 rc=0 took 25s out:
  NOT ok - B3b rc=0 took 26s out:  err:
  NOT ok - B3c rc=0 took 25s
  pass=19 fail=3
Verdict: PASS (timeout removed -> the hanging stub holds the hook 25s and three cases go red; restored -> 22 of 22)
```

Earlier control, kept: breaking the detection string turned A1, A5, A7b, B1 and C1 red (`pass=10 fail=5` at the time); restored, green.

## Not proven

- The advisory is evaluated only on pushes that pass every blocking check, so a blocked push never shows it (B4, B4b assert rc=2 and no advisory).
- Whether the harness surfaces a PreToolUse `systemMessage` on an allowed push is the same mechanism `_floor_check` already relies on; not re-proven here.
- A killed `skill-manifest` wrapper can leave its `go build` child running to completion in the background; it holds no hook pipe.
- Only the default `skills/` folder is scanned; a repo with skills elsewhere gets no advisory.
