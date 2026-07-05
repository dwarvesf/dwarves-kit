# Sub-goal 03: harvest-quota-verify

**Merge policy:** gate (the keep/disable/down-rate call is a cost/benefit judgment on real data, not a binary test)
**Time budget:** measurement window may span a day; ~1-2 hours of active loop work plus wait
**Depends on:** none
**Branch:** feat/cctoken-03-harvest-quota
**PR base:** main

## Outcome

The cc-harvest header claim, "Haiku adds no new cost because the transcript is already in an Anthropic session", is empirically settled. A before/after measurement answers whether each `claude -p --model haiku` extractor call consumes Max-plan usage / weekly rate limit / 5h-window quota, and a keep / disable / down-rate decision is recorded (with the gating change committed if the answer is "it costs").

## Quality bar

The assertion that has sat unverified in the tool header since day one gets a real number behind it. If Haiku eats quota, the tool is gated or down-rated, not left on a hopeful comment. If it does not, the exemption is documented so nobody re-litigates it.

## How to close the loop

Route through the kit: `lane-classify classify "measure whether cc-harvest's Haiku extractor consumes Max-plan quota and gate if so"`, run its gates. The throttle (<=1/hour, PR #432) already exists; this is the measurement + decision half only.

Sub-goal-specific verification:
- Establish a baseline: cc-observe report over a window with the harvest extractor disabled (or its stamp-file forcing skips), then a comparable window with it enabled. Compare Haiku-model token/usage attribution.
- Cross-check against any native usage signal available (the 5h-window / weekly limit indicator) to confirm whether `claude -p` invocations count against the plan ceiling.
- Record a before/after run-table (the literal commands, the measured Haiku token deltas, the conclusion) and the decision.
- If it costs: commit the gating change (a disable flag or `CC_HARVEST_EXTRACTOR` down-rate / skip), with a test, and capture it.

**Done =** `tools/cc-harvest/docs/proof-of-done.md` gains a "quota impact" section with a real before/after run-table (commands + measured Haiku usage deltas) answering whether the extractor consumes Max-plan/weekly/5h quota, plus a recorded keep/disable/down-rate decision (and, if "it costs", the committed gating change + test).

## Scope edges

**In:** the measurement, the cc-harvest proof-of-done quota section, and only-if-needed a gating/down-rate change in `tools/cc-harvest/bin/cc-harvest`.
**Out:** the throttle (already shipped), the audit (01), cc-observe (02), the global CLAUDE.md (04).
**Not:** do not re-implement the throttle, do not add a new extractor model option beyond a disable/down-rate switch, do not change the harvest's staging format.

## Where to look

`tools/cc-harvest/bin/cc-harvest` (the Haiku extractor call + the existing throttle), `tools/cc-harvest/docs/proof-of-done.md`, and cc-observe / any native usage-limit signal for the measurement.

## PR body

Settles ID-152 part 2: measures whether cc-harvest's `claude -p --model haiku` extractor consumes Max-plan/weekly/5h quota, with a before/after cc-observe run-table, and records a keep/disable/down-rate decision (gating change committed if it costs). The throttle (part 1) already shipped in #432.

Verify: open `tools/cc-harvest/docs/proof-of-done.md` "quota impact" section, confirm the before/after run-table + the decision.

Roadmap: `_meta/megagoals/cc-token-reduction/ROADMAP.md`.

## Notes
