# Proof of done: session recall --subagents

Change: `session recall --subagents PREFIX [filter]` lists a session's subagent transcripts (time, description, jsonl path), so `--final <path>` can read one report without a hand-written jq over `subagents/*.meta.json`.

| Check | Command | Result | Verdict |
|---|---|---|---|
| Unit tests | `bash tests/test-session-recall.sh` | `PASS: session-recall` | PASS |
| Full suite | `bash tests/run-all.sh` | `run-all: all 22 suites passed, 0 skipped for missing tooling` | PASS |
| Real primary flow | `python3 lib/session/recall/session_recall.py --subagents 988d6aae 'r2 reviewer 3'` against a real session with 44 subagents | two matching rows printed, `SPEC-260 r2 Reviewer 3` and `SPEC-154 r2 Reviewer 3`, each with its jsonl path | PASS |
| Negative control | `lib/gate/negctl.sh` with the pre-change `session_recall.py` | `FAILED (failures=3)`, then green after restore, `Verdict: PASS` | PASS |

Output:

```
2026-11-06  SPEC-260 r2 Reviewer 3  <projects>/<session>/subagents/agent-ab8dc7e0e18646a5f.jsonl
2026-11-06  SPEC-154 r2 Reviewer 3  <projects>/<session>/subagents/agent-a4acf25f77f66d63c.jsonl
```

Verdict: PASS.
