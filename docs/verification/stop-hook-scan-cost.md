# Proof of done: SPEC-086 (stop-hook source-file scan cost)

Behavioral change to two Stop hooks. Proof = green suite + falsifiable negative
control + a reproducible CPU benchmark of the fix.

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | Neither Stop hook descends into pruned dirs (`build/` canary absent) | PASS | suite: "slop: prunes build/", "session-state: prunes build/" |
| AC2 | A changed top-level source file is still reported | PASS | suite: "slop: reports a bloated root source file", "session-state: lists a changed source file" |
| AC3 | Outside a git work tree, neither hook scans | PASS | suite: "slop: no scan outside a git work tree", "session-state: no scan outside a git work tree" |
| AC4 | Marker path honors `DWARVES_KIT_SESSION_MARKER`; default unchanged | PASS | hooks read the env var; suite drives the scan via a temp marker, real `/tmp` marker untouched |
| AC5 | `bash tests/test-hooks.sh` green | PASS | 432/432 |

## Implementation

| File | Change |
|---|---|
| `hooks/slop-cleaner.sh` | grep-after-find -> prune-during-traversal; git-work-tree guard; `$MARKER` override |
| `hooks/session-state-save.sh` | same three changes |
| `tests/test-hooks.sh` | +6 assertions (slop-cleaner + new session-state-save section) |
| `docs/specs/SPEC-086-stop-hook-scan-cost.md` | the spec |

`context-readiness.sh` already pruned (the precedent) and fires once per session,
not per turn; left unchanged.

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| Full hook suite | `bash tests/test-hooks.sh` | `Passed: 432 / 432 — All tests passed.` |
| New SPEC-086 assertions | (subset of above) | 6/6 PASS |
| Negative control (falsifiability) | old grep-after vs new prune on a fixture | OLD leaks `./build/canary.py`; NEW excludes it |
| CPU benchmark (the heat fix) | old vs new `find` from a ~25-repo workspace root | 13.09s -> 0.87s system CPU; 4.60s -> 0.45s wall |
| Syntax | `bash -n hooks/{slop-cleaner,session-state-save}.sh` | OK |

## Run detail

Negative control (proves the canary test fails if grep-after-find returns):

```
=== OLD logic (grep-after node_modules|vendor|dist) — canary LEAKS ===
./touched.py
./build/canary.py
=== NEW logic (prune build/) — canary EXCLUDED ===
./touched.py
```

Benchmark (workspace root, ~25 repos + an Obsidian vault), `time`:

```
OLD: 0.55s user 13.09s system 296% cpu  4.600 total
NEW: 0.05s user  0.87s system 205% cpu  0.447 total
```

Live incident signal before the fix: 8 concurrent `find` processes at ~80% CPU,
`load average 13.58` on a 10-core M4. After the runtime patch: load falling,
zero active dwarves-kit `find` scans.

## Reproduce

```sh
cd ~/workspace/tieubao/dwarves-kit
bash -n hooks/slop-cleaner.sh hooks/session-state-save.sh   # syntax
bash tests/test-hooks.sh                                    # 432/432
# negative control: run the OLD pipeline vs the NEW prune over a temp fixture
# with a build/<name>.py newer than the marker; OLD lists it, NEW does not.
```
