# Verification -- board sweep, board sweep verify, board mirror-cleanup

An operator with many boards on one host ran a private sweeper around the kit's per-repo `board sync`: the registry loop, the publish gate, the origin-fed Hermes mirror, a change-only digest with its poster, a no-write verifier, and a card-cleanup tool. Everything in it was generic except where it posts and how the host authenticates. This change moves the generic parts into the kit as three verbs and leaves two seams: a `--poster` command and the `--preflight` and `--on-clean` hooks. The operator's tool shrinks to config and one poster adapter.

## Gate table

| Claim | Evidence |
|---|---|
| the digest parses every `describe()` line kind, dedupes, tracks flapping, and carries a failed post forward | digest run below |
| the poster contract holds: exit 0 is delivered, stderr is the redacted reason, state is 0600 | poster run below |
| the sweep loop, hooks, token handoff, publish gate, and dry run behave | sweep run below |
| the mirror leg reads origin and refuses a tick with an unresolved repo | mirror run below |
| the verifier proves a sweep wrote no board, and reads the newest tick | verify run below |
| the cleanup classifies, archives, and never deletes | cleanup run below |
| nothing else in board or sync regressed | board and sync suites below |
| the guards are load-bearing | negative controls below |
| the new engine does what the private sweeper did, on live data | parity section below |

## Green run

```
Command: bash tests/test-board-digest.sh
Exit: 0
Output:
case rc-passthrough (the digest never signals a data problem through its exit code):
  ok   unmapped/bad-rail/unknown-line/corrupt-state all exit 0
PASS=63 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-board-sweep-post.sh
Exit: 0
Output:
case usage (missing flags are a usage error, 64):
  ok   no --cluster -> 64
  ok   no --poster (and no --dry-run) -> 64
PASS=32 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-board-sweep.sh
Exit: 0
Output:
case usage (bad invocations):
  ok   no --registry -> 64
  ok   missing registry file -> 2
  ok   unknown flag -> 64
  ok   --help prints the usage
PASS=55 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-board-sweep-mirror.sh
Exit: 0
Output:
case trap (a killed run still moves every temp artifact out of the repo root):
  ok   trap block extracted
  ok   SIGTERM handler exits 143 (killed, not swallowed)
  ok   trap moved the per-repo snapshot into the discard dir
  ok   trap left nothing behind at the repo root
PASS=43 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-board-sweep-verify.sh
Exit: 0
Output:
ok   a sweep that writes back is DAMAGE
ok   a damaging sweep exits 1
ok   --no-run with no sweep between snapshots is VERIFIED
ok   no --run and no --no-run is refused
29 ok lines, 0 FAIL
Verdict: PASS
```

```
Command: bash tests/test-board-mirror-cleanup.sh
Exit: 0
Output:
  ok   first matching rule wins: a decomposer child on the chatter board is a decomposer-child
  ok   no --kinds-file: only the decomposer rule is built in
  ok   a malformed --kinds-file fails loudly
  TOTAL: 31   PASS: 31   FAIL: 0
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only test-board --time
Exit: 0
Output:
run-all: 19 suites, 4 at a time, 0 serial
test-board-digest                              ok (13s)
test-board-mirror-cleanup                      ok (3s)
test-board-sweep-mirror                        ok (2s)
test-board-sweep-post                          ok (6s)
test-board-sweep-verify                        ok (1s)
test-board-sweep                               ok (6s)
test-board-publish                             ok (2s)
test-board-mirror                              ok (14s)
run-all: all 19 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only test-sync --time
Exit: 0
Output:
test-sync-cron-install                         ok (1s)
test-sync-cron-launcher                        ok (0s)
test-sync-dispatch                             ok (2s)
test-sync                                      ok (2s)
run-all: all 4 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

Each fault was injected into the committed code, the suite re-run, and the file restored with `git checkout --`.

```
Command: bash tests/test-board-sweep.sh, with `unset BOARD_SWEEP_TOKEN` removed from lib/sync/sweep/board-sweep
Exit: 1
Output:
  FAIL BOARD_SWEEP_TOKEN itself reached a child
  FAIL publish env:   env [r-alpha/publish] GH_TOKEN=UNSET GIT_ASKPASS=board-git-askpass GIT_TOKEN=tok-123 SWEEP_TOKEN=tok-123 PROMPT=0
PASS=53 FAIL=2
Verdict: RED as expected
```

```
Command: bash tests/test-board-sweep-mirror.sh, with the mirror gate `[ -s "$MIRROR_FAILED" ]` replaced by `false`
Exit: 1
Output:
  FAIL no tick-skip summary line: [2026-10-05 13:39:25] board-sweep: start
  FAIL board mirror was invoked despite an unresolved repo (would archive its live cards)
PASS=41 FAIL=2
Verdict: RED as expected
```

```
Command: bash tests/test-board-digest.sh, with `valid_rail` made always true in lib/sync/sweep/board-digest.sh
Exit: 1
Output:
  FAIL no ERROR(no rail line for bad rail
PASS=62 FAIL=1
Verdict: RED as expected
```

All three files were restored from the commit and the suites re-run green (rows above).

## Parity with the private sweeper

The old sweeper ran against live boards, a live Hermes store, and live spoke state in dry-run, then the new `board sweep` ran the same way. Same registry, same starting digest state, a `board` shim that records every call and forces dry-run, and stubs standing in for the rails. The harness lives with the operator's tool, where the old sweeper's source is.

```
Command: compare the two runs' recorded calls, their sweep logs, and the bytes each handed to the rail stubs
Exit: 0
Output:
CALLS IDENTICAL: 20 calls (19 sync, 1 mirror)
sweep log: 645 of 646 lines identical, the 3 tail lines differ by design (the old run posted to a stub, the dry run prints the payload)
digest: 15 cluster comparisons over 5 scenarios, same=15 diff=0
POSTED BYTES IDENTICAL (curl argv, headers, HMAC signature, body): 574 bytes
mirror-cleanup, 4 modes against the live store: same
Verdict: PASS
```

```
Command: the same digest comparison with --crit-prefix dropped on the new side
Exit: 1
Output:
NC ok: broken input is caught
  old severity=crit  new severity=info
Verdict: RED as expected
```

## Not proven

- The publish leg was not exercised live: the parity tick wrote no board, so nothing triggered it. The gate and the token handoff are covered by `tests/test-board-sweep.sh` only.
- No sweep ran under launchd from this branch, and the live schedule is unchanged.
- The state lock uses `lockf` on macOS and `flock` on Linux; only the macOS path ran here. With neither, the write is unguarded.
- `tests/test-config-registry.sh` shows two failures on `master` as well (orphan-env drift lint, root-only key count); this change touches neither (the lint's seed prefixes do not include `BOARD_`).
