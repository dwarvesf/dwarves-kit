# flick shadow phase: agreement report (wrap-7b)

Verdict: NOT ready. The shadow log holds 0 real wrap-7b pairs. Agreement on the 32 logged rows is 7 of 22 (31.8%), against a 90% bar. Promotion stays off.

Source: `decide.jsonl` in the shared log dir, 32 lines, 2026-10-01 06:19Z to 17:07Z. Contract: `docs/specs/SPEC-381-flick.md`, section "Exit criterion".

## Who labels

The spec, not Han, defines the label. The exit criterion reads "agreement with the lead's verdict". Step 7b has the lead (the wrap session) write `existing` into every request, and flick logs it beside `chosen`. So the label is the session's own verdict, captured at call time. An agent may supply it. Han's judgment is not the ground truth here.

Consequence: agreement is a mechanical comparison of `chosen` against `existing`. No after-the-fact labelling was needed, except one row noted below.

## Where the 32 rows come from

All 32 rows are smoke runs of 2026-10-01, not wrap sessions. They carry four invented slugs and one fixture client name, repeated. No log line is newer than that day (checked 2026-10-05), and the wrap-session count since then was not measured.

| Candidate | Hit | Rows | Answered | Agree | chosen | existing |
|-----------|-----|------|----------|-------|--------|----------|
| backlog-flip-script | board | 7 | 7 | 0 | none, new | enhance (one row blank) |
| merge-own-pr-loop | wrap | 6 | 6 | 0 | none, new | enhance |
| photo-resize-helper | board | 10 | 8 | 5 | none, new | new |
| acme-sync | board | 4 | 2 | 2 | new | new |
| (denied, no text logged) | none | 5 | 0 | 0 | none | none |

Row outcomes: 23 answered, 5 `egress_denied` (3 `guard`, 2 `word_gate`), 4 `no_token` (token wiring not yet live at 09:03Z). Four distinct pairs make up 27 rows. Repeats of one pair are not independent samples.

## Agreement

| Basis | Agree | Of | Rate |
|-------|-------|----|------|
| Answered rows that carry `existing` | 7 | 22 | 31.8% |
| Same, plus the one blank-`existing` row labelled below | 7 | 23 | 30.4% |
| Distinct pairs, latest answer each | 2 | 4 | 50% |
| Bar (SPEC-381) | | | 90% |

The 7 agreements are photo-resize-helper (5) and acme-sync (2). Both are the "unrelated tool" cases, where `new` is the easy answer. Both enhance-labelled pairs score 0 of 12.

Two caveats that make 31.8% a ceiling for decision quality, not a floor:

- The first 9 rows ran at 06:19Z, before the 07:19Z template change that the handoff calls the fold. They answered `none` for everything and drag the rate down. Rows 10 onward (post fold): 7 of 13 answered rows with `existing`, or 53.8%. Still well under 90%.
- The `existing` labels on the fixture pairs were set by the smoke script's author, not by a wrap session judging a live precedent hit. They are plausible labels, not session verdicts.

## The one row labelled here

Row 29 (2026-10-01T12:28:51Z): candidate `backlog-flip-script`, hit `board`, `existing` blank, flick `chosen` = `new`, margin 0.05 (a near tie). Label assigned: `enhance`. Rationale: the `board` tool owns flipping backlog rows, so a script that flips them is the job `board` already does or could own. This matches the label the same pair carries in six other rows. flick disagrees. It is counted in the second row of the agreement table only.

The five denied rows log no candidate or hit text (by design), so they cannot be labelled and are not counted.

## Count still missing

| Need | Have | Missing |
|------|------|---------|
| 50 labelled real wrap-7b pairs | 0 real, 4 distinct fixture pairs | 50 |

The spec counts pairs, and 27 smoke rows over 4 pairs do not satisfy "50 labelled pairs". If the 22 labelled smoke rows were generously counted, 28 would still be missing.

## Why no real pairs landed

Open question, not diagnosed here. Config is on (`backend = "jev"`, `mode = "shadow"`, `points = "wrap-7b"` in the operator kit.toml), and the log dir is the default shared one (no `KIT_LEDGER_DIR` or `DWARVES_KIT_LOG_DIR` in the environment). Candidates to check, in order:

1. Wrap step 7b is skipped by sessions that close without a precedent hit to judge, so flick is never called.
2. The step is prose in `commands/wrap.md`, so a session can omit the call. Nothing enforces it.
3. Real candidate slugs fail the word gate and log as `egress_denied`. Those rows would still appear, so this does not explain an empty log.

Check 1 and 2 by counting wraps since 2026-10-01 that reached step 7b. A decision for Han: whether to keep waiting for organic pairs or to run a labelled batch of real candidate/hit pairs drawn from past wrap sessions.

## Other exit-criterion half

Zero private names in the sent slugs: the sent slugs are `backlog-flip-script`, `merge-own-pr-loop`, `photo-resize-helper`, `acme-sync`. None are private names. This half passes, on a sample too small to mean much.

## Not done

Promotion is not flipped. SPEC-381 says a later spec decides promotion, and this report supplies no evidence for one.
