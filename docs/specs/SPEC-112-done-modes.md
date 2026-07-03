# SPEC-112: UI done-modes + quiescence loop

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

`/kit:ui-design`'s Phase B (Step 5) is a single bounded auto-revise loop (max 2 regenerations)
with one fixed rigor. A UI sub-goal cannot declare HOW MUCH verification it owes: a trivial tweak
and a flagship surface get the same treatment, and there is no "polish until the critique stops
finding real issues" mode. The mega-goal (roadmap: ops-toolkit `_meta/megagoals/kit-face/`,
assumptions 07) resolves this with three declared done-modes, consumed as a `/kit:ui-design`
`$ARGUMENTS` flag.

## Solution

Three done-modes; **proof is the mandatory floor, over-test + quiescence are opt-in escalations
chosen per UI sub-goal at decompose time** (proof if unspecified):

1. **proof** (default) , the current bar: real-surface flows + 2-3 captures + a11y. Every UI
   sub-goal gets at least this.
2. **over-test** , proof + a `/kit:test-plan` matrix + `/kit:verify` execution + a COVERAGE-DELTA
   row (ACs-covered / tests-added, before-vs-after) appended to the proof-of-done run-table.
3. **quiescence** , Phase B EXTENDED into a converging loop: critique -> apply accepted fixes ->
   re-render -> re-critique. **Stop when a round yields zero NEW findings >=HIGH AND no OPEN
   finding >=HIGH remains** (two-sided by design), or at round cap 3. The loop lead carries a
   cross-round dedup ledger in-session; each round emits a `[[QL-VERDICT round=N clean=BOOL
   findings=K]]` marker (test-plan-review-team precedent) and tags each finding `[resolved in
   round N | OPEN]`; sub-floor (<HIGH) + capped-out findings land in a `### Deferred findings`
   subsection of the spec's `## Visual critique`. **Authorship (spec-validate F2):** the ui-design
   LOOP LEAD appends `### Deferred findings` to the FINAL `## Visual critique` AFTER the loop
   terminates , an explicit carve-out to ui-design's "do not write `## Visual critique` yourself"
   rule (ui-design.md Step 3), because visual-team REPLACES that section every round and is
   single-pass stateless (it cannot hold the cross-round deferred ledger, which is the loop lead's
   in-session state). Appending post-termination avoids round N+1's replace eating it.

**Final acceptance stays `gate` in every mode** , taste ships past the human eyeball only.
`visual-team` stays single-pass stateless (quiescence extends ui-design's loop, not visual-team).

**The two-sided stop is load-bearing (the named NC).** "zero NEW" ALONE falsely quiesces when a
round re-finds an unresolved CRITICAL (it is not NEW, but it is OPEN and >=HIGH); the "AND no OPEN
>=HIGH" clause pins this. Severity floor is >=HIGH (the kit has no MAJOR): the BLOCKING threshold
sits one notch HIGHER than test-plan-review-team's "only LOW remain" (HIGH vs MEDIUM) , MEDIUM/LOW
findings DEFER rather than block (they land in `### Deferred findings`), so the loop converges on
the high-severity surface, not cosmetic churn. The strictly-falling-findings guard
(test-plan-review-team) is deliberately NOT adopted , the two-sided severity stop + hard cap 3
already bound the loop, and a round that resolves a CRITICAL while surfacing a new MEDIUM is
progress, not a stall.

**Cap divergence (a DEC).** quiescence caps at 3 (test-plan-review-team parity); the plain REVISE
loop keeps cap 2 (fix-agent parity) , recorded as DEC-018 so the divergence is not read as an
inconsistency.

`Done-mode:` becomes a subgoal-template field (dotfiles half), next to `Proof:`.

## Verification

```bash
cd dwarves-kit
# Done-mode flag consumed + branches per mode (the wiring gate: ui-design reads the flag)
grep -qiE 'Done-mode' commands/ui-design.md
grep -qiE 'proof|over-test|quiescence' commands/ui-design.md
# quiescence stop condition is TWO-SIDED (the no-false-quiescence NC): zero NEW >=HIGH AND no OPEN >=HIGH
grep -qiE 'zero NEW.*>=?HIGH.*(AND|and).*no OPEN.*>=?HIGH' commands/ui-design.md   # full conjunction, no one-sided escape
grep -qiE 're-found|re-find|still OPEN|does NOT quiesce|falsely quiesce' commands/ui-design.md   # the NC is stated
# QL-VERDICT markers + resolved/OPEN tags + Deferred findings subsection
grep -qF '[[QL-VERDICT' commands/ui-design.md
grep -qiE 'resolved in round|OPEN\]' commands/ui-design.md
grep -qiE 'Deferred findings' commands/ui-design.md
# cap divergence: quiescence 3, plain REVISE still 2 (regression control) + the DEC
grep -qiE 'cap.*3|round cap 3|3 rounds' commands/ui-design.md
grep -qiE 'max .?2|cap .?2' commands/ui-design.md   # plain REVISE unchanged
grep -q 'DEC-018' docs/specs/SPEC-112-done-modes.md
# over-test coverage-delta row defined
grep -qiE 'coverage.delta|ACs-covered|coverage delta' commands/ui-design.md
bash tests/test-meta.sh   # green incl. the SPEC-112 ui-design done-modes pins
# The fixture TRACES (the goal's crux proof) are pinned in the proof-of-done, not just the contract:
grep -qiE 'converge' docs/verification/done-modes.md                 # fixture 1: round 2 stops clean
grep -qiE 'cap|round 3' docs/verification/done-modes.md              # fixture 2: never-satisfied critic caps at 3
grep -qiE 're-found|does NOT quiesce|falsely' docs/verification/done-modes.md   # NC: re-found CRITICAL does not quiesce
grep -qiE 'plain REVISE|cap 2' docs/verification/done-modes.md       # regression: plain REVISE still 2
# dotfiles half (local): Done-mode field in the subgoal-template
grep -qiE '^\*?\*?Done-mode' ~/workspace/tieubao/dotfiles/home/dot_claude/skills/plan-for-mega-goal/references/subgoal-template.md
```

## After state

- `commands/ui-design.md`: a Done-mode `$ARGUMENTS` flag (proof|over-test|quiescence); Phase B gains
  the quiescence branch (two-sided stop, cap 3, QL-VERDICT markers, resolved/OPEN tags, `### Deferred
  findings` subsection); over-test defines the coverage-delta row; plain REVISE unchanged (cap 2).
- `docs/specs/SPEC-112-done-modes.md`: DEC-018 (the 3-vs-2 cap divergence).
- dotfiles `plan-for-mega-goal` subgoal-template: a `Done-mode:` field next to `Proof:` (applied +
  committed atomically per the S-64 watcher rule).
- `tests/test-meta.sh`: SPEC-112 pins (flag consumed, two-sided stop, QL-VERDICT, Deferred findings,
  cap divergence, coverage-delta).
- `docs/verification/done-modes.md`: the run-table incl. the three quiescence fixtures + the
  plain-REVISE regression.

## Scope edges

**In:** ui-design.md Phase B (quiescence mode + Done-mode arg + Deferred-findings subsection), the
cap DEC, the coverage-delta row definition, the dotfiles template field, tests.
**Out:** visual-team internals (stays single-pass stateless; 06 owns its only change); the advisor
(its ADR-0028 station is the final boundary, NOT inside this loop).
**Not:** a numeric combined score (ui-design bans inventing one); unbounded polish loops; auto-
accepting critique fixes without the per-round approval Phase B already has.

## Open questions

The three quiescence fixtures (converge / cap-out / no-false-quiescence) are grep-pins on
ui-design.md's prose (ui-design is a prompt with no shell dispatcher, the same SPEC-078/107/109/111
fidelity; visual-team + ui-design are not in CI). The load-bearing no-false-quiescence NC is pinned
structurally: the stop condition text MUST carry the two-sided "zero NEW >=HIGH AND no OPEN >=HIGH"
clause + an explicit statement that a re-found unresolved CRITICAL does not quiesce. The behavioral
loop itself runs downstream (the kit has no UI to dogfood it); the pins prove the CONTRACT is
present + two-sided, not a live convergence run.
