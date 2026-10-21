# Verification -- recall-final-reply

`session recall --final <transcript.jsonl> [--fence TAG]` prints the last assistant message that has text, or the content of the last closed fenced block with that tag.

## Green run

```
Command: cd lib/session/recall && python3 -m unittest discover -s tests   (Python 3.12.13)
Exit: 0
Output:
  .............................................
  ----------------------------------------------------------------------
  Ran 45 tests in 0.822s

  OK
Verdict: PASS
```

Real primary flow, CLI on a fixture transcript whose last two turns are thinking-only and tool_use-only:

```
Command: python3 bin/session-recall --final fixtures/final-backtick.jsonl --fence markdown
Exit: 0
Output:
  # Report

  Intro line.

  ```bash
  ls -la
  ```

  Done section.
Verdict: PASS
```

## Negative control

```
Command: mutate session_recall.py (found = "\n".join(lines) -> found = found or "\n".join(lines), i.e. first block wins), run the suite, restore, run again
Exit: 1 (under mutation, RED expected)
Output:
  FAILED (failures=1)    test_final_fence_backtick_takes_last_block_and_keeps_inner_fence
Restore exit: 0, Ran 45 tests ... OK
Verdict: PASS (RED with the first-block mutation, green after restore)
```

## Not proven

- A transcript where one API message is split across several JSONL lines with text on more than one line: only the last such line is returned.
- An unlabeled inner fence of the same length as the outer closes the outer block early; use a longer outer fence.
