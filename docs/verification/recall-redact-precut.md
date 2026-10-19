# Verification -- recall-redact-precut

`session recall` cut no text before `SECRET_SHAPE_RE`, whose PASSWORD/TOKEN branch is cubic on repeated keyword runs. `opening_ask` and `_clean_tail_text` now cut to `max(512, 2 * width)` chars first.

## Green run

```
Command: cd lib/session/recall && /usr/bin/python3 -m unittest discover -s tests
Exit: 0
Output:
  .....................................
  ----------------------------------------------------------------------
  Ran 37 tests in 0.735s

  OK
Verdict: PASS
```

```
Command: cd lib/session/recall && python3 -m unittest discover -s tests   (Python 3.12.13)
Exit: 0
Output:
  .....................................
  ----------------------------------------------------------------------
  Ran 37 tests in 0.580s

  OK
Verdict: PASS
```

Timing of the real call, `opening_ask` on a first user turn (unfixed -> fixed):

```
Command: python3 timing.py TOKEN:819   (opening_ask on "TOKEN" * 819 = 4095 chars)
Exit: 0
Output:
  Python 3.9.6   before 22.68s   after 0.120s
  Python 3.12.13 before 14.82s   after 0.126s
  Python 3.9.6   after: TOKEN*2000 0.187s, PASSWORD*1000 0.171s
  Python 3.12.13 after: TOKEN*2000 0.071s, PASSWORD*1000 0.118s
Verdict: PASS
```

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "cd lib/session/recall && /usr/bin/python3 -m unittest discover -s tests" "git show HEAD~1:lib/session/recall/session_recall.py > lib/session/recall/session_recall.py"
Exit: 1 (under mutation, RED expected)
Output:
  AssertionError: ask on TOKEN*2000 still running after 5 s
  Ran 37 tests in 5.486s
  FAILED (failures=1)
Verdict: PASS (RED under the unfixed file, green again after restore)
```

The mutation put the pre-fix `session_recall.py` back; negctl restored the fixed file and the suite went green (37 tests, OK).

## Not proven

- `lib/precedent/inventory.py` `safe_text` runs the same pattern on file lines with no pre-cut; not touched here.
- Output for text longer than 512 chars whose redactions shrink it below the cap can differ from before (the tail past the cut is never shown).
