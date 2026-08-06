# FEEDBACK, cc-elevation-r2

Append-only meta-feedback for the skill maintainer (Han). One paragraph per entry, date-stamped, no PII/secrets. Categories are suggestions.

## Skill friction

- 2026-06-15: EnterWorktree named branches `worktree-feat+cc-elev-r2-NN-*` (prefixed `worktree-`, `/` -> `+`), not the clean `feat/cc-elev-r2-NN-*` the pointer prompt + sub-goal `Branch:` lines assumed. Cosmetic (PRs + squash-merges worked fine), but the roadmap's branch names did not match reality. The loop survived only because it keys off ROADMAP PR#s, not branch-name lookup. If a future pointer relies on branch names, account for this transform.
- 2026-06-15: the commit-format PreToolUse hook (72-char subject cap) caught one subject at 73 chars, and because the block fires on the whole Bash call, the paired `git add` in the same `&&` chain also did not run, so the retry had to re-stage. Worth knowing: the hook blocks the entire compound command, not just the commit verb.

## Tooling gaps

- 2026-06-15: several sub-goals had a genuinely un-autonomous final step (WorktreeCreate live event-fire, `launchctl bootstrap`, real agent runs of saved workflows, phone-push delivery). Handled by proving the logic in a unit smoke + marking the live step a documented deploy check. A first-class "deploy-verify" lane in the kit (distinct from the unit gate) would make this cleaner than per-tool prose.

## Codebase issues

- 2026-06-15: `cc-context` (pointer shorthand) is actually `tools/cc-context-hooks/` on main; the sub-goal file used the shorthand. Minor, resolved in impl-notes. Worth pinning exact tool dir names in sub-goal files when they extend an existing tool.

## Pointer prompt churn

(none; the pointer prompt was not edited mid-loop)
