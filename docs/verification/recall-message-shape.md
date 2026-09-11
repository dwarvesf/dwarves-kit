# Verification: session-recall survives a non-dict message

`lib/session/recall/session_recall.py` read `(entry.get("message") or {}).get(...)` in `_role`, `searchable_text` and `opening_ask`. A transcript line whose `message` is a string or a list is valid JSON and a valid object, so `load()` keeps it, and the first `.get` on it raised `AttributeError`. The observe and semantic readers received this guard on 2026-09-10 (`lib/session/observe/docs/implementation-notes/observe-nondict-crash.md`); recall was recorded there as the open follow-up.

One helper `_msg(entry)` now returns the message when it is a dict and `{}` otherwise. All three readers call it, so the check lives in one place.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `cd lib/session/recall && python3 -m unittest discover -s tests` | 0 | PASS, 16 tests |

```
Command: python3 -m unittest discover -s tests
................
Ran 16 tests in 0.215s
OK
Exit: 0
Verdict: PASS
```

The new case is `test_second_level_non_dict_message_never_crashes`. It loads `tests/nondict-edge/nondict-message.jsonl` (a string message, a list message, then a valid turn) and asserts every reader returns, `_role` falls back to the top-level `type`, `opening_ask` skips to the valid turn, and `search` still finds it.

## Negative control

Drop the `isinstance` check from `_msg` so it returns `m or {}`, run, restore.

```
Command: sed -i '' 's/    return m if isinstance(m, dict) else {}/    return m or {}/' session_recall.py \
         && python3 -m unittest discover -s tests; git checkout -- session_recall.py
ERROR: test_second_level_non_dict_message_never_crashes
AttributeError: 'str' object has no attribute 'get'
Ran 16 tests in 0.198s
FAILED (errors=1)
Exit: 1
Verdict: RED as expected, then restored clean
```

Only the new case fails, so the fixture reaches exactly the path the guard protects.

## Reproduce

```bash
cd lib/session/recall && python3 -m unittest discover -s tests
```

## Note on the glob

`tests/run-all.sh` globs `tests/test-*.sh`. No shell suite runs the recall unittest, so a green `run-all.sh` says nothing about this module. The command above is the only way to run it.
