# NOTES , token-optim-v3

## Active blockers
(none) , the v2 SG-09 prerequisite cleared 2026-06-30. SG-06 is now fully runnable. SG-07 still
needs SG-02 + SG-04 built (it measures levers 01..04); v2 SG-09's threshold methodology is in place.
[cleared 2026-06-30] sub-goal 06: v2 SG-09 done (PR #601, ablation data committed) -> unblocked.
[cleared 2026-06-30] sub-goal 07: v2 SG-09 methodology present; remaining dep is SG-02 + SG-04, not SG-09.

## Proposed additions
- 2026-06-29: cross-agent presence view (pi-messenger-swarm overlay) , PARKED by Han 2026-06-29. One
  live view of active Claude background agents (mega-goal / loop / workflow / Hermes / OpenClaw).
  Overlaps v2 SG-01 (live stream) + SG-10 (board) + the existing vps-mon / menubar. Revisit if/when
  running many concurrent background agents makes the gap real; fold into vps-mon first, a dedicated
  TUI overlay only if that is insufficient.
- 2026-06-29: graduation , replace native /compact with the deterministic compactor. This is the
  FUTURE step of SG-04 (SG-04 ships the parallel command + writes the criteria). Promote to a
  sub-goal once SG-04's graduation criteria are met (N sessions A/B'd, zero load-bearing drops,
  recall covers any gap).
- 2026-06-29 [MOVED to its own mega-goal `kit-hardening`, Han 2026-06-29]: reconcile `plan-for-mega-goal` skill <-> dwarves-kit `/kit:mega` (SPEC-034). The skill
  has auto-merge (auto-bottom-up/gated-final), front-loaded questions, and deploy+UAT=done; the kit
  has NONE of these (loop never merges, human ships at /kit:ship; done = verified tasks; its mega
  lane is VALIDATED-not-shipped). Decide: the kit's mega lane ADOPTS the skill's three properties,
  or keep them intentionally separate (skill = personal aggressive autonomy, kit = conservative
  team-gated). Natural fit for the token-optim line since the orchestrator IS the subject. Surfaced
  by the 2026-06-29 kit-orchestration audit.

## Event log
- 2026-06-29: mega-goal scaffolded from the 2026-06-29 design session as the complement to
  token-optim-v2. Adopts pi-vcc (deterministic no-LLM compaction + lossless recall -> SG-01/02/03/04)
  and the claude-code-hooks-mastery meta-agent (SG-05 drafter now, SG-06 data-driven after v2 SG-09).
  pi-messenger-swarm overlay parked (Han). 7 sub-goals; 5 runnable now (01,02,03,04,05), 2 blocked on
  v2 SG-09 (06,07). Merge posture: auto for ops-toolkit-owned (01,03), gate for the rest. Execution
  via POINTER_PROMPT in a fresh /goal session; SG-01 first.
- 2026-06-29: kit-orchestration audit (read-only subagent over dwarves-kit) found the 3 mega-goal
  principles (auto-merge/minimal-gate, front-load questions, deploy+UAT=done) live in the
  `plan-for-mega-goal` SKILL, NOT in the kit (kit: loop never merges, human ships at /kit:ship;
  done=verified tasks; no front-load; `/kit:mega` is VALIDATED-not-shipped). Han chose to reconcile;
  promoted the reconcile to SG-08. Now 8 sub-goals; 6 runnable now (01,02,03,04,05,08), 2 blocked on
  v2 SG-09 (06,07). Also corrected: v3's gate-heavy posture on kit sub-goals is ALIGNMENT with the
  kit's human-ship rule, not over-gating (an earlier in-session claim was wrong).
- 2026-06-29: SG-08 (reconcile) MOVED OUT to its own mega-goal `kit-hardening` (it grew past a
  sub-goal: ADR-0028 + SPEC-088 + 3 sub-goals, the kit-side counterpart to v3). v3 back to 7
  sub-goals, pure context-engineering.
- 2026-06-30: cleared the stale SG-06/07 blockers. v2 SG-09 is done (box flipped, PR #601 held for
  Han's end-review, ablation data committed). SG-06 (data-driven-routing) fully unblocked; SG-07
  (proof-ablation) v2-SG-09 dep cleared, remaining dep is SG-02 + SG-04 being built. v3 status: 2/7
  shipped (SG-01 #598, SG-03 #599 merged); runnable now: 02, 04, 05, 06.
- 2026-06-30: SG-02 (deterministic-handoff) built + PR #90 opened (dwarves-kit, base master).
  Ported SG-01's no-LLM extractor into lib/handoff/, added lib/handoff-gen (two-tier formatter),
  wired orchestrate.sh behind DETERMINISTIC_HANDOFF=1 (default off = byte-identical). 8 new tests
  (TEST 13), 56/56 green; proof at docs/verification/v3-deterministic-handoff/. Box NOT flipped:
  this is a `gate` sub-goal AND AC8 (live turns-to-first-correct-action A/B over real Opus
  cold-resume sessions) is deferred to Han at the gate; determinism/fidelity/no-LLM/wiring are
  captured. STOP for Han.
- 2026-07-01: WAVE COMPLETE (open-only). Built + opened the 4 remaining sub-goals in one loop, merged
  nothing. SG-04 dotfiles #167 (/dcompact additive command), SG-05 dwarves-kit #91 (meta-agent
  drafter, 38/38 + kit guards 508/508), SG-06 dwarves-kit #92 stacked on #91 (data-driven routing,
  10/10, abstains because SG-09 data is haiku-only n=1), SG-07 ops-toolkit #608 (v3 ablation arms +
  pipeline validation 9/9, live Opus run gated on Han). All 7 sub-goals now merged-or-open: SG-01 #598
  + SG-03 #599 merged; SG-02 #90, SG-04 #167, SG-05 #91, SG-06 #92, SG-07 #608 open + held for Han's
  single end-review. LAB_LOG arc entry rides SG-07 #608 (SPEC-005). Before final close: run
  /kit:review-team across the merged set, then mark the mega-goal complete. STOP.
- 2026-07-01: applied latest plan-for-mega-goal + Han's "review at the end" directive. Merge
  posture for all remaining sub-goals changed to OPEN-ONLY / review-at-end: the loop opens each
  PR, merges nothing, and no longer halts at each gate, it continues to the next runnable sub-goal
  and stops once all are open + held for Han's single end-review. Preserves the kit human-ship rule
  (no auto-merge) while removing per-sub-goal interruption. Resolved via batched clarification
  (one interactive checkpoint): SG-04 = additive `/dcompact` SLASH COMMAND (not a hook), shipped in
  DOTFILES (~/.claude commands are chezmoi-managed). SG-05/06/07 had only dependent (resolve-at-
  execution) unknowns, nothing to pre-answer. Updated POINTER_PROMPT.md, ROADMAP header + Assumptions
  (Merge posture v2), and goals/04. Scaffold already had FEEDBACK.md + the merge knobs.
