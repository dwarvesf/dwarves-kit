# The worker-brief pattern

Every subagent dispatch needs the same preamble: where it runs, what it may touch, and what
it owes back. A dispatching command used to retype that preamble by hand each time. This doc
names the block once so a command can cite it instead.

## What it is

The block a dispatching command puts at the top of a worker prompt, before the task-specific
instructions. It is not a template to fill in with placeholders; it is a checklist the
dispatcher runs through and writes into the prompt in its own words.

## The block

- Run `pwd` first. Confirm the worktree the worker actually landed in before reading or
  writing anything.
- Fetch and merge `origin/main` before reading any prerequisite doc.
- Use absolute paths for every write.
- Run git as `git -C <worktree>`, never a bare `git` that assumes the caller's cwd.
- Rename the branch to the repo's branch convention before the first commit.
- Name the files the worker may modify, and the shared modules it may not touch.
- For any behavioral change: require `docs/verification/<slug>.md` with a run table, a
  negative control, and a `## Not proven` section. Add a rollback note when the change is
  stateful.
- Require an activity-log line (the repo's LAB_LOG or equivalent).
- Commit, but never push.
- Report in N lines or fewer.

## Why each line is there

- **`pwd` first**: a worker's worktree can be created before a merge lands, so the worker
  needs to confirm where it is before trusting any relative assumption about what exists there.
- **Fetch and merge `origin/main` before reading a prerequisite doc**: a worker whose
  worktree predated a merge could not see the doc it was told to read. It read a stale copy,
  answered from it, and the answer was wrong in a way that looked confident. This is a real
  failure from the 2026-09-10 session.
- **Absolute paths for every write**: a relative write resolves against whatever the shell's
  cwd happens to be at that moment, not against the worktree the worker was told to use.
- **`git -C <worktree>`**: same reason as absolute paths, for git specifically. A bare `git`
  command trusts the ambient cwd, which drifts across a multi-step dispatch.
- **Rename the branch**: a worker that keeps the scaffold branch name collides with the next
  worker's scaffold, or ships a branch nobody can identify from the PR list later.
- **Name the files a worker may modify, and the shared modules it may not**: a worker fenced
  to a file set by exclusion ("don't touch the shared stuff") still edited a doc it thought
  was in scope and left two stale lines behind, because "the shared stuff" was never named.
  This is the second real failure from the 2026-09-10 session.
- **`docs/verification/<slug>.md` with a run table, negative control, `## Not proven`**:
  without this the worker's own claim of "done" is the only evidence, and a claim is not
  proof. The rollback note is the stateful case's extra: a stateful change without a named
  undo path is not reversible by anyone reading the record later.
- **Activity-log line**: the log is the index across every worker's output; a change with no
  log line is invisible to anyone scanning what happened this session.
- **Commit but never push**: a worker's commit is reviewable before it becomes a push the
  dispatcher did not look at.
- **Report in N lines or fewer**: an unbounded report from twenty parallel workers is a
  transcript nobody reads. A bound forces the worker to lead with the answer.

## Fences that matter

Name the files a worker may modify **positively**, as a list, not as "everything except
X". An exclusion list is only as good as the dispatcher's memory of what is shared; a
positive list is checkable by the worker without guessing. Say who owns the parts it may
not touch, so a worker that finds a real problem there knows to report it rather than fix
it.

## The open fork

This is a doc a command cites today: a dispatcher reads this file and writes the block into
its own words. It could instead be a lib helper that emits the block programmatically, or a
set of fields carried directly on the agent definitions. The doc is the reversible first
step; a helper or a schema change costs more to undo if the shape turns out wrong. The
alternatives, and which one to pick, are the dispatcher's call and are tracked in the
backlog row this pattern was promoted from (`_meta/backlog-staging.md`, "worker brief
template for subagent dispatch").
