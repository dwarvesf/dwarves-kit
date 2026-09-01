Mega-goal kit-north-star. Source of truth: `_meta/megagoals/kit-north-star/ROADMAP.md` in ops-toolkit (~/workspace/<owner>/ops-toolkit). Re-read it plus the active sub-goal file under its `goals/` every turn; update NOTES.md and FEEDBACK.md per their section rules.

Destination: dwarves-kit routes every kind of task through a right-sized loop. Chat stays chat; tasks classify by type and lane; non-code types (research/eval/compare/test-design/cleanup/doc) get defined loops with a designated or dynamic agent; the kit BACKLOG becomes a status-driven kanban an agent can pull from; tests are designed first in the dialect fitting the type, and runs are stored as proofs.

Quality bar: the kit takes its own medicine. Every sub-goal ships through the kit's lanes with recorded gates; spec statuses stay truthful; nothing phantom (no documented-but-unimplemented feature).

Work repo: ~/workspace/<owner>/dwarves-kit (shared; NEVER push master). One branch + one PR per sub-goal (branch names in the sub-goal files), gh sequential: a dependent PR opens only after its parent merges; while waiting, work a non-dependent sub-goal or stop blocked. The kit repo is kit-adopted: classify each sub-goal's lane with lib/lane-classify.sh and record its gates with lib/gate-ledger.sh (slash commands bind to cwd; from an ops-toolkit session drive the lib machinery directly). Both suites (tests/test-meta.sh, tests/test-hooks.sh) must be green before any PR.

Hard rules:
- One PR per sub-goal; a local-only diff is an unstarted sub-goal.
- Record the PR # on the ROADMAP row the moment it opens; a checked box is `- [x] ... PR #N` or it is not checked.
- CI green means `gh pr checks` on the open PR, not local tests.
- Never merge PRs; merging is the human's gate. Sequential deps mean you may be waiting on a human merge: mark blocked, hop or stop.
- Done= lines and outcomes are immutable; deviations go in the sub-goal file's ## Notes.
- No new sub-goals mid-loop; discoveries go to NOTES.md ## Proposed additions.
- Stop only when: all boxes checked with PRs, or every remaining sub-goal is blocked with unchanged prerequisites, or the budget is exhausted. Anything else: keep moving.
- Before claiming success: extract every PR # from ROADMAP.md, `gh pr view` each (state, reviewDecision, checks); any failure invalidates that box.
- On any stop append a final summary block to NOTES.md ## Event log. Blockers live in ## Active blockers, fingerprinted (command · failure · prerequisite · last verified), updated in place; retry a blocked item only when its prerequisite changed.
- Each sub-goal verifies with ITS OWN close-the-loop commands from its goals/ file, never a generic test run.
- On repeated fast-stops emit only a short `🛑 LOOP BLOCKED — STOP /goal MANUALLY` banner; do not re-append summaries.

Defaults: address reviewer feedback inline on the affected PR's branch; fix-then-retry CI twice before marking blocked; pre-flight each sub-goal (if its Done= is already true, check the box and move on); heartbeat to the Event log if hours pass with nothing to log.

Before marking the mega-goal complete: draft a single-paragraph ops-toolkit `_meta/LAB_LOG.md` entry covering the arc (slug, sub-goal count, PR range, key lessons) and open a small ops-toolkit PR carrying it plus the final ROADMAP state. Then mark complete.
