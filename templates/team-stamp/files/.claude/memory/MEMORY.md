# Repo lessons

Each line is one lesson that cost time once. Read the note before you do the work it covers. Add a note in the PR that paid for it: `AGENTS.md`, section "Lessons". Keep this file under 8,000 characters.

- [CI runner has no procps](ci-runner-has-no-procps.md): no `kill`, `pgrep`, `ps` or `rsync` binary on a slim runner; use the shell built-in `kill -0` and `cp` in tests.
- [CI sets CI=true](ci-sets-ci-true.md): a script that branches on `CI` acts differently in CI; tests set or clear it on purpose.
- [Queued run missing from lists](queued-run-missing-from-lists.md): a branch filter can miss a queued run; wait by run id or by the PR check rollup.
- [Guards match command text](guards-match-command-text.md): the hook sees command text only and has known misses; do not hide a command from it, CI is the second line.
- [Stale checks after a rule change](stale-checks-after-a-rule-change.md): green checks are from the old rules; update the branch with `gh pr update-branch`, never close and reopen to refresh CI.
