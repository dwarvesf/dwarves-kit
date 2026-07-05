You are running the `token-hygiene` mega-goal. Source of truth on disk: `~/workspace/tieubao/ops-toolkit/_meta/megagoals/token-hygiene/`. Read `ROADMAP.md` every turn, and the relevant `goals/NN-*.md` before working a sub-goal. Do not rederive scope.

Rules (commands, not suggestions):
- One PR per sub-goal. A sub-goal that is only a local diff is unstarted. Record its PR # on the ROADMAP line when opened; mark `- [x] , PR #N` only when complete and merged-or-held.
- Stacking: gh stacked PRs. SG-01, SG-02, SG-03 are independent: branch off main, base main. SG-04 depends on SG-03: branch off SG-03's branch and base it there.
- Merge = auto-bottom-up + gated-final. SG-01 and SG-02 are `auto`: merge their PR yourself once ALL auto-merge gates hold (its own close-the-loop verification green; `gh pr checks <pr>` green; reviewDecision not CHANGES_REQUESTED; a proof-of-done with CAPTURED evidence committed; tagged auto), doing the retarget-child-before-delete dance. SG-03 and SG-04 are `gate`: open the PR then STOP for Han (shared dwarvesf/dwarves-kit repo, team review). Never merge a gate PR. Leave the final closing PR for Han (gated-final).
- "CI green" = the open PR's checks, never local tests.
- ops-toolkit is kit-adopted: each ops-toolkit sub-goal reads AGENTS.md + WORKFLOW.md, runs its lane, records gates via lib/gate-ledger.sh so the ship-gate is the Done check.
- Cross-repo: SG-03 and SG-04 live in dwarvesf/dwarves-kit, NOT ops-toolkit. The `/kit:*` slash commands bind to cwd, so run those sub-goals from a session whose cwd is the dwarves-kit checkout (or drive the lane via lib/ directly). Do not author kit specs from the ops-toolkit cwd.
- Do not rewrite a sub-goal's Done=. No new sub-goals mid-loop (log them to NOTES.md `## Proposed additions`). ROADMAP.md is the source of truth for done + PR #s.
- Each sub-goal verifies via its own close-the-loop commands (in its goal file), not a generic test run.
- Token hygiene (this mega-goal's own subject, so practice it): push big reads/searches to subagents (Explore/Agent), read narrow slices (offset/limit, grep -n), pipe big outputs to files. Keep the lead context lean. `/compact` if it bloats mid-loop.
- Before claiming the mega-goal complete: extract every PR # from ROADMAP, `gh pr view <N> --json state,reviewDecision,statusCheckRollup` each, confirm. Then run `/kit:review-team` plus one focused review lens across the merged set. Then append a single LAB_LOG arc entry (slug, sub-goal count, PR range, lessons) on the last sub-goal's branch per ops-toolkit SPEC-005. Then mark complete.
- Stop conditions: all sub-goals merged-or-held (success); a `gate` sub-goal or the held final PR awaiting Han; all remaining blocked with unchanged prerequisite; token budget exhausted. On any stop, append a summary to NOTES.md `## Event log` and emit a `🛑 LOOP BLOCKED , STOP /goal MANUALLY` banner.

Start: read ROADMAP.md and pick the first unchecked workable sub-goal. SG-01 is the natural start (it implements `tools/token-forensic/docs/specs/SPEC-120-token-forensic-loops.md`, already VALIDATED).
