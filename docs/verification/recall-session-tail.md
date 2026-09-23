# Verification: session recall --tail (SPEC-309)

`session recall --tail <prefix>` prints one session's recent prompts and replies, with its last-turn time and last-write age, so an operator can see what a peer session is doing before acting.

Headless CLI change: the capture is the text output below, no image capture. Transcript text is not reproduced here; the real-run rows record exit codes and line counts only.

## Green run

| Check | Command | Exit | Output |
|---|---|---|---|
| Recall suite | `python3 -m unittest lib/session/recall/tests/test_recall.py` | 0 | `Ran 36 tests`, OK (AC1 to AC8, incl. the byte diff of query and `--sessions` output against `origin/master`) |
| Parser smoke | `bash lib/session/tests/test-parse-transcript.sh` | 0 | all 7 passed (`parse_lines` shared by `load` and the chunk reader) |
| Shared pattern pin | `bash tests/test-precedent.sh` | 0 | 82/82 passed (`SECRET_SHAPE_RE` byte-equal to `lib/precedent/inventory.py`) |
| Forwarder | `bash tests/test-bin-forwarders.sh` | 0 | all 48 passed |
| Changed suites | `RUN_ALL_TIMEOUT_SECS=600 bash tests/run-all.sh --changed` | 0 | all 33 suites passed |

## Real run

On the operator's machine, 2026-09-23, against live transcripts under `~/.claude/projects` (313 project dirs):

| Case | Command | Exit | Output |
|---|---|---|---|
| Live peer in another session, default sweep | `session recall --tail 5ae3f7a2` | 0 | 13 lines: header, DATA marker, 10 turns, footer; 11 MB transcript, 0.04 s |
| Own session, slash command visible | `session recall --tail cf651279 --limit 40` | 0 | one `user  /kit:wrap distill` line |
| Unknown prefix | `session recall --tail zzzzzz` | 1 | 112-byte message naming the dir count (was 27 KB before the review fix) |
| Ambiguous prefix | `session recall --tail 5` | 2 | 443-byte message, 10 ids then `... and <N> more` |
| JSON beside tail | `session recall --tail 5ae3 --json` | 2 | usage |

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "python3 -m unittest lib/session/recall/tests/test_recall.py" "git show origin/master:lib/session/recall/session_recall.py > lib/session/recall/session_recall.py"
Exit: 0 (green before mutation)
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/recall/session_recall.py
Exit: 0 (green after restore)
Verdict: PASS
```

The review team also mutated in temp copies: redaction moved after the cap leaked a `ghp_` token (straddle test RED); the CLI stdout write removed stayed green before the fix round, which added the subprocess test.

## Gates

| Phase | Verdict |
|---|---|
| Validate | NEEDS REVISION, 2 critical and 10 warnings, all folded into the spec |
| Design critique | REVISE, 10 findings; finding 7 declined (see implementation notes) |
| Review (review-team) | FIX THEN SHIP, 12 findings; 11 fixed in `230e3a6`, the proof (this file) closes the 12th |

## Not proven

- Secret shapes outside `SECRET_SHAPE_RE` plus `TAIL_EXTRA_SECRET_RE` still print. The two lists are fixed patterns, not a scanner.
- "Last write" can be fresh while the session is idle (a hook write) or stale while it works (a long tool call outside `subagents/`). The output calls it a hint.
- Timestamps with an explicit non-`Z` offset print `--:--`; none were seen in real transcripts.
