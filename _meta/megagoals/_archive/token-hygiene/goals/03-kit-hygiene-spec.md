# SG-03: dwarves-kit context-hygiene SPEC + ADR (design)

Merge policy: gate
Time budget: ~1 session

## Directional outcome
A design (SPEC + ADR) in the dwarves-kit repo for inter-sub-goal context hygiene, so the
mega-goal loop stops accumulating an un-cleared marathon context. Design only; no impl in
this sub-goal.

## Done =
In `dwarves-kit` (dwarvesf/dwarves-kit): a SPEC (`docs/specs/`) + an ADR (`docs/decisions/`)
proposing (1) subagent-return summarization (lead receives a distilled result, not full
output) and (2) a post-sub-goal "checkpoint: safe to /clear + resume from POINTER_PROMPT"
signal. Opened as a PR. Because this is a shared repo, the PR is `gate` (Han/team review),
not auto-merge.

## Close the loop (verification)
```
# in the dwarves-kit checkout
ls docs/specs/ | grep -i context-hygiene
ls docs/decisions/ | grep -i context-hygiene
```
PR opened, review requested.

## Scope edges
Design artifacts only (no kit code). Must cite the audit evidence (`WORKFLOW.md:651-652,
707-712`). The kit cannot self-`/clear` (kills its own loop), so the design centers on
summarization + operator signals, not self-clearing.

## Where to look
Kit source: `~/.claude/dwarves-kit/` (WORKFLOW.md, lib/), kit skills `/kit:execute`,
`plan-for-mega-goal`. Cross-repo caveat: drive `/kit:*` from a session whose cwd is the kit
repo, or use `lib/` directly (per plan-for-mega-goal cross-repo note).

## PR body
docs(kit): SPEC + ADR for inter-sub-goal context hygiene (summarize subagent returns +
checkpoint signal). Design only; gated for team review.
