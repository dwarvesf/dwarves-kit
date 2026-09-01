# Sub-goal 04: slim-global-claude-md

**Merge policy:** gate (capability-loss judgment on a file that loads every session; CROSS-REPO dotfiles PR; Han signs off)
**Time budget:** 1-2 hours of loop work
**Depends on:** 01 (the audit's ranked cheap-wins list says what is safe to cut)
**Branch:** feat/cctoken-04-slim-claude-md (in the `dotfiles` repo)
**PR base:** main (in `dotfiles`)

## Outcome

The global CLAUDE.md, the single biggest recurring token sink, loaded on every session, is measurably slimmer, with the cuts taken from sub-goal 01's cheap-wins list, and no capability lost (the rules that actually fire are kept; only dead weight, duplication, and stale sections go).

## CROSS-REPO + dotfiles discipline (read first)

This sub-goal does NOT land in ops-toolkit. The global CLAUDE.md source is the chezmoi template `~/workspace/<owner>/dotfiles/home/dot_claude/modify_CLAUDE.md.tmpl`. Consequences:
- `/kit:*` slash commands bind to the ops-toolkit cwd and CANNOT drive this work. Skip SDD-via-slash here; do the change directly and open the PR with plain `gh` from the dotfiles repo.
- The dotfiles watcher reverts uncommitted tracked changes (memory `project_dotfiles_watcher_atomic_commit`). Edit the template, then stage AND commit in ONE shell invocation; never leave the edit unstaged.
- `diff` is shell-aliased and fails non-interactively in dotfiles; use `cmp` / `shasum` to compare.

## How to close the loop

Sub-goal-specific verification:
- Pull the cheap-wins targeting CLAUDE.md from `research/2026-06-DD-cc-token-reduction-audit.md` (sub-goal 01). Cut only what that list marks safe.
- Edit `home/dot_claude/modify_CLAUDE.md.tmpl` in the dotfiles repo; `chezmoi apply`; confirm the live `~/.claude/CLAUDE.md` regenerated.
- Capture the delta: before/after line count (`wc -l`) and an estimated token delta. Baseline is ~580 lines.
- Capability check: confirm no actively-firing rule was removed (the canary line, the machine banner, the tool-selection + worktree + security sections stay). Note what was cut and why.
- Open the PR in the dotfiles repo, stamped with the before/after delta. It is `gate`: stop for Han's capability-loss sign-off.

**Done =** `home/dot_claude/modify_CLAUDE.md.tmpl` is slimmer with a captured before/after line-count + estimated token delta in the dotfiles PR body, only cuts from sub-goal 01's cheap-wins list, every actively-firing rule preserved, `chezmoi apply` clean, opened as a dotfiles PR awaiting Han.

## Scope edges

**In:** `home/dot_claude/modify_CLAUDE.md.tmpl` in the `dotfiles` repo only.
**Out:** ops-toolkit files, the repo-local CLAUDE.md files, MCP config, hooks (those are separate levers from the 01 list, not this sub-goal).
**Not:** do not remove the adherence canary, the machine banner, or any security/tool-selection rule that still fires; do not restructure the whole file; do not touch other dotfiles; do not hand-edit `~/.claude/CLAUDE.md` directly (edit the template, then chezmoi apply).

## Where to look

The dotfiles repo (`~/workspace/<owner>/dotfiles/home/dot_claude/modify_CLAUDE.md.tmpl`), the sub-goal 01 audit's CLAUDE.md cheap-wins rows, and memory `project_dotfiles_watcher_atomic_commit`.

## PR body

(Opens in the `dotfiles` repo.) Slims the global CLAUDE.md template, the biggest recurring per-session token sink, taking only the cheap-wins flagged safe by the cc-token-reduction audit. Before/after: <N> -> <M> lines (~<X>k token delta/session). Every actively-firing rule preserved (canary, machine banner, security + tool-selection + worktree sections intact).

Verify: `chezmoi apply` regenerates `~/.claude/CLAUDE.md`; `wc -l` before/after; spot-check the canary + banner survive.

Cross-repo gate: part of ops-toolkit mega-goal `cc-token-reduction` (sub-goal 04); scoped by `research/2026-06-DD-cc-token-reduction-audit.md`.

## Notes
