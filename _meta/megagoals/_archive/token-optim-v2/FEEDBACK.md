# FEEDBACK: token-optim-v2 (skill / tooling / codebase friction)

Append-only. Audience: Han (skill maintainer), not the loop runner. Skim after the run; fold
items into `plan-for-mega-goal`, the kit, or the codebase.

- 2026-06-29: cross-repo worktree friction. The native `EnterWorktree` cannot create a worktree
  in a second repo (dwarves-kit) from an ops-toolkit session, so kit sub-goals needed a manual
  `git worktree add`. A documented cross-repo worktree recipe (or a kit helper) would remove the
  recurring exception. Surfaced while shipping token-hygiene #80/#81.
- 2026-06-29: this mega-goal is mostly `gate` (dwarves-kit shared repo), so `auto-bottom-up`
  effectively behaves like `open-only` for it. A `merge_mode` hint that says "this repo is
  always-gate" would make the resolved policy line less misleading.
