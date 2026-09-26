# Implementation notes -- rebase-resolve

Deltas from SPEC-329. Nothing here repeats what the spec already states.

## 2026-09-27 The pure-addition test reads diff through process substitution
- Context: the first build piped `diff base side | grep -q '^<'`. Under `set -o pipefail`, diff's exit 1 (the files differ) became the pipeline status, so `!` read every CHANGELOG conflict as pure.
- Decision/Change: `_rb_changelog_pure` runs `grep -q '^<' < <(diff ...; diff ...)`.
- Why: the reworded-bullet test caught it: the verb unioned a reworded bullet, the exact failure the design change exists to refuse.
- Impact: none on the contract; a comment at the call names the trap.

## 2026-09-27 The no-marker assertions read git output the same way
- Context: the first negative control went red on the three `MARKERS` assertions but not on `no marker in any reachable commit`. Under the suite's pipefail, `git log -p | grep -q` reported git's SIGPIPE, so the check passed with markers committed.
- Decision/Change: every rebase assertion that greps git output uses `< <(git ...)`; a second commit fixed them and the negative control ran again on it.
- Impact: the mutation now turns four assertions red.

## 2026-09-27 Test origin is a plain repo, not a bare one
- Context: the spec's test plan names a bare origin. Moving a bare origin needs a `git push` to `main` from the test, which the session's branch guard blocks inside a script.
- Decision/Change: each case clones a non-bare repo on `main` and commits there directly; the worktree's `git fetch origin` sees it the same way.
- Why: no push anywhere in the rebase block, so no guard exemption is needed.
- Impact: none on coverage; every fetch the verb runs reads a real remote.

## 2026-09-27 Smaller choices the spec left open
- The worktree argument resolves through `rev-parse --show-toplevel`, so a subdirectory of a worktree rebases that worktree.
- Preflight refusals go to stderr, like `wrap land`; the run's own lines (`REFUSED`, `MARKERS`, `rebased ...`) go to stdout.
- A generator failure in the final pass prints `GENERATOR FAILED` too and exits 1; the branch is already rebased then.
- `_usage` now prints lines 2 to 31, so the help keeps the `--tips-file` seam line the new verb line pushed out.
