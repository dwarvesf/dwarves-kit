Drive the cc-elevation-r4 mega-goal to completion autonomously. Source of truth: `_meta/megagoals/cc-elevation-r4/ROADMAP.md` + the `goals/NN-*.md` files beside it. Read them every turn (outcomes, Done= lines, scope edges, verification paths). Work in `~/workspace/<owner>/ops-toolkit`. Umbrella spec `tools/cc-self-improve/docs/specs/SPEC-103-cc-self-improve.md` is VALIDATED; do not re-litigate its design.

Pre-flight (turn 1): confirm `gh` installed (else stop and tell me) and clean latest `main`.

Workflow (hard rules):
- ONE PR per sub-goal; a sub-goal with only local diff is unstarted. Record PR# on the ROADMAP line when it opens (`- [ ] ... PR #N`), flip to `- [x] ... PR #N` when complete. A checked box always carries a PR#.
- Branch/base per ROADMAP: 02->03->04 STACKED (03 off 02, 04 off 03); 01 off `main`. `gh pr create --base <parent-or-main>`.
- "Green" = the open PR's CI (`gh pr checks <pr>`), not local tests (no-CI repo; proof = smoke + a recorded run).
- Kit-adopted: each sub-goal runs `lane-classify` and owes a co-located proof-of-done (green run + negative control) before its PR, or the ship-gate blocks the push. 02/03/04 extend `tools/cc-self-improve/docs/proof-of-done.md` (multi-feature index, SPEC-016); 01 extends `tools/cc-harvest/docs/proof-of-done.md`.
- SPEC-103 invariants (each goal file restates them): reviewer/curator run `--allowedTools ""` (no model write); only the wrapper + `/skill-review` write; curator git-mv-never-delete; hooks async + exit-0.
- Never rewrite a sub-goal's Done=/outcome mid-loop; record deviations under `## Notes` in the goal file (the goal is immutable). No new sub-goals mid-loop; discovered ones go under `## Proposed additions` in NOTES.md.

Merge = auto-bottom-up + gated-final. AUTO-MERGE each `auto` sub-goal (01,02,03) once ALL gates hold: (a) Done= verified by its close-the-loop, (b) proof-of-done committed WITH captured evidence (run-table / real log slice, not a bare "GREEN"), (c) reviewDecision not CHANGES_REQUESTED. Walk bottom-up; before deleting a merged parent's branch, retarget the child to `main` (`gh pr edit <child> --base main`) to dodge the auto-close trap. 01 (off main) merges any time. HOLD 04 (`gate`, final + host-touching launchd): open its PR, do NOT merge, it needs my click. Record `PR #N` + merge SHA on the ROADMAP line as each lands.

Defaults: fix-then-retry; after ~2 failed fixes on one sub-goal, log a fingerprinted blocker to NOTES.md `## Active blockers` (`command · failure · prerequisite · last verified`) and hop to the next. Address review feedback on the affected PR's own branch. Pre-flight each sub-goal: if Done= is already true, check the box + move on. Heartbeat to NOTES.md if hours pass with nothing to log. Verification = the goal file's close-the-loop, not a generic test run.

Stop conditions (only three): (1) 01/02/03 merged (checked-with-PR + SHA) AND 04 open+green+review-clean, HELD for my click; (2) every remaining sub-goal blocked on an unchanged prerequisite; (3) token budget exhausted. Else keep moving. Retry a blocked sub-goal only when its prerequisite changed since `Last verified`.

On every stop, append a summary to NOTES.md `## Event log` (outcome, PRs with #, blockers -> `## Active blockers`, reviewer items). On reaching held 04 emit `🛑 NEEDS APPROVAL: sub-goal 04, STOP /goal MANUALLY`; on later fast-stops emit only `🛑 LOOP BLOCKED: STOP /goal MANUALLY` and do not re-audit.

Before claiming success: for every `PR #N` in ROADMAP.md run `gh pr view <N> --json state,reviewDecision,statusCheckRollup`; any checked sub-goal whose PR is not open+green+review-clean is invalid, unmark it and keep working.

Close-out (sub-goal 04): before marking the mega-goal complete, 04's branch must carry the `_meta/LAB_LOG.md` entry for the whole cc-elevation-r4 arc (slug, 4 sub-goals, PR range, key lessons, the Hermes-parity assertion) as the newest entry (SPEC-005), plus the cc-elevation suite-docs memory/skill split. Then mark complete.
