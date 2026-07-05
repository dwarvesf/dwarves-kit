Drive the cc-elevation-r3 mega-goal to completion autonomously. Source of truth: `_meta/megagoals/cc-elevation-r3/ROADMAP.md` and the per-sub-goal files in `_meta/megagoals/cc-elevation-r3/goals/`. Read them every turn; they hold the outcomes, Done= lines, scope edges, and verification paths. Work in `~/workspace/tieubao/ops-toolkit`.

Pre-flight (turn 1): confirm `gh` is installed; if missing, stop and tell me. Confirm you are on a clean checkout of latest `main`.

Workflow shape (hard rules):
- ONE PR per sub-goal. A sub-goal with only local diff is unstarted. Record its PR# on the ROADMAP line the moment it opens: `- [ ] ... PR #N`, then `- [x] ... PR #N` when complete. A checked box has a PR# or it is not checked.
- Branch/base per ROADMAP: 01->02->03 are STACKED (02 off 01's branch, 03 off 02's branch); 04, 05, 06 branch off `main`. Use `gh pr create --base <parent-or-main>`.
- "Green" = the open PR's CI (`gh pr checks <pr>`), not local tests.
- DO NOT merge any PR. Merging is my gate. Open the stack + independents, get them green + review-clean, then stop.
- Do not rewrite any sub-goal's Done= or outcome mid-loop. Append a `## Notes` section to a sub-goal file to record a deviation; the goal is immutable.
- No new sub-goals mid-loop. Discovered ones go under `## Proposed additions` in NOTES.md.
- This repo is kit-adopted: each sub-goal runs its lane via `lane-classify` and owes a co-located proof-of-done (green run + negative control) before its PR, or the ship-gate blocks the push. cc-observe view sub-goals (01-03) extend `tools/cc-observe/docs/proof-of-done.md`; 04/05 own theirs; 06 emits an eval verdict in the research note.

Good defaults: fix-then-retry on CI/review failures; after ~2 failed fixes on one sub-goal, log a fingerprinted blocker to NOTES.md `## Active blockers` (`command · failure · prerequisite · last verified`) and hop to the next workable sub-goal. Address review feedback on the affected PR's own branch. Pre-flight each sub-goal: if its Done= is already true, check the box + continue. Heartbeat to NOTES.md `## Event log` if hours pass with nothing else to log.

Per-sub-goal verification is the sub-goal file's close-the-loop section, not a generic test run. Each cc-observe view owes a fixture + a negative control + a real-data run in the proof; 05 owes a real ingest landing on `/status` + a stale negative control; 06 owes the Remote-Control regression test result + a written verdict.

Stop conditions (only three): (1) all 6 sub-goals checked-with-PR, CI green, reviews not requesting changes; (2) every remaining sub-goal blocked with an unchanged prerequisite; (3) token budget exhausted. Anything else: keep moving. Retry a blocked sub-goal only when its prerequisite changed since `Last verified`.

On every stop, append a final summary to NOTES.md `## Event log` (outcome, PRs with #, blockers pointing at `## Active blockers`, reviewer items). On later fast-stops emit only `🛑 LOOP BLOCKED , STOP /goal MANUALLY`; do not re-audit.

Before claiming success: extract every `PR #N` from ROADMAP.md and run `gh pr view <N> --json state,reviewDecision,statusCheckRollup`; any checked sub-goal whose PR is not open+green+review-clean is invalid , unmark it and keep working.

ops-toolkit close-out: before marking the mega-goal complete, draft a single-paragraph `_meta/LAB_LOG.md` entry (slug, sub-goal count, PR range, key lessons) as the newest entry on the LAST sub-goal's branch so it rides into that PR (SPEC-005). Then mark complete.

Merge discipline is MINE on return (do not do it): merge 01->02->03 bottom-up, retargeting each child's base to `main` before deleting the parent's branch; 04/05/06 any time.
