# Verification log: finishing the `lib/` scattered-id strip, zone 8 registered

Branch `chore/ids-lib`, base `c7f4d78`.

Board row ID-837. `bash bin/lint --zone lib --count` was 488 on this branch's base (about 478
at the row's filing, drift from unrelated commits landing in between); after this branch it is
0, and `tests/test-no-scattered-ids.sh` now enforces it as zone 8, alongside hooks/bin/skills.

The strip touched 75 files under `lib/`: comments, docstrings, help text, and one free-text
ledger reason string. Every hit followed one of three shapes per CONTRIBUTING.md's "Where an
ID may appear": the id was dropped and the reason kept; the whole citation was dropped when it
was pure decoration; or, for a genuine file pointer, the id was dropped and the file path kept.

## Green run

Command: `bash lib/lint/scattered-ids.sh --zone lib --count`
Exit: 0
Output: `0`
Verdict: PASS

Command: `bash tests/test-no-scattered-ids.sh`
Exit: 0
Output (excerpt): `PASS no scattered id in lib` (Zone 8); `test-no-scattered-ids: all 7 passed`
Verdict: PASS

Full suite run alongside (all green, `48/50` and `2/3` are pre-existing/environment gaps
confirmed below, not caused by this branch):

```
bash tests/test-meta.sh                              -> 852/852 passed
bats tests/test-queue.bats                           -> 24/24 passed
bash tests/test-stats-no-persist.sh                  -> 2 passed, 0 failed, 1 skipped (needs uv sync locally)
bash tests/test-gate-ledger-history.sh                -> 9/9 passed
bash tests/test-gate-ledger-report.sh                 -> 8/8 passed
bash tests/test-gate-outcome.sh                       -> 25/25 passed
bash tests/test-gate-vocab-recording.sh               -> 20/20 passed
bash tests/test-money-gate.sh                         -> 16/16 passed
bash tests/test-orchestrate-gate-dispatch.sh          -> ALL PASS
bash tests/test-quiz-gate.sh                          -> 33/33 passed
bash tests/test-redteam-gate.sh                       -> 40/40 passed
bash tests/test-ship-gate-coverage-map.sh             -> 10/10 passed
bash tests/test-ship-gate-fail-closed.sh              -> 5/5 passed
bash tests/test-ship-gate-profiles.sh                 -> ALL PASS
bash tests/test-boundary-lint.sh                      -> 5/5 passed
bash tests/test-mutation-smoke.sh                     -> 32/32 passed
bash tests/test-proof-table-gen.sh                    -> 25/25 passed
bash tests/test-proof-dir-layout.sh                   -> 3/3 passed
bash tests/test-proof-negctl.sh                       -> 16/16 passed
bash tests/test-proof-override-order.sh               -> 5/5 passed
bash tests/test-mega.sh                               -> 18/18 passed
bash tests/test-mega-merge.sh                         -> 30/30 passed
bash tests/test-mega-review.sh                        -> 26/26 passed
bash tests/test-mega-reconcile.sh                     -> 35/35 passed
bash tests/test-mega-report.sh                        -> 17/17 passed
bash tests/test-runs-dashboard.sh                     -> 21/21 passed
bash tests/test-goal-dispatch.sh                      -> 20/20 passed
bash tests/test-reflect-drain.sh                      -> 23/23 passed
bash tests/test-reflect-propose.sh                    -> 48/48 passed
bash tests/test-reflect-propose-precision.sh          -> 5/5 passed
bash tests/test-lane-classify.sh                      -> 32/32 passed
bash tests/test-lane-telemetry.sh                     -> 29/29 passed
bash tests/test-role-classify.sh                      -> 24/24 passed
bash tests/test-significance-classify.sh              -> 25/25 passed
bash tests/test-classify-md-inert.sh                  -> 4/4 passed
bats tests/test-sync.sh                               -> 264/264 passed
bash tests/test-sync-dispatch.sh                      -> 5/5 passed
bash tests/test-sync-cron-install.sh                  -> 29/29 passed
bash tests/test-sync-cron-launcher.sh                 -> 14/14 passed
bash tests/test-board.sh                              -> 48/49 (1 pre-existing skip)
bash tests/test-board-mirror.sh                       -> 76/76 passed
bash tests/test-board-writeback.sh                    -> 53/54 (1 pre-existing skip)
bash tests/test-board-set-note.sh                     -> ALL PASS
bash tests/test-board-promote.sh                      -> 29/29 passed
bash tests/test-board-publish.sh                      -> ALL PASS
bash tests/test-precedent.sh                          -> 69/69 passed
bash tests/test-config.sh                             -> selftest PASS
bash tests/test-config-registry.sh                    -> 48/50 (2 pre-existing failures, confirmed below)
bash tests/test-config-seams.sh                       -> 53/53 passed
bash tests/test-config-stamp.sh                       -> 17/17 passed
bash tests/test-reserved-config-guard.sh              -> 9/9 passed
bash tests/test-spec-index.sh                         -> 9/9 passed
bash tests/test-onboard-detect.sh                      -> 19/19 passed
bash tests/test-orchestrate.sh                        -> ALL PASS
bash tests/test-token-capture.sh                      -> ALL PASS
bash tests/test-wave-token-capture.sh                 -> ALL PASS
bash tests/test-watchdog-token-capture.sh             -> ALL PASS
```

`test-config-registry.sh`'s two `wrap.drain_staged` failures were reproduced against a clean
`origin/master` worktree with none of this branch's changes: same two FAILs, same 48/50. Not
caused by this branch; pre-existing.

## Negative control

Command: planted `# NEGATIVE-CONTROL-PLANT SPEC-999 marker for zone-8 verification` as the new
first line of `lib/gate/gate-ledger.sh`, then ran `bash tests/test-no-scattered-ids.sh`.
Exit: 1
Output (excerpt): `FAIL 1 hit(s) in lib; see lib/lint/README.md for the exemption list`,
naming `lib/gate/gate-ledger.sh:1` and the planted text.
Verdict: RED-as-expected.

Restore: removed the planted line. Re-ran `bash tests/test-no-scattered-ids.sh`.
Exit: 0
Output: `test-no-scattered-ids: all 7 passed`
Verdict: PASS, restored clean.

## A lint gap found and fixed along the way

Three files end in a bottom-of-file provenance footer using shell/python comment syntax
(`# provenance: SPEC-XXX, ...`) rather than the markdown `<!-- provenance: ... -->` shape
CONTRIBUTING.md's example shows. The enumerator's exemption only recognized the HTML-comment
form, so these three read as false-positive hits: `lib/board/board-mirror.sh`,
`lib/board/board.sh`, `lib/precedent/precedent.sh`. Extended `lib/lint/scattered-ids.sh`'s
`is_exempt()` (and `lib/lint/README.md`) to also match `^#\s*provenance:`, the same clause-3
footer, just in a language with no HTML-comment syntax. No new exemption was invented for a
shape that was not already sanctioned; this only teaches the tool to recognize a shape it
should have all along.

## Exclusions

None. Every scattered id in the `lib` zone was either rewritten in place (comment/docstring/
help-text prose) or was a provenance footer now correctly exempted above. No load-bearing
data string (a ledger marker, an event name, a filename another module parses) was left with
an id inside it, because none needed one: the sole free-text data string touched
(`quiz-gate.sh`'s debt-response reason, `"SG-04 quiz-gate nudge..."` -> `"quiz-gate nudge..."`)
is documented as free text in `gate-ledger.sh`'s own header and is not matched, parsed, or
asserted on by any test (confirmed by grep across `tests/`).

## Deliberately not done

Zones 6 (`agents/*.md`) and 7 (`commands/*.md`) are a sibling worker's scope and are not
registered by this branch.
