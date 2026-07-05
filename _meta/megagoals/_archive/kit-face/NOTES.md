# NOTES , kit-face

## Active blockers

<none yet>

## Proposed additions

- 2026-07-03: follow-up (filed by design, NOT scope) , dispatch-count ACTION line (`gate-ledger.sh action "$RID" "dispatched <agent>"`) at named-agent dispatch points, the missing half of metric 11's "first-N dispatches follow-through". Deliberately cut from 05 v1.
- 2026-07-03: instrumentation , 03's TOKENS lines + the tracked corpus make the NEXT eval re-run (SPEC-073) able to price sub-goals in tokens; re-run the eval after this wave + 5 tracked runs.

- 2026-07-03: TIER-4 advisor (over-suggest) , 9 grounded follow-ups the wave left on the table (proposals only, NOT built):
  1. **Pin architecture.md:77 prose count** (S) , the V-phase table rows are pinned (SPEC-113) but the human-readable "Total: 25 commands + 15 agents = 40 entries" prose is untested + stale (now 27+24=51). Exactly the drift-class the quality bar swore off; extend the computed pin to the prose line.
  2. **Per-round rework-share** (M) , 03 shipped run-granularity v1; the sidechain probe showed per-round is possible. Attribute bug-lane tokens per round.
  3. **Automate metric-11 catch-count as a lane-telemetry subcommand** (M) , SPEC-073 metric 11 is a manual grep; make it command-backed (AC2).
  4. **Extend the SPEC-111 domain-reviewer lens to `/kit:review`** (S/M) , the 4 domain reviewers dispatch only from `/kit:review-team`; solo `/kit:review` never classifies the diff domain. Thread `role-classify` into review.md too.
  5. **Watchdog-path token capture** (M) , 03 left the watchdog/timeout path a declared gap; runaway runs (the expensive ones) record no TOKENS. Capture partial usage before termination.
  6. **Bridge manual/non-orchestrated runs into token accounting** (M/L) , manual runs report `usage=?`; a thin ccusage/ops-toolkit ingest closes it without touching SPEC-087's default-path pin.
  7. **Thread persona into ui-design GENERATION** (M) , 06 shipped critique-only; feed the `Persona:` brief line into the frontend-design generation delegation.
  8. **Extract the bounded quiescence loop to a `lib/` primitive** (M) , 07's Phase-B loop + test-plan-review-team both run cap-3 converge-or-cap; share it to avoid per-command drift.
  9. **Give `### Deferred findings` a lifecycle** (S/M) , 07 parks capped-out findings; route them to the board / a re-check list so a capped-out HIGH does not rot.
- 2026-07-03: TIER-4 deep-security LOW notes (defense-in-depth, unreachable with untrusted input, NOT built): (a) `lane-telemetry.sh:356` mermaid label not quote-escaped (lane names are fixed-vocabulary/operator-only; impact = broken diagram, not exec); (b) `visual-team.md:33` operator `persona:` arg not fenced like fetched content (operator-liability by design). Optional hardening follow-ups.

## Event log

2026-07-03 HH:MM · scaffold · kit-face mega-goal created from operator asks + a 3-miner framing harvest (25 questions: 21 repo/recommendation-resolved, 4 asked, AFK-defaults taken). 8 sub-goals, gh-stacked + auto-bottom-up + gated-final (08-release is the gate), cross-repo halves in dotfiles (04, 07).
2026-07-03 HH:MM · reshape (operator review) · (1) docs 01+02 moved to run LAST (depend on all machinery), so they reflect final state instead of drifting; (2) Done-mode clarified: proof = mandatory floor, over-test/quiescence = opt-in escalations; (3) meta-agent placement verified correct (no move); (4) added 09-role-agents (8 domain agents, MIXED reviewer/worker per operator, each effectiveness-gated, reconciles SPEC-089). Now 9 sub-goals. Execution: {03,04,05,06,09} -> 07 -> {01,02} -> 08.
2026-07-03 HH:MM · reshape (wiring gate) · operator: ensure post-implementation artifacts are WIRED to the workflow, not orphaned. Added a cross-cutting WIRING GATE to the quality bar (per-sub-goal invocation proof + WORKFLOW.md honesty + a TIER-4 no-orphan check), grounded in kit-hardening's c6fbd99 (3 agents defined but never dispatched). Code check found execute.md 2b-0 ALREADY has the role-specialist dispatch path (reuse-known-first, synthesize-novel-fallback), so 09's SPEC-089 collision is lighter than first written: 09 POPULATES 2b-0's reuse lookup rather than amending SPEC-089's design; the wiring proof is a reuse HIT per agent.

2026-07-03 HH:MM · COMPLETE (loop terminus) · All 8 sub-goals shipped. MERGED: 04 #128 c4b6032, 05 #129 cf0dc73, 06 #130 f9981b4, 03 #132 6be7d9c, 09 #133 03620ac, 07 #134 2a3c021, 01 #135 9274b15, 02 #136 c1cd13e. HELD (gate+final): 08 #137 OPEN , v2.0.0 PREPARED (changelog + BREAKING 3-rename + 3 surfaces at 2.0.0 + 3-surface pin + tag/Release/held-review files under docs/releases/v2.0.0/); Han tags + `gh release create`, the loop never did. Order run: {04,05,06,03,09} machinery -> 07 -> {01,02} docs -> 08. TIER-4: no-orphan CLEAN + security SECURE + advisor 9 follow-ups (above). Every sub-goal: spec -> adversarial spec-validate (found real MAJOR/HIGH on 03/04/05/06/07/09, all folded) -> build -> proof-of-done -> both-runner CI green -> gated merge; success audit re-confirmed all 8 PRs (128-136 MERGED green, 137 OPEN green). Cross-repo: dotfiles 9dd5c48 (04) + ac2c6a4 (07); stray unpushed Fable ADR-0032 preserved on branch adr-0032-megagoal-hygiene (kept out of the wave). No open blockers.

2026-07-03 HH:MM · 08 MERGED, TAG DEFERRED (operator) · PR #137 merged e375e57: the v2.0.0 release CONTENT is now on master (VERSION/plugin.json/tool.toml all 2.0.0, CHANGELOG [2.0.0], BREAKING 3-rename map, docs/releases/v2.0.0/ files). Per operator "merge but not bump the tag": NO v2.0.0 git tag + NO GH Release cut , those stay Han's call (`git tag -a v2.0.0 -F docs/releases/v2.0.0/tag-message.txt` + `gh release create`). All 8 sub-goals now merged; the loop's terminus is reached. dwarves-kit local branches cleaned (8 feat branches deleted + pruned); kept adr-0032-megagoal-hygiene (preserved stray ADR) + flagged the stray origin branch docs/adr-execution-hygiene.
