# Implementation notes: SPEC-323 PR titles in wrap step 10

Delta from `docs/specs/SPEC-323-pr-fill-first.md`.

- The old pin `... --head <branch> --fill` passed against `--fill-first` because the check is a substring match. It could never have caught this flag. The new pins require the full new text, and a `chk_no` on the literal flag-then-backtick rejects a bare `--fill`.
- That `chk_no` also caught a prose sentence in the step that named both flags; the sentence was reworded.
- `wrap land` has the same title problem: it takes the last commit's subject (#771 and ops-toolkit #3478 both landed under a follow-up commit's subject). That is a `lib/wrap/wrap.sh` change, full lane, and out of this spec's scope.
- The ship-gate refuses even `gh pr create --dry-run` while lane gates are missing, so combining `--title` with `--fill-first` was not probed. The draft command does not combine them.
