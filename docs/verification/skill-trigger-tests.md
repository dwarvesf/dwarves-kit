# Verification: stats skill trigger phrases

| Item | Result |
|---|---|
| Cause | #700 trimmed `skills/stats/SKILL.md` description to 400 chars and moved 4 phrases to the body |
| Fix | Description rewritten (356 chars) to carry telemetry, understanding debt, kit runs, render the ledger |
| Tests unchanged | `lib/stats/tests/test-render-skill.sh`, `lib/stats/tests/test-docs-wiring.sh` |

| Check | Command | Result |
|---|---|---|
| Render skill | `cd lib/stats && bash tests/test-render-skill.sh` | 30 passed, 0 failed |
| Docs wiring | `cd lib/stats && bash tests/test-docs-wiring.sh` | PASS=18 FAIL=0 |
| 400-char cap | `bash tests/test-command-triggers.sh` | 12/12 (stats is 356 chars) |
| Structure | `bash tests/test-meta.sh` | no FAIL lines |

| Negative control | Result |
|---|---|
| `git checkout HEAD~1 -- skills/stats/SKILL.md` | render-skill red on `telemetry`; docs-wiring red on the other 3 phrases (3 FAIL) |
| `git checkout HEAD -- skills/stats/SKILL.md` | restored, tree clean |
