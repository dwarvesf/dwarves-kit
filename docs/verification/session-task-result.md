# Verification -- session-task-result

`session recall --final <task.output>` gains `--json` (parsed outermost object), `--out FILE` (write the result, print a one-line summary) and `--max-bytes N` (stdout cap, default 64 KiB), so a lead reads one subagent's result without opening the whole task output file.

## Green run
```
Command: cd lib/session/recall && python3 -W error::ResourceWarning -m unittest discover -s tests
Exit: 0
Output:
Ran 52 tests in 1.040s
OK

Command: session-recall --final fixtures/result-json.jsonl --json --out /private/tmp/claude-501/r.json
Exit: 0
Output:
wrote 124 bytes to /private/tmp/claude-501/r.json, top-level keys: verdict, count, findings

Command: session-recall --final fixtures/result-bad-json.jsonl --json
Exit: 1
Output:
session-recall: outermost {...} is not valid JSON (Expecting value: line 1 column 30 (char 29)) in the final reply of lib/session/recall/fixtures/result-bad-json.jsonl

Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
run-all: all 9 suites passed, 0 skipped for missing tooling
Verdict: green; the new modes behave on the fixtures and through lib/session/session.sh recall.
```

## Negative control
```
Command: sed the slice anchors in outermost_json_object from "{" "}" to "[" "]", then python3 -m unittest discover -s tests
Exit: 1
Output:
FAIL: test_result_json_prints_outermost_object
FAIL: test_result_malformed_json_is_clear_error_exit_1
FAIL: test_result_out_writes_file_and_prints_one_line_summary
Ran 52 tests in 0.990s
FAILED (failures=3)
Verdict: RED with the parser broken. Restored with git checkout -- session_recall.py; suite back to 52 tests OK.
```

## Not proven
- Not run against a real multi-megabyte task output file; the byte cap is covered by a unit test on the fixture.
- The outermost slice takes first `{` to last `}`: a reply with two separate JSON objects fails as invalid JSON (reported, not guessed).
