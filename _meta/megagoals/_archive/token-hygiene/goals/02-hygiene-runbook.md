# SG-02: mega-goal token-hygiene runbook

Merge policy: auto
Time budget: ~0.5 session

## Directional outcome
A short operator runbook that turns the session's finding into a repeatable practice:
stage mega-goals, `/clear` between sub-goals/stages, resume via POINTER_PROMPT, and keep
big outputs out of the lead context.

## Done =
`tools/token-forensic/docs/token-hygiene-runbook.md` (or a `research/` note) exists, is
linked from the token-forensic README, and covers: when to `/clear` vs `/compact`, the
stage-and-resume mega-goal pattern, and the subagent-offload / narrow-slice / pipe-to-file
rules. Merged via PR.

## Close the loop (verification)
```
test -f tools/token-forensic/docs/token-hygiene-runbook.md
grep -q token-hygiene-runbook tools/token-forensic/README.md
```

## Scope edges
Doc only. No tool code. Reuse the patterns already written in
`research/2026-06-28-token-spend-forensic.md` (do not restate; link).

## Where to look
`research/2026-06-28-token-spend-forensic.md` (Actionable + Handoff sections), the kit
audit findings in `.claude/handoffs/2026-06-28-token-optimize.md`.

## PR body
docs(token-forensic): operator runbook for mega-goal/session token hygiene.
