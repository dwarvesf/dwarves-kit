# NOTES, harness-loop

## Active blockers

(none)

## Proposed additions

- 2026-07-12: sub-goal idea, capture the missing retro for the kit-modularity/harness-ops cycles (docs/retro has nothing after 2026-07-04), discovered during brief drafting, /kit:retro is interactive human Q&A, so it needs Han live, not the loop; run it once alongside this mega's own close-out retro.
- 2026-07-12: sub-goal idea, `learned-ledger` flush paydown (~140 queued rows, 1 flushed since 2026-06-14), discovered during the mechanism audit, the flush is the learning-ledger skill's job (operator-side, ADR-0031); SG-05 only SURFACES the count. A weekend session that drains it is Han-time, not loop work.
- 2026-07-12: successor idea, Hermes cockpit cards for `learn propose` output (Decision H mirror, auto-improvement design doc), deferred; the staging file + board are the v1 surface.
- 2026-07-12: sub-goal idea, merge ADR-0034's module-to-leg table and SG-08's env/key registry into ONE module-metadata source that both `config list` and the README render from, discovered during advisor P6, two hand-maintained module tables is the same drift class as the agents-11-vs-25 bug; not blocking this mega, fold when one of them next changes.

## Advisor dispositions (P5 2026-07-12)

Applied: #1 CRITICAL (SG-10 deps += 08,09; net-chain marked illustrative), #2 (SG-04 handoff), #3 (SG-06 expiry pinned to lib/learn, never kit.toml), #4 (SG-08 source = fresh self-derived sweep), #5 (SG-09 rung 3 live re-execution), #6 (SG-01 handoff += 08), #7 (ROADMAP assumption 2 notes the stale SPEC-193/194 mentions), #8 (SG-10 parity scope names lib/stats/skill explicitly). #9 accepted noise: the missing 07-04+ retro stays a NOTES idea by design (needs Han live; deliberately ungated). P6: #1-#4, #6, #8 folded into SG-02/05/06/08/09; #5 folded into SG-07 (counter footer); #7 recorded above.

## Event log

2026-07-12 · scaffold created · 10 sub-goals, brief v2 (decisions resolved), pending advisor P5/P6 pass + Han's SG-01 gate
2026-07-12 · advisor pass · P5: 1 CRITICAL + 4 MAJOR + 4 MINOR, all applied or dispositioned (facts verified clean: PR #226, paths, ADR-0034/SPEC-193..199 free); P6: 8 suggestions, 7 folded, 1 recorded as proposed addition. See ## Advisor dispositions.
2026-07-12 · scope amendment 2 (Han review) · four-concern check: telemetry presentation already covered (SG-07/10); memory staleness = ID-100's job, SG-05 gains the weekly memory-sweep tripwire; ledger/db config = SG-08 registry now names [ledger] + STATS_* keys, ADR gains retention position (area 10); post-loop improvement circuit made explicit in brief §3.4 (promoted rows ride the normal board->lane path; process/harness/skill = three channels).
2026-07-12 · scope amendment (Han review) · three fragmentation flags folded in: bin/ mixed-grammar sprawl (11 entries, session-* x5, orphan add-backlog, missing subsystem entries), thin/undecided skills surface, plist-per-job daemon sprawl. Brief gains §4.7-4.9; SG-01's ADR becomes census + target-state (9 decision areas); SG-04 renamed learn-subsystem -> surface-consolidation (executes the full bin/skills regroup, ~1 day); SG-10's daemon leg becomes the ONE weekly scheduler (dispatcher + jobs list, per-job plists retire).
