# Queue run runbook: dispatch, monitor, review, close out an `#auto` row

The operator-side procedure around `bin/queue watch`. The tool owns the launch; this doc owns
everything the launch does not: picking the row, the review bar a draft PR must clear, and the
close-out choreography. Distilled from the first five live runs (the four pilot rows plus the
mechanism-fix cycle); every step below exists because skipping it bit once.

## 1. Pick a row worth automating

A good `#auto` row is bug-fix or test-fix shaped with a concrete, already-diagnosed root cause
and zero unresolved dependencies. Reject: rows depending on other queued rows, design-taste
work, security-critical surfaces, vague "calibrate X" asks. The row's Notes cell should let a
cold reader start working within a minute.

## 2. Dispatch

1. Write `.claude/goals/<slug>.md`. Keep it under roughly 2400 chars: the XPIA preamble and
   EXIT_SIGNAL/draft-PR suffixes consume the rest of the 4000-char `/goal` budget. Over-budget
   now fails fast to journal `error` (the pre-flight), but a fat pointer still wastes a cycle.
   Include: context with the diagnosed cause, task, scope fence (In/Not), self-verification
   with a negative control, the worktree-discipline paragraph, done-means.
2. Tag the row: `#auto #queue{repo=<name>,pointer=.claude/goals/<slug>.md}`.
3. Commit the tag. The watcher requires a CLEAN tree on the DEFAULT branch of the real
   checkout; a side worktree cannot pass the guards by construction.
4. Dry-run first: `bin/queue watch --max 1`. Expect your row, 0 skipped.
5. Launch detached: `nohup bin/queue watch --apply --max 1 > <log> 2>&1 &` then `disown`.
   Peek the tmux pane (`tmux capture-pane -p -t dk-queue:<slug>`) once after ~30s: the session
   should already be working, bare prompt, spinner up.

## 3. Monitor

Use `bin/queue wait <slug> [--timeout S]` instead of a hand-rolled poll loop: it blocks until the
slug gets a new terminal journal row (prints it, exit 0), its window dies without one (residue to
stderr, exit 1), or the timeout hits (exit 2). It is read-only over the journal + mux + sidecars.
The principle it encodes: poll the journal, not the pane, and treat the window disappearing
without a terminal row as a dead conductor, not a completion. Do not drive the window by hand
while it runs.

## 4. Review the draft PR (the bar every run must clear)

Never merge on the run's own say-so. In a FRESH worktree off the PR head:

1. Read the whole diff and the run's implementation notes. The notes should record decisions,
   deviations, and open questions; a notes file that mirrors the diff is a red flag.
2. Run the suites the change touches, plus the repo's meta suite.
3. Delta-vs-master: any failure on the branch must fail IDENTICALLY on a pristine-master
   worktree, or it belongs to the PR. And "identical on master" is not yet exoneration: check
   the state dirs the suite touches before calling it pre-existing code rot (the ID-468
   lesson: leaked per-machine state can fail a suite on one machine only).
4. Independent negative control: revert the fix (stash or checkout of the fix files only,
   never the test files), confirm the new test goes RED, restore, confirm green. Do this
   yourself; do not just re-read the PR's recorded control.
5. No-mutation check where relevant: checksum the files a test run might rewrite, run the
   suite, re-verify.
6. `gh pr ready` + merge only after all of the above.

## 5. Close out

One follow-up PR: flip the board row to `shipped [date #PR; one-line what-actually-happened]`,
add the CHANGELOG entry (the pointer's char budget rarely leaves room to ask the run for one),
and update `.claude/memory/` if the run changed what a future session should believe. Then
remove the run's worktree and branch, and reconcile the main checkout: before any
`reset`/`ff`, run `git log --format='%h %an %s' origin/master..HEAD` and account for every
local commit by author and subject; a commit you cannot account for stops the sync.

## Known sharp edges

- The main checkout is a shared surface: other sessions and editors hold it. Never branch-switch
  it, never `checkout --` a file that might carry unstaged work, stash (recoverable) instead of
  discarding.
- A dirty tree at dispatch is usually residue, not a human edit: two files modified in the same
  second is a machine signature. Diff against origin/master before assuming either way.
- Cleanup of a failed run: kill the tmux window, then check for orphaned `queue.sh run`
  processes (`ps -ef | grep queue.sh`) still holding the heartbeat, then clear the slug's
  beat/status/guard files (trash, not rm).
