# queue: prompt char match is locale-independent

Date: 2026-10-27
Class: behavioral (changes what `_mux_submit` and `_mux_wait_ready` do under a C locale)

## Restated claim

`_mux_submit` sends exactly one Enter to a window whose prompt is already clear (a bare `❯`),
in every locale. Measured by counting `enter slug=...` lines the stub mux logs.
It was false under a C locale.

## Defect

The nightly regression on the Mini (`mini.kit-nightly-regression`, launched by a launchd stage, no
`LANG` set) failed `test-queue` T10 on 2026-10-27 and posted CRIT `kit-regression-failed`.

Root cause: `lib/queue/queue.sh` wrote the prompt char as the bracket class `[>❯]` in two greps.
In a C locale a bracket class holds the three bytes of `❯` (E2 9D AF), not the character. On the
bare line `❯ ` the first byte matches the class, the second byte matches `[^[:space:]]`, so the
bare prompt read as "prompt with content after it". `_mux_submit` then re-sent Enter five times
and warned `submit unconfirmed after 5 tries`. The readiness check (`_mux_wait_ready`) had the
same class and treated any line starting with byte E2 (a box drawing rule) as a prompt.

Why it surfaced now and not earlier: the suite was a `.bats` file no runner collected. #1065 renamed
it to `tests/test-queue.sh`, so the nightly full run collected it for the first time (suite count
262 on 2026-10-26, 303 on 2026-10-27). The queue code and T10 are unchanged since 2026-08. This is
a deterministic locale failure, not a timing flake. In a real overnight queue run under launchd the
same bug sends four extra Enters into a live session.

## Fix

Prompt char written as the alternation `(>|❯)`, which matches the whole character in every
locale. New case T10c runs the bare prompt and a box drawing line under `LC_ALL=C`.

## Green run

Baseline is the clean `origin/master` checkout (bcf21ee). Each cell is passes over runs of
`bash tests/test-queue.sh`. "env -i" is a launchd-like environment: no `LANG`, no `LC_*`.

| Locale | origin/master | with fix |
|---|---|---|
| `LC_ALL=C` | 0/10 | 12/12 |
| `LC_ALL=en_US.UTF-8` | 10/10 | 12/12 |
| `env -i` (launchd-like) | 0/10 | 12/12 |

```
- Command: LC_ALL=C bash tests/test-queue.sh
- Exit: 0
- Output: test-queue: all 30 passed
- Verdict: PASS
```

## Negative control

Old `lib/queue/queue.sh` restored from origin/master, new test file kept:

```
- Command: LC_ALL=C bash tests/test-queue.sh   (old queue.sh)
- Exit: 1
- Output:
    FAIL T10 submit-bare-prompt: bare prompt exits after one Enter
    FAIL T10c submit-bare-prompt-c-locale: bare prompt exits after one Enter under LC_ALL=C
    test-queue: 28 passed, 2 FAILED -> T10 T10c
- Verdict: RED-as-expected
```

Under `LC_ALL=en_US.UTF-8` with the old file only T10c fails (29 passed), so T10c discriminates the
locale defect on a UTF-8 developer machine too. The fixed file was restored with `git checkout --`
and the suite re-run green (30 passed).

## Unverified

The full `run-all.sh --all` was not re-run here. The nightly flagged only `test-queue`; the other
suites it newly collected passed in the same C-locale environment.

## Rollback

Revert the commit. Two grep patterns and one test case; no state, no migration.
