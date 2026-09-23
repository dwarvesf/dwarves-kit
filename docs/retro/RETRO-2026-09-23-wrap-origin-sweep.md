# Retro: wrap origin branch sweep
Date: 2026-09-23
Sprint: 2026-09-23 (one session)

Answers below were drafted from session evidence during `/kit:wrap`, not from an operator interview.

## Metrics
- Tasks planned: 1 (SPEC-307), completed: 1, deferred: 0; one follow-up fix
- Commits: 2 squash merges (#736 feature, #738 scope fix)
- Files changed: 11 in #736 (+424/-11), 6 in #738 (+31/-7)
- Key commits: `fdbd87d` feat(wrap): delete merged branches on origin during apply; `6f5123b` fix(wrap): run the origin branch sweep under --own too
- Real effect: 321 merged branches deleted on origin across foundation-workers, foundation-apps, foundation-ops, dwarves-kit

## What worked
- A dry run on the three real repos before any `--apply`. It surfaced two branches whose PRs had merged within the hour, so the lead checked them before deleting.
- The implementer ran the sweep against real origins and caught that `refs/remotes` tracked 13 of 181 branches; the sweep switched to `git ls-remote`.
- Leased deletes (`--force-with-lease` per branch at the tip read) plus the open-PR base guard. No branch with new work and no stacked PR was lost.
- A negative control for each guard: breaking any of the eight turned the suite red.

## What hurt
- The first ship scoped the origin sweep like the local sweep, so `--own` skipped it. Shared repos are exactly where step 5 prescribes `--own`, so real wraps would never have swept origin. Four merged heads were back on foundation-workers within an hour.
- Cause: the spec copied the local sweep's scope rule by analogy. Every real-repo verification ran `apply` without `--own`, not the invocation step 5 prescribes for shared repos.
- The lead ran the hand-worktree land loop (worktree, commit, override, named push, PR, merge, cleanup) three times while `bin/wrap start` / `bin/wrap land` existed.

## Action items
- [x] Run the origin sweep under `--own` and pin it with a test -- owner: @tieubao -- deadline: 2026-09-23 (#738)
- [ ] Verification for a `wrap` verb change runs the verb the way `commands/wrap.md` step 5 invokes it on a shared repo (`--own`), not only the bare form -- owner: @tieubao -- deadline: 2026-09-30

## Kit feedback
- `bin/wrap land` was the right tool for the three foreign-repo docs landings and went unused; the memory note for cross-repo worktrees now names it as the first rung.
- The command text loaded at session start still said `--own` skips the origin sweep after #738 merged; a running session keeps the old command body until restart.
