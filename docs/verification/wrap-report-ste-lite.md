# Proof of done: wrap reports follow STE-lite prose

## What changed

`commands/wrap.md` step 9 fixed the report structure and `lib/wrap/report-lint.sh` linted it, but nothing constrained the prose. Real reports came out with semicolons and 30-word sentences. Step 9 now carries a "Prose is STE-lite" bullet (step 10's report follows it). The lint fails a semicolon or a sentence over 20 words, counted outside backtick spans, in `Needs you` items, `What happened` bullets, the `FYI` Fact cell, the `Left alone` Why cell, and the `reported:` reason of a `Built:` item. A contraction only warns.

## Gate table

| Claim | Evidence |
|---|---|
| a semicolon fails, and the finding names the line | green run, case "semicolon finding names the line" |
| a 21-word sentence fails, a 20-word one passes | green run, two cases |
| a semicolon inside backticks passes | green run, backtick case |
| FYI Fact, Left alone Why, and Needs you cells are judged | green run, three cases |
| the new cases are load-bearing | negative control below |
| step 9 template and the harvest-sweep report still lint clean | fixture and renderer rewrite below |

## Green run

```
Command: bash tests/test-wrap-report-lint.sh
Exit: 0
Output: test-wrap-report-lint: all 148 passed
Verdict: PASS
```

## Negative control

The old lint (`git show HEAD:lib/wrap/report-lint.sh`) run against the new test file:

```
Command: bash tests/test-wrap-report-lint.sh   (old lint restored)
Exit: 1
Output:
  FAIL a semicolon in What happened fails
  FAIL the semicolon finding names the line
  FAIL a 21-word sentence fails
  FAIL the long-sentence finding names the count
  FAIL a semicolon in a Left alone Why cell fails
  FAIL a 21-word FYI Fact cell fails
  FAIL a semicolon in a Needs you item fails
  FAIL the contraction warning names the line
  test-wrap-report-lint: 140 passed, 8 FAILED of 148
Verdict: RED, as required
```

## Fixtures and examples rewritten

| File | Why it failed | Fix |
|---|---|---|
| `tests/fixtures/harvest-sweep/report-wrap-harvest-skip.md` | semicolon in a What happened bullet | two sentences |
| `hooks/harvest_sweep.py` (sweep report renderer) | semicolon in the What happened bullet | period instead |
| `commands/wrap.md` FYI STATE template cell | 22-word sentence | shortened to 17 words |
