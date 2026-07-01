# Implementation notes: SPEC-086 (stop-hook scan cost)

Delta from the spec only. The spec holds the design; this holds what it did not.

## 2026-06-19 The session marker is global and never refreshed per-session

- Context: wiring `DWARVES_KIT_SESSION_MARKER` so the scan is testable.
- Finding (not in the spec): `/tmp/.dwarves-kit-session-start` is created once,
  on the first Stop where it is absent, and never updated afterward. It is also
  a single path shared by every repo and every concurrent session. So
  "files modified since session start" actually means "since the marker file
  was first created" which, after the first session ever, is an arbitrarily old
  timestamp. The `head -10/-20` cap is the only thing bounding the result set.
- Decision: left as-is. SPEC-086 is scoped to scan *cost* and blast radius, not
  marker *semantics*. The git-guard + prune fix the heat regardless of how stale
  the marker is (a stale marker means "more files match", still bounded by prune
  + head + the repo boundary).
- Impact: a proper per-session marker (write it at SessionStart, key it per
  repo/cwd) is a separate correctness fix. Tracked as a follow-up, not done here.

## 2026-06-19 Runtime sync is a stopgap until the PR ships

- Context: the heat had to stop on the live machine immediately.
- Decision/Change: the prune fix was applied directly to the runtime copy
  (`~/.claude/dwarves-kit/hooks/`) first, then the guard+marker were synced there
  by `command cp` from the source repo. That directory is kit-managed
  (install-by-copy, SPEC-066): a future `install.sh` / plugin update pulls from
  the *published* version and would revert it.
- Why: install-by-copy is the anti-drift mechanism; the only durable path is
  source -> PR -> version bump -> reinstall. The manual cp buys time on this
  machine in the meantime.
- Impact: until SPEC-086 ships in a kit release, a plugin reinstall on this Mac
  reintroduces the unfixed Stop hooks. After it ships, runtime derives cleanly.
