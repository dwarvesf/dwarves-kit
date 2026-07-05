# NOTES: gate-review-absorptions

## Active blockers

(none yet; updated in place, one fingerprint per blocker: command · failure · prerequisite · last verified)

## Proposed additions

- (append-only; discovered sub-goals + skill/tooling friction land here, never inline)
- Candidate follow-on (draft-time): on an ADOPT verdict from 03, wire pl-gate into OPERATE.md/mega as the default human-gate surface (new row, not this run).
- Candidate follow-on (draft-time): gate-feedback compounding lens (ID-266, parked) reads the deny/feedback rows this run starts emitting.
- Candidate follow-on (advisor P6, 2026-07-04): `suggestion-yield` query mirroring 04's review-yield but over advisor P6 proposals (were they acted on?); joins against the advisor rows 06 starts emitting. Zero code this run.
- Candidate follow-on (advisor P5, 2026-07-04): lens-level review emit in the kit (per-lens `findings=` instead of the whole-review aggregate), which would upgrade 04's FP-rate from approximation to exact. Named follow-on, not this run.

## Event log

- 2026-07-04 RUN COMPLETE (build) + HELD (gate). Subagent-delegate, thin conductor, two parallel per-repo lanes, one worker per lane. Guard re-verified live (both siblings merged). Merged: 01 #172, 02 #173, 05 #697, 06 #174. HELD for gated-final: 03 #698 (gate; live pl-gate trial = the review), 04 #701 (ops-stack final, carries this close-out). SPECs dwarves-kit 143/144/145 + ops tool-local 137. Convergence machine-demos green: review-yield over real ledgers (`fp_rate_approx=0.25 approx=True low_n=True`) + a live review pass firing stale-ADR drift + previously-rejected surfacing + a novel finding on the same file, with a real SG-02 emit row. All load-bearing NCs proven by deliberate break. No worker kills. ~132 worker-min / ~76 wall-min, ~1.82M tokens, all sonnet. Full record: RUN_REPORT.md. Terminal STOP: NEEDS APPROVAL (03 + 04 held).
- 2026-07-04 advisor P5 (critique) + P6 (over-suggest) dispatched pre-launch at Han's request (the advisor-impact demo). P5 verdict was fix-first: 1 CRITICAL (04's FP-rate design assumed kit_gates columns that do not exist in the merged #683 schema; 04 rewritten to regex-extract from `reason`, per-run denominator, approximation labeled), 2 MAJOR (05's ID-246 conditional resolved to fact + mirror moved into scope; stale LAUNCH-HELD status fields refreshed), 3 MINOR (multi-repo mechanism named, suppressed=/rejected= disambiguated, 03's self-referential proof stated). P6: 6 suggestions, #1 adopted (actor= on all new emit grammars), #2/#3/#4/#5 landed as contract lines in goals/01/02/03, #6 filed above. All fixes applied same day; scaffold now LAUNCHABLE.
- 2026-07-04 drafted (5 sub-goals, two per-repo stacks; 06 added same day after the advisor-invisibility audit). LAUNCH-HELD until both sibling megas (harness-observatory, kit-absorptions) close: file overlap on kit commands, ledger-observatory, and OPERATE.md. Guard CLEARED same day (both siblings closed). Source analysis: research/2026-07-04-pxpipe-plannotator-improve-absorption.md.
