# Retro: tiered verification for mega-goal waves (SPEC-421)
Date: 2026-11-16
Sprint: 2026-11-15 to 2026-11-16

Answers drafted by the lead from the session record (the operator approved the landing without a Q&A round). Edit any line that misreads it.

## Metrics
- Tasks planned: T0 to T4 (the kit repo), completed: all; T5 (dotfiles skills) and T6 (Spacedown pilot) deferred to other repos.
- Spec: 3 revisions. Revision 3 rescoped to cheap re-runs after the confirmation review instead of a fourth fold. Spec landed as #1170 first, the build as #1171.
- Build: 15 commits before the land, 21 files, about +1.2k lines; new suites `test-known-failures` and `test-orchestrate-tiered`, plus a verify-off golden that pins the default path.
- Follow-ups after the first review pass: head pinning (`--expect-head`, exit 75), a signal trap on the join, base-count guard, unreadable-base stop, join refs removed.
- Default unchanged: `[mega] verify` is `off`; tiered mode needs the base commit's `.kit.toml`.

## What worked
- Capturing the verify-off golden before touching `orchestrate.sh` turned "no default change" into a diff, not a claim.
- Reading every gate key from the base commit closed the "a node edits its own gate" class in one rule instead of per-key patches.
- A negative control per join rule (C2 red when the join is removed) made each fold falsifiable.

## What hurt
- The spec said the serial path joins per DAG level, but the serial loop never merges. The mismatch surfaced only at build time (D9) and left the serial path unbuilt.
- The spec branch and the build branch both carried the spec commits, so landing the spec first made a rebase refuse on the spec file and a merge conflict on the generated registry.
- `wrap start` refused the build worktree because the spec branch's worktree held the slug directory, so the worktree was hand-made.
- Draft-push overrides for ship and reflect sat in the ledger for the whole build and had to be superseded at land time.

## Action items
- [ ] Build the serial-path join (D9): the same once-per-level full-suite join before the serial merge step, reusing the wave join -- owner: @tieubao -- deadline: 2026-11-17
- [ ] Port T5 (the two dotfiles mega-goal skills) and run T6 (the Spacedown pilot, AC8) on a real run -- owner: @tieubao -- deadline: 2026-11-30
- [ ] Decide whether a `fail_count_line` key is worth adding: a failure the `failure_line` regex never prints stays invisible while the count holds (D23) -- owner: @tieubao -- deadline: 2026-11-30

## Kit feedback
- `wrap rebase` refuses a branch that carries its own spec branch's commits once the spec squash-merged; the safe-conflict list could treat an identical add on both sides as clean.
- `wrap start` derives the worktree directory from the branch slug, so a build branch named after a spec branch with a live worktree cannot start through it.
