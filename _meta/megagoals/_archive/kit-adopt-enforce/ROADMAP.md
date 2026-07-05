# Mega-goal: kit-adopt-enforce

**Destination:** Adopting a repo into the dwarves-kit is one command, and a full-lane change cannot ship review-less because lane + loop-type classification drives the gates.
**Quality bar:** Adoption is one command and the guardrails actually bite. A repo that ran the adopt cannot quietly ship a full-lane change without its lane's gates; the agent is told to classify + pick a lane before touching code, and skipping review is a blocked push, not a polite suggestion. It wires what already exists: no rebuilt classifiers, no new taxonomy.
**Stacking tool:** gh (sequential; ghstack/Graphite absent)
**Started:** 2026-06-09

## Sub-goals

- [x] 01-adopt-command, `/kit:adopt` injects the operate-contract + wires the classifiers, PR #22 (MERGED to dwarves-kit master)
- [x] 02-gate-fail-closed, ship-gate fails CLOSED on spec-exists-no-lane; install.sh uses adopt, PR #23 (MERGED to dwarves-kit master)
- [x] 03-ops-toolkit-adopt, ops-toolkit adopted; the growatt-tui review-less push is now BLOCKED by the gate, PR #163 (MERGED to ops-toolkit main)
- [x] 04-install-ships-contract, install.sh ships AGENTS.md + WORKFLOW.md so adopt + gate-ledger work from the INSTALL (the self-install gap), PR #24 (MERGED to dwarves-kit master; applied live; test-install-contract 3/3 + meta 395/395)
- [x] absorb-harness, A1 (@AGENTS.md import loader) + A2 (--dry-run/--refresh) absorbed from hoangnb24/repository-harness; absorption report proposal-only, PR #25 (MERGED to dwarves-kit master)

## Dogfood result (2026-06-10): the review lane bit, as designed

PRs #24 + #25 were run back through the kit's OWN 3-lens review-team before merge (the dogfood). It caught real blockers, not theatre:
- PR #25 CRITICAL (3 reviewers independently): `--refresh` awk strip ate the rest of CLAUDE.md when the END marker was missing. Fixed: refuse-on-missing-END guard + awk EOF backstop + exact-line marker match + atomic WORKFLOW write + cmp-before-"updated". test-adopt 8 -> 12.
- PR #24 HIGH x2: install `rm -f` could destroy a user's real AGENTS.md/WORKFLOW.md (now symlink-only, skip real files); tests simulated the layout but never ran install.sh (test-meta now asserts the real install + uninstall). meta 392 -> 395.
Both fixed through respond-to-review, re-verified with live proof + negative control, recorded in dwarves-kit `docs/verification/{kit-adopt,install-ships-contract}.md`. This is the point of the gate: a full-lane change does not ship review-less.

## Proposed follow-ups still open

- sub-goal 05 (dwarves-kit): ship-gate should resolve the active spec without coupling to the branch slug (see NOTES.md `## Proposed additions`). LOW.
- A3 (dwarves-kit): the 10-flag risk checklist + count-based lane tree from repository-harness. This cycle's review confirmed the need: `lane-classify` under-classified both kit-machinery PRs as `normal` when they were `full`. MED. See dwarves-kit `docs/absorption/2026-06-10-repository-harness.md`.

Destination now fully holds: with sub-goal 04, `/kit:adopt` + the lane gate work from the install, so the kit self-installs and self-enforces per-repo.

## Dependencies

- 02 depends on 01 (install.sh's adopt path calls the new `/kit:adopt` command)
- 03 depends on 01 + 02 (both MERGED to dwarves-kit master, so the installed kit carries the command + the fail-closed gate)

## Repos

- 01, 02 -> `~/workspace/tieubao/dwarves-kit` (SHARED repo: branch + PR, never merge, needs Han's nod)
- 03 -> `~/workspace/tieubao/ops-toolkit` (personal)

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "$pr" --json state,reviewDecision,statusCheckRollup
    done
