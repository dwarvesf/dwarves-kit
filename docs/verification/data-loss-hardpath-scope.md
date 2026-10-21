# Proof of done: a canonical injection literal in a test file is not a data-loss line

## What changed

At the ship-gate only (`KIT_FLOOR_SQLI_CARVEOUT=1`, set by `ship_rule_floor`), the floor's data-loss scan now replaces one literal before its grep chain runs: `"<word>'; DROP TABLE <name>;--"` after the word `in`, in a test file of a known code language, when the line and the file's head image pass every guard in SPEC-412. Any doubt keeps the raw line and prints a fallback note. Each skip and each fallback reaches the push output and `ship-gate.log`. `battery-gate.sh` and `proof-ledger.sh` stay on the raw scan.

## Gate table

| Claim | Evidence |
|---|---|
| the live sample (ops-toolkit #4630) no longer forces the full lane at the ship-gate | real primary flow below, `floor-data-loss-sqli-canonical` |
| production paths, SQL files and unknown languages keep the hit | `floor-data-loss-sqli-paths` |
| an opener on an earlier line (heredoc, triple quote, backtick, Rust raw string, Ruby percent literal) keeps the hit | `floor-data-loss-sqli-crossline` |
| every line guard and every reviewer counterexample keeps the hit | `floor-data-loss-sqli-guards` |
| the span is replaced, never the line | `floor-data-loss-sqli-payload`, NC2b |
| fail closed: unreadable head image, candidate cap, awk failure, failed self-test | `floor-data-loss-sqli-show-fails`, `floor-data-loss-sqli-cap`, `floor-data-loss-sqli-awk-fails` |
| only the ship-gate opts in | `floor-data-loss-sqli-optin` |
| skips and fallbacks are visible with their own labels and counters | `ship-sqli-skip-visible` |
| cost stays flat | `floor-data-loss-sqli-long-line`, `-many-lines`, `-big-head` |
| no regression | AC13 cases below, `run-all --changed` |
| the suite is load-bearing | NC1, NC2, NC2b below |

## Real primary flow

The floor on the real ops-toolkit commit that raised the item (`ce61e16c3`, PR #4630), from this worktree's lib:

```
Command: KIT_FLOOR_SQLI_CARVEOUT=1 bash lib/classify/lane-classify.sh floor <ops-toolkit checkout> ce61e16c3^ ce61e16c3
Exit: 0
Output:
floor-exempt	data-loss	sqli-payload	-	built-in sqli-payload literal	-	tools/vps-mon/scripts/test/test-hb-ack.sh
(stdout empty: no hard-path hit)
Verdict: PASS

Command: bash lib/classify/lane-classify.sh floor <ops-toolkit checkout> ce61e16c3^ ce61e16c3
Exit: 0
Output:
full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh
Verdict: PASS (no flag: the raw scan, as battery-gate and proof-ledger see it)
```

The full hook path (push JSON in, `systemMessage` and `ship-gate.log` out) runs in `ship-sqli-skip-visible`.

## Green run

```
Command: bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-paths floor-data-loss-sqli-crossline floor-data-loss-sqli-show-fails floor-data-loss-sqli-cap floor-data-loss-sqli-optin floor-data-loss-sqli-canonical floor-data-loss-sqli-guards floor-data-loss-sqli-payload floor-data-loss-sqli-tab-path floor-data-loss-sqli-awk-fails ship-sqli-skip-visible floor-data-loss-sqli-long-line floor-data-loss-sqli-many-lines floor-data-loss-sqli-big-head floor-where-boundary floor-plus-line floor-non-ascii floor-exempt-data-loss-still-hits ship-data-loss ship-test-path-skip-visible floor-test-path-notice floor-timing floor-timing-30k
Exit: 0
Output:
PASS floor-data-loss
PASS floor-data-loss-sqli-paths
PASS floor-data-loss-sqli-crossline
PASS floor-data-loss-sqli-show-fails
PASS floor-data-loss-sqli-cap
PASS floor-data-loss-sqli-optin
PASS floor-data-loss-sqli-canonical
PASS floor-data-loss-sqli-guards
PASS floor-data-loss-sqli-payload
PASS floor-data-loss-sqli-tab-path
PASS floor-data-loss-sqli-awk-fails
PASS ship-sqli-skip-visible
PASS floor-data-loss-sqli-long-line (679ms, 168928 bytes)
PASS floor-data-loss-sqli-many-lines (1299ms for 30000 lines)
PASS floor-data-loss-sqli-big-head (851ms, 5888925 bytes)
PASS floor-where-boundary
PASS floor-plus-line
PASS floor-non-ascii
PASS floor-exempt-data-loss-still-hits
PASS ship-data-loss
PASS ship-test-path-skip-visible
PASS floor-test-path-notice
PASS floor-timing (368ms for 1000 paths)
PASS floor-timing-30k (771ms for 30000 paths)
Verdict: PASS

Command: bash tests/test-ceremony-fits-diff.sh floor-data-loss-still-hits-in-comments
Exit: 0
Output:
PASS floor-data-loss-still-hits-in-comments
Verdict: PASS

Command: bash tests/run-all.sh --changed --time   (on commit 76728074)
Exit: 1
Output:
run-all: FAILED -> test-config-registry test-meta-docs-registry test-no-personal-paths
run-all: 57 suites run, 0 skipped for missing tooling
Verdict: 54 suites green. The three failures were registry and doc lints, not behavior: the new env flag had no registry row, docs/FEATURES.md reference counts were stale, and the spec held a home-relative path. Commit f863b829 fixed all three.

Command: for t in test-config-registry test-meta-docs-registry test-no-personal-paths; do bash tests/$t.sh; done   (on commit f863b829)
Exit: 0, 0, 0
Output:
test-config-registry rc=0
test-meta-docs-registry rc=0
test-no-personal-paths rc=0
Verdict: PASS
```

## Negative control

Test command for all three: `bash tests/test-lanes-data.sh floor-data-loss-sqli-canonical floor-data-loss-sqli-payload`, run through `lib/gate/negctl.sh` on the committed tree.

```
NC1
Command: bash lib/gate/negctl.sh "$PWD" "<test command>" "git show origin/master:lib/classify/lane-classify.sh > lib/classify/lane-classify.sh"
Exit: 1 (under mutation, RED expected)
Output:
  FAIL floor-data-loss-sqli-canonical:  [for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do in tools/vps-mon/scripts/test/test-hb-ack.sh should not hit: 'full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh'] [for p in "1'; drop table users;--": pass in tests/t.py should not hit: 'full data-loss: tests/t.py'] [é=1; for b in "x'; DROP TABLE t;--"; do in tests/é.sh should not hit: 'full data-loss: tests/é.sh']
  PASS floor-data-loss-sqli-payload
Restore: git checkout HEAD -- lib/classify/lane-classify.sh, Exit: 0 (green after restore)
Verdict: PASS

NC2 (pass B replaces the whole line instead of the span)
Command: bash lib/gate/negctl.sh "$PWD" "<test command>" "bash nc2-mutate.sh"
Exit: 1 (under mutation, RED expected)
Output:
  FAIL floor-data-loss-sqli-canonical: (the same three rows hit: the self-test caught the mutation and kept the raw scan)
  PASS floor-data-loss-sqli-payload
Restore: Exit: 0 (green after restore)
Verdict: PASS

NC2b (the NC2 mutation plus the self-test stop removed)
Command: bash lib/gate/negctl.sh "$PWD" "<test command>" "bash nc2b-mutate.sh"
Exit: 1 (under mutation, RED expected)
Output:
  PASS floor-data-loss-sqli-canonical
  FAIL floor-data-loss-sqli-payload: got ''
Restore: git checkout HEAD -- lib/classify/lane-classify.sh, Exit: 0 (green after restore)
Verdict: PASS
```

`nc2-mutate.sh` swaps `c = pre "\"sqli-payload\"" substr(c, RSTART + RLENGTH)` for `c = "\"sqli-payload\""` in pass B. `nc2b-mutate.sh` does the same and replaces `_floor_sqli_note "self-test failed"; return 0` with `:`. Each run restored the file; `git status` was clean after.

## Not proven

- A deliberate test-file author can still hide one destructive string (SPEC-412 DEC-7): an ordinary quoted string spanning lines in shell or Ruby, or a value reused from an `in` loop. No test claims otherwise.
- The 5 s G9 time budget has no forcing test; the cap and the unreadable-image paths cover the same fallback code.
- The full `run-all --all` glob was not run (nightly job, per AGENTS.md).
