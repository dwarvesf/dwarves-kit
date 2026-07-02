# Lane-classify rule-correctness audit (SPEC-098, kit-telemetry SG-03)

Date: 2026-07-02
Board: ops-toolkit ID-149 (narrowed remainder: the lane-classify RULE audit; the
verifier-coverage + under-gating halves shipped in kit-hardening SG-04/05/06)
Method: audit the task-shape -> lane rules in `lib/lane-classify.sh` against RECORDED
reality (the ledger misfire corpus) + a rule-correctness spot-check on the task shapes
that actually occurred in the kit-hardening + kit-telemetry waves.

## Part 1: recorded-misfire disposition

Capture (`bash lib/lane-telemetry.sh misfires`, floor-check section):

| Misfire signature | Count | Distinct? | Disposition |
|---|---|---|---|
| `chosen=tiny suggested=full \| add user authentication with jwt sessions` | 9 | **No** , byte-identical text, only the timestamp differs | **operator-error / test-fixture noise, NOT a rule fault.** The string is a canonical TEST fixture (test-lane-escalation / test-hooks / the escalation examples); those `check` calls reached the real `completeness.log` because some ran without `DWARVES_KIT_LOG_DIR` set. Already filed as **ID-087** (SG-02 bonus). No rule change. |
| lane-misrouted (chosen != classified) among tracked runs | 0 | , | `lane-telemetry.sh report` headline `lane-misrouted: 0`. Zero real operator lane-misroutes recorded. |

Key point: the one repeated signature is the classifier working **correctly** , "add user
authentication" hits the `auth` hard-gate -> `suggested=full`, and the floor-check rightly
WARNED that a `tiny` choice was under-sized. The rule is right; the noise is a test writing
to the real log. So the recorded-misfire corpus yields **zero confirmed rule faults**.

## Part 2: rule-correctness spot-check (occurred shapes)

A clean recorded-misfire corpus does not mean the rules are correct , the untracked-run
gap (SG-02 metric 3, ID-085) means most runs never recorded a chosen-vs-classified pair to
misfire in the first place. So I ran the ACTUAL occurred task shapes (the 8 kit-harden +
5 kit-telem sub-goals) through the live classifier and checked each landed in the right lane.

**Confirmed rule-gap (CONFIRMED, fixed):** the `kit-machinery` hard-gate regex covers
`gate-ledger / ship-gate / lane-classify / proof-gate / task-type-classify / goal-registry /
dispatch-gate / backlog.sh / install.sh / adopt.sh / workflow.md` but MISSED four libs that
are equally enforcement/telemetry machinery:

| Occurred shape (real sub-goal) | Before | After fix |
|---|---|---|
| `add a render subcommand to lib/lane-telemetry.sh` (SG-04) | normal | **full** |
| `add a code-level guard to lib/mega-merge.sh` (SG-05) | normal | **full** |
| `log overrides in lib/proof-ledger.sh` (SG-01) | normal | **full** |
| `durable resolver in lib/kit-log-dir.sh` (SG-01) | normal | **full** |
| (control) `fix the parser in lib/gate-ledger.sh` | full | full |

Disposition: **rule-gap**. These four libs are as load-bearing as `gate-ledger`
(mega-merge = auto-merge enforcement; proof-ledger = the proof-of-done gate;
lane-telemetry = the eval's data source; kit-log-dir = the durable-storage substrate).
Work on them should size to `full` like the other machinery. **Fix:** add the four
basenames to the hard-gate regex (SPEC-098). Precedence (backfill > tiny > hard-gate)
is untouched, so a cosmetic edit to one of these libs still classifies `tiny`.

Pinned in `tests/test-lane-classify.sh` (AC1-AC6): the four now escalate to full; a
cosmetic edit stays tiny (negative control); previously-covered machinery + a plain
feature are unchanged.

## Rules deliberately NOT changed (audited, held)

- `auth` -> full: works (the 9 downgrades prove it fires correctly). No change.
- tiny / backfill precedence (a typo about auth is still tiny; an in-doc keyword does not
  escalate a doc task): audited, correct, untouched , changing it would over-gate.
- soft-flag counting (2-3 -> normal, 4+ -> full): no recorded shape misfired on it; no
  speculative change (YAGNI, per the contract's "no speculative rules for shapes that
  never occurred").
- No new lanes, no classifier rewrite.

## Outcome

Not a purely clean audit: the recorded-misfire corpus was clean (0 real faults, evidenced
by the fixture-only downgrade capture), but the occurred-shape spot-check found ONE real
rule-gap (kit-machinery under-coverage of four enforcement libs), now fixed + pinned. The
cross-repo ops row **ID-149** flips at the mega-goal close (noted in NOTES).
