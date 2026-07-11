# Mega-goal: harness-loop

**Destination:** the Specify → Execute → Observe → Govern → Learn loop CLOSES: run ledgers get distilled on a weekly cadence into evidence-cited backlog proposals behind the unchanged human gate, a per-mega HTML dashboard becomes the sign-off surface, Learn machinery gets ONE named subsystem home (`lib/learn/` + `bin/learn`), and the front door (README, `/kit:onboard`, `bin/config`) finally tells the five-leg story with a config surface that shows provenance.
**Quality bar:** Propose, never dispose: every automated leg ends at a staging file or a rendered surface, and `add-backlog` + mega sign-off stay Han's. Every proposal cites lens + figure + rids, or it does not stage. No new diaries: each artifact this mega adds has a named reader or is a forcing function (process-audit R4/R6 rule). One word, one meaning: `retro` = per-run, `propose` = cross-run.
**Design source:** `docs/briefs/DECISION-BRIEF-harness-loop.md` (v2, decisions §5 resolved 2026-07-12)
**Stacking tool:** gh (STACKED PRs, switched from gh-sequential by Han 2026-07-12: a dependent sub-goal branches off its parent sub-goal branch, PR base = parent branch; independents off master; fan-in sub-goals base master after parents merge; each goal file PR-base field is authoritative)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-12 (drafted; launch pending Han's go on SG-01's taxonomy ADR gate)

## Sub-goals

- [x] 01-loop-taxonomy, ADR-0034 opens with a full surface CENSUS (bin/, skills/, daemons) + target-state tables, then locks naming/scope/modularity (learn subsystem, retro-vs-propose vocabulary, legs-as-metadata registry, front-door verb fences, `-propose` suffix, bin/ one-grammar consolidation, the kit-skill rule, the one-scheduler decision), `gate`, PR #236 (open + HELD for Han, per gate policy; Done = PR open, the gate click is Han's)
- [x] 02-outcome-emit-sweep, OUTCOME timing brackets wired at the missing gate call sites so `stats mega-durations` + digest time-to-done stop reading honest-zero, `auto`, PR #237, merged 76fbafe (2026-07-12; CI green both OS on PR head; proof docs/verification/loop-02-outcome-emit.md)
- [x] 03-harvest-dedup-land, PR #226 (harvest flock dedup) reviewed + merged, regression row 4c green on master, `auto`, PR #226, merged a6c5a9e (2026-07-12; post-merge suite 51/51 on master)
- [ ] 04-surface-consolidation, the ADR-0034 target surface becomes reality in one wave: `lib/learn/` + `bin/learn`; bin/ regrouped to one `<subsystem> <verb>` grammar (session-* 5->1, add-backlog -> `board promote`, missing spec/goal/stats/mega/queue entries created); stats skill relocated; all call-sites repointed (dotfiles companion PR), zero alias shims, `auto`, PR #239 (open, stacked on #236's branch; merges after #236; companions dotfiles#213 + ops-toolkit#796)
- [ ] 05-retro-cycle, `learn propose` (stats-window aggregate → sonnet interpret → adversarial check → cited, deduped staging) + the recurring `kit-retro-YYYY-WW` queue goal template + `[features] auto_improvement` flipped to [impl] with the SPEC-188 lint amended, `auto`, PR #
- [ ] 06-staging-drain, `learn drain` renders staging grouped + age-sorted + evidence-first; 30d rows move to `[expired]` (never deleted); promote/reject flow unchanged, `auto`, PR #241 (open, stacked on SG-04's branch; merges after #239)
- [x] 07-mega-review-dashboard, `mega review --html <slug>` composes the shipped stats render formatters into one static sign-off page, wired at TIER-4 close, `auto`, PR #238, merged c2eb239 (2026-07-12; CI green both OS; proof docs/verification/loop-07-mega-dashboard.md + 3 screenshots docs/proof/loop-07-mega-dashboard/)
- [ ] 08-config-surface, `bin/config list|get|explain` with provenance (env > project > kit-root > default) + status tags + the checked-in env↔key registry + drift lint, `auto`, PR #240 (open, stacked on #236's branch; merges after #236)
- [x] 09-onboard-wizard, `/kit:onboard` interactive first-run orchestrator (detect install mode, offer adopt, module picker, consumer-knob capture, plugin-gap disclosure, welcome tour), `gate`, PR #242 (open + HELD for Han, stacked on SG-08's branch; gate Done = PR open, the gate click is Han's)
- [ ] 10-front-door-truth, README reorganized around the five legs + tables truth-matched (agents 25, skills per ADR §8) + weekly digest folded into session-intel + the ONE kit scheduler (single weekly LaunchAgent + declarative jobs list; per-job plists retire), `auto` (held as final PR under gated-final), PR #

## Dependencies

- 01 first and GATED, gate = MERGE gate under stacked mode (Han 2026-07-12): 04/08 MAY build + open PRs stacked on `docs/loop-01-taxonomy` while Han reviews; NOTHING in that stack merges before #236 merges; an ADR redline rebases the stack (accepted tradeoff). Same rule for 09 stacking on 08.
- 02, 03 depend on nothing (run parallel to 01; disjoint Touches).
- 04 depends on 01 (subsystem name + move plan come from the ADR).
- 05 depends on 01 + 02 + 04 (vocabulary; timing data worth citing; the lib/learn home).
- 06 depends on 01 + 04. Parallel to 05 (disjoint files within lib/learn + board bin).
- 07 depends on 02. Parallel to 04/05/06/08.
- 08 depends on 01 (registry shape + verb fences). Parallel to 04-07.
- 09 depends on 08 (the wizard renders config via the surface it explains).
- 10 depends on 05 + 07 + 08 + 09 (docs LAST, documents EVERYTHING that shipped; its close-out proof includes a `config list` capture and the README/MANUAL index names `/kit:onboard`) and is the held final PR.

Net chain: {01 gate, 02, 03} -> {04, 07, 08} -> {05, 06, 09} -> 10. (Illustrative only; the scheduler reads each goal file's literal `Depends on:` field, per ADR-0030.)

## Assumptions (front-loaded, per the decompose checkpoint)

1. Decisions delegated by Han 2026-07-12 ("your call, prefer thorough") are FINAL for this run and recorded in the brief §5: weekly LaunchAgent cadence + on-demand verb; sonnet interpret + adversarial per-proposal check; 30d staging expiry; `/kit:onboard` command (install.sh stays non-interactive); per-proposal Home: board routing.
2. Spec numbers reserved up front (parallel branches collide otherwise): 02→SPEC-193, 04→SPEC-194, 05→SPEC-195, 06→SPEC-196, 07→SPEC-197, 08→SPEC-198, 09→SPEC-199. 01 is ADR-0034 (no spec), 03 is a merge, 10 is docs. Note: "SPEC-193"/"SPEC-194" were name-dropped but never filed in `_meta/megagoals/_archive/harness-ops/NOTES.md` and one old proof-of-done; those stale mentions are noise, the filenames are free (advisor P5 verified).
3. The kit-retro goal contract (`ops-toolkit/_meta/megagoals/kit-wiring/goals/kit-retro.md`) moves INTO SG-05 verbatim as the LLM leg's contract; kit-wiring (ID-273) loses that sub-goal (one engine, one truth). ID-273's row gets a pointer note when SG-05 ships.
4. Settled decisions this mega must NOT re-litigate: propose-don't-dispose (kit-foldin DECISIONS), hooks never read config (SPEC-183 lint), stats persists nothing (SPEC-182), no recurrence engine in the kit (PHILOSOPHY §3; date-suffixed slug is the mechanism), no new learning engine kit-side (ADR-0031), no CONSUMER_ROOT (board.sh:23), weekend-batch orchestration stays in the dotfiles skill (SPEC-126 split; SG-04 moves the FILE, not the split).
5. Terminus: build + merge + the consumer-side scheduler leg PREPARED (the ONE LaunchAgent plist + runbook committed consumer-side, loading is Han's click). Non-deployable otherwise; deploy/UAT gates beyond that are intentionally absent. Close-out = RUN_REPORT.md + 2-3 freeze-PNG proofs on the final branch.
6. Execution modes + parallelism: runnable via the /goal loop (POINTER_PROMPT) or the kit orchestrate/queue engine; under orchestrate, SPEC-106 waves fire by default (WAVE_CAP=2) on Touches-disjoint ready sub-goals (expected waves: {01-build,02,03} -> {04,07,08} -> {05,06,09} -> 10; 05/06 Touches are file-sliced to stay disjoint). The mega ENDS at the TIER-4 convergence gate (integration-verifier + review-team + advisor P5/P6 + recheck on the assembled tree, tier4_close=true), validated against git truth per the proof-ceremony-rot lesson, then the held final PR.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
