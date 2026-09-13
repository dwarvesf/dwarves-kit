# Proof of done: batch-debt-warn hook

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | Two merges in one session with no lane START warn once | live hook run, two payloads, warn on the second | PASS |
| AC2 | A lane START inside the window keeps the hook silent | live hook run with a real `gate-ledger.sh start` between the two merges | PASS |
| AC3 | A single merge never warns | test case 3.1 | PASS |
| AC4 | The warn fires once per session, not once per merge | test case 1.3 (third merge silent) | PASS |
| AC5 | Non-merge commands never engage | test cases 3.2 and 3.3 (`git push`, merge text inside a commit message) | PASS |
| AC2 [NEGATIVE CONTROL] | Breaking the START detection makes the silent case warn | `STARTED=""` forced, case 2.2 flips to FAIL, restored to green | PASS |
| AC6 | The hook stays inside the 500ms hook budget | three timed runs against the operator's real ledger (617 run logs) | PASS |

## Implementation

- `hooks/batch-debt-warn.sh` (37 lines): PreToolUse Bash hook. Counts its own `gh pr merge`
  engagements per session in the ledger stream `merge-watch/<session_id>.log`, then compares the
  newest `| START` line across `runs/*.log` against the timestamp of that session's first merge.
- `tests/test-batch-debt-warn.sh`: hermetic HOME plus a temp `KIT_LEDGER_DIR`, 8 cases.
- Registration: `settings.json`, `hooks/hooks.json`, the `session` install module in `install.sh`
  and `tests/test-install-modules.sh`, the README hook roster, the `docs/architecture.md` fallback
  table (advisory), and the generated `docs/FEATURES.md`.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-batch-debt-warn.sh` | 0 | PASS=8 FAIL=0 |
| `bash tests/test-batch-debt-warn.sh` (START detection broken) | 1 | PASS=7 FAIL=1, case 2.2 warns |
| `bash tests/test-batch-debt-warn.sh` (restored) | 0 | PASS=8 FAIL=0 |
| `bash tests/test-meta.sh` | 0 | 852/852 passed |
| `bash bin/lint --zone hooks --count` | 0 | 0 scattered ids |
| `bash tests/test-no-scattered-ids.sh` | 0 | 9/9 passed |

## Run detail

Ungated batch, live hook, temp ledger:

```
--- merge 1 (silent expected) ---
--- merge 2, no START (warn expected) ---
📚 **Batch-debt warning**: this session has merged 2+ PRs with no lane START in the gate ledger
since the first merge, so the batch is closing with its understanding debt unrecorded. Fix in one
line: `gate-ledger.sh start <rid> <lane> <lane> <type>` then `gate-ledger.sh debt <rid>
significance=high worthiness=high verdict=tap response=defer`. A batch with nothing to absorb can
dismiss this.
--- ledger stream ---
2026-09-12T19:00:10Z | MERGE
2026-09-12T19:00:10Z | MERGE
2026-09-12T19:00:10Z | WARNED
```

Gated batch, same hook, a real `gate-ledger.sh start` between the two merges:

```
--- START written ---
2026-09-12T19:00:34Z | START | lane=full classified=full type=feature ctype=demo repo=batch-debt-warn
--- merge 2 (silent expected) ---
(no output above = silent) OK
```

Negative control, `STARTED=""` forced into the hook:

```
  PASS 2.1 first merge                                    silent
  FAIL 2.2 second merge after a START                     expected=silent actual=warn
PASS=7 FAIL=1
exit=1
```

Latency against the operator's real ledger:

```
real 0.13
real 0.33
real 0.22
```
