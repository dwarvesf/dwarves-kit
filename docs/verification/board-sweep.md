# Proof of done: `board sweep`, `board sweep verify`, `board mirror-cleanup`

An operator with many boards on one host ran a private sweeper around the kit's per-repo `board sync`: the registry loop, the publish gate, the origin-fed Hermes mirror, a change-only digest with its poster, a no-write verifier, and a card-cleanup tool. Everything in it was generic except where it posts and how the host authenticates. This change moves the generic parts into the kit as three verbs and leaves two seams: a `--poster` command and the `--preflight` and `--on-clean` hooks. The operator's tool shrinks to config and one poster adapter.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-board-digest.sh` | 0 | PASS 63/63 (parse grammar, merge, flapping, carry-forward, field cap, ticket links, clusters, state lock) |
| 2 | `bash tests/test-board-sweep-post.sh` | 0 | PASS 32/32 (poster contract, redaction, 0600 state, carried reason, embed budget) |
| 3 | `bash tests/test-board-sweep.sh` | 0 | PASS 55/55 (loop, hooks, token handoff, publish gate, poster wiring, dry run) |
| 4 | `bash tests/test-board-sweep-mirror.sh` | 0 | PASS 43/43 (origin-fed registry, unresolved-repo gate, kill-safe cleanup) |
| 5 | `bash tests/test-board-sweep-verify.sh` | 0 | PASS 29/29 (byte-identical proof, damage detection, last-tick reader) |
| 6 | `bash tests/test-board-mirror-cleanup.sh` | 0 | PASS 31/31 (classes a to e, idempotent apply, rule list) |
| 7 | `bash tests/run-all.sh --only test-board` and `--only test-sync` | 0 | every existing board and sync suite still green |
| 8 | `/bin/bash -n` on every new script, digest exercised under Apple bash 3.2 | 0 | PASS |

## Negative control

Each fault was injected into the committed code, the suite re-run, and the file restored from the commit.

| Fault injected | Suite | Result |
|---|---|---|
| `unset BOARD_SWEEP_TOKEN` removed from `board-sweep` | `test-board-sweep.sh` | 2 FAIL (the token reached a child; publish saw it) |
| mirror gate `[ -s "$MIRROR_FAILED" ]` replaced by `false` | `test-board-sweep-mirror.sh` | 2 FAIL (no tick-skip line; `board mirror` ran with an unresolved repo) |
| `valid_rail` made always true in `board-digest.sh` | `test-board-digest.sh` | 1 FAIL (a rail outside the map was accepted) |

## Parity with the private sweeper

The old sweeper ran against live boards, a live Hermes store, and live spoke state in dry-run, then the new `board sweep` ran the same way. Same registry, same starting digest state, same `board` shim recording every call, poster stubs standing in for the rails.

| Check | Result |
|---|---|
| Every `board sync` and `board mirror` call: cwd, argv, token and askpass presence, Hermes home, Notion pin, the rewritten mirror registry | identical across all calls |
| Whole sweep log, planned writes and digest log lines included | identical except the three tail lines that a dry run changes by design |
| Digest payload, 15 cluster comparisons over 5 scenarios (live capture, a recorded fixture with an adopted incident and a long title, flapping, carry-forward, field cap) | identical, byte for byte, through the operator's poster adapter |
| Bytes handed to the rail stubs (argv, headers, HMAC signature, body) | identical |
| `board mirror-cleanup` against the live store, four modes | identical output and exit code |

The harness has its own negative control: dropping `--crit-prefix` on the new side turned one payload from `crit` to `info` and the comparison reported the difference.

## Reproduce

```bash
bash tests/run-all.sh --only test-board
bash tests/run-all.sh --only test-sync
```

## What did not move

The chat service, the credentials, the host bootstrap, the list of checkouts that must be kept fresh, the heartbeat, and the names of the bots whose Hermes cards the mirror never owns stay with the operator. They reach the kit as the `--poster`, `--preflight` and `--on-clean` commands, the `--repo-arg` and `--sync-token-repo` flags, and a `--kinds-file` rule list.
