# Proof of done: no-implnotes fixture (test fixture, tests/test-pitch.sh)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | fixture thing happens | PASS | Confirmation run below |
| AC2 | NEGATIVE CONTROL: reverting the fixture change makes the fixture check fail | PASS | git stash proof below |

## Confirmation run (green)

```
$ echo fixture-check
fixture-check
PASS 1/1
```

## Reproduce

```
echo fixture-check
```
