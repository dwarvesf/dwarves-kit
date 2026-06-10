# SPEC-052: /kit:test-plan-review-team (adversarial test-design critique)

Status: Implemented
Date: 2026-06-09
Relates-to: SPEC-046 (verification framework, the spine + QL-VERDICT contract), SPEC-018 (test plan per spec, the `## Test plan` home + drift guard), SPEC-031 (V-model), SPEC-016/023 (devs-team / visual-team team pattern), docs/verification/test-design-standard.md (the standard this executes)

## Problem

The kit reviews two of the three V-model artifacts adversarially and skips the third:

- The **spec** gets `/kit:spec-validate` (5 lenses, pre-implementation).
- The **code** gets `/kit:review-team` (3 lenses, post-implementation).
- The **test design** , the bridge between them , gets neither. `/kit:test-plan` writes a `## Test plan`
  coverage matrix into the spec, and `/kit:execute` runs it unreviewed.

The quality bar for a test design exists as reference (`docs/verification/test-design-standard.md`: coverage
rule, test ladder, falsifiability, one-source/three-roles, sign-off checklist) but has **no executor**. So
coverage gaps, weak/fake negative controls, non-runnable proofs, and flaky designs only surface AFTER
`/kit:execute` runs , as retry loops, surprise RED runs, or "we never covered that" post-hoc.

## Solution

A new command `/kit:test-plan-review-team` that critiques a spec's `## Test plan` via 5 parallel
adversarial lenses and tightens it through a bounded revise loop, slotted between `/kit:test-plan` and
`/kit:execute`. It mirrors `/kit:devs-team` (same team machinery, one altitude down) and is **report-only**
(never blocks `/kit:execute`).

### Command contract (`commands/test-plan-review-team.md`)

- **Resolve** the active spec (branch-aware, spec-first) and read its `## Test plan` + `## Acceptance
  Criteria` + named failure modes. No `## Test plan` -> tell the user to run `/kit:test-plan`, stop.
- **5 lenses, in parallel** (read-only Task subagents, inline prompts , no per-lens agent files, like
  devs-team). Each encodes a slice of `test-design-standard.md`:
  1. Coverage completeness (every AC <-> a test; category matrix; failure modes covered).
  2. Oracle & falsifiability (credible negative control per load-bearing case; real oracle, not "should work").
  3. Feasibility & reproducibility (concrete pasteable isolated proofs; honest TBD/no-check).
  4. Test-ladder & boundary depth (climbs to a real-state run for stateful/behavioral; edges enumerated).
  5. Determinism & maintainability (flakiness sources mitigated; env pinned; CI/sandbox-runnable).
- **Bounded revise loop**: if findings > 0 and round < 3, a DISTINCT reviser subagent (producer != reviewer)
  revises the `## Test plan`, then re-critique. `[[QL-VERDICT round=N clean=BOOL findings=K]]` per round;
  findings must strictly fall (non-falling -> stop). Stop early at 0.
- **Write + report**: append `## Test plan critique` to the spec (replace-not-stack), with rounds, findings
  by severity, the 5 scores, and a `SOLID / REVISE / RECONSIDER` verdict. Never blocks.

## Acceptance criteria

- [x] AC1: `commands/test-plan-review-team.md` exists, dispatches 5 lenses in parallel, writes
      `## Test plan critique` spec-first (replace-not-stack).
- [x] AC2: The bounded revise loop uses a distinct reviser (producer != reviewer), caps at 3 rounds, emits
      the `[[QL-VERDICT ...]]` marker, and enforces strictly-falling findings.
- [x] AC3: Report-only , the command never blocks `/kit:execute`; verdict vocabulary is SOLID/REVISE/RECONSIDER.
- [x] AC4: The 5 lenses map to `docs/verification/test-design-standard.md` (named in the command's lens text).
- [x] AC5: A meta-test pins the literal `## Test plan critique` heading + the `spec-first` write target
      (drift guard, SPEC-018/023 shape); `tests/test-meta.sh` stays green.
- [x] AC6: The V-model doc (SPEC-031) names the test-design-review node between test-plan and execute.

## Test plan

Date: 2026-06-09
Source: this spec's ## Acceptance criteria
Runner: `bash` >= 3.2 (macOS default) with the project test harness; CI image ships GNU coreutils. All
matchers use portable `grep -F` / `grep -cF` (fixed-string, no regex) so a green local run on BSD grep
matches CI on GNU grep. `grep -c` counts lines, not matches; where a case needs an occurrence count
(a needle that can repeat on one line), it counts with `grep -oF '<needle>' <file> | wc -l` and trims
whitespace, never `grep -c`.

**Proof class reality.** The artifact under test, `commands/test-plan-review-team.md`, is a pure-prose
LLM prompt. It has NO executable entrypoint, no injection seam, no stub-able dispatch. There is no way
to drive its loop / dispatch / report-only behavior deterministically in CI: the kit cannot run a live
Claude subagent in CI (precedent: `tests/test-review-team-plants.sh` header , "We cannot dispatch a
live Claude reviewer in CI, so we test prompt completeness instead"). So the two real classes are:

- **Lane A , prompt-completeness pins (CI-blocking, deterministic).** Each load-bearing invariant must
  be ENCODED in the command prose. The pin greps that the command text carries the rule; its negative
  control is real , delete that sentence from `commands/test-plan-review-team.md` and the pin flips RED.
  Each row names its revert target ("delete X -> RED").
- **Lane B , live loop dynamics (manual / nightly, non-blocking, human-attested).** The actual
  convergence / cap / strictly-falling behavior is exercised by a real `/kit:test-plan-review-team`
  invocation whose dynamics an operator attests. No scripted stub, no synthetic `out.md`; the real
  subagents run and the recorded run lands at `docs/verification/test-plan-review-team.md`.

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1a | command file exists + names the 5 numbered lenses | happy-path | AC1 | the file is present and the lens block lists lenses 1..5 | `test -f commands/test-plan-review-team.md` exits 0; `n=$(grep -cE '^[1-5]\. \*\*.*\(std §' commands/test-plan-review-team.md); test "$n" -eq 5` (anchors on the numbered bold lens line WITH its standard tag; the loop's own numbered rules carry no tag, so they cannot inflate the count). Revert: drop a lens from the command -> != 5 -> RED |
| 1b | command instructs spec-first write target (prompt pin) | happy-path | AC1 | the command prose tells the coordinator to resolve the active spec spec-first AND write the critique back to that same spec | `grep -cF 'spec-first' commands/test-plan-review-team.md` >= 1 AND `grep -cF 'write the critique back to' commands/test-plan-review-team.md` >= 1. Revert: delete the spec-first instruction -> RED. (Live ordering placement is attested in Case 8b, not pinned on synthetic output.) |
| 1c | verdict vocabulary is SOLID/REVISE/RECONSIDER | happy-path | AC3 | exactly those three verdict tokens appear in the command | `grep -cF 'RECONSIDER' commands/test-plan-review-team.md` >= 1, same for `SOLID` and `REVISE`. Revert: rename a verdict token -> RED |
| 2 | report-only: command encodes "never blocks `/kit:execute`" and invokes NO ship/proof gate | failure-injection | AC3 | the command prose states it never blocks `/kit:execute`, AND the command text contains no ship-gate / proof-gate invocation verb (it must not call the gate) | `grep -cF 'never block' commands/test-plan-review-team.md` >= 1 (report-only stated); AND the gate is absent: `test "$(grep -ciE 'proof-gate\.sh|ship-gate|\.ship-gate' commands/test-plan-review-team.md)" -eq 0`. Revert (positive): delete the "never blocks" line -> first pin RED. Negative control (real): add a `proof-gate.sh` invocation to the command -> second pin RED |
| 3 | strictly-falling rule is encoded (loop-monotonicity prompt pin) | failure-injection | AC2 | the command prose mandates findings strictly fall round-over-round and stop otherwise | `grep -cF 'strictly fall' commands/test-plan-review-team.md` >= 1 (or `grep -cF 'must strictly fall'`). Revert: delete the strictly-falling sentence from the command -> RED. Live firing on an equality plateau is attested in Case 8b |
| 4 | 3-round hard cap is encoded (cap prompt pin) | boundary | AC2 | the command prose caps the revise loop at 3 rounds | `grep -cF '3 rounds' commands/test-plan-review-team.md` >= 1 AND `grep -cF 'cap' commands/test-plan-review-team.md` >= 1. Revert: delete "Hard cap: 3 rounds" -> RED. Live cap-as-stopping-cause (still-falling-at-round-3) is attested in Case 8b |
| 5 | distinct reviser (producer != reviewer) is encoded | boundary | AC2 | the command prose requires the reviser to be a distinct subagent, not one of the 5 lenses | `grep -cF 'producer must not be reviewer' commands/test-plan-review-team.md` >= 1 (or `grep -cF 'distinct reviser'`). Revert: delete the producer!=reviewer constraint -> RED. Live distinct-id is attested in Case 8b + recorded in the Case 8a artifact |
| 6a | absent-input stop is encoded ("no `## Test plan` -> stop") | boundary | AC1 | the command prose tells the coordinator to stop, write no critique, and route to `/kit:test-plan` when the spec has no `## Test plan` | `grep -cF 'no `## Test plan`' commands/test-plan-review-team.md` >= 1 AND `grep -cF 'run `/kit:test-plan`' commands/test-plan-review-team.md` >= 1. Revert: delete the absent-input stop -> RED |
| 6b | partial-merge "missing:" path is encoded (lens-timeout control) | failure-injection | AC2 | the command prose says a lens timeout/failure does NOT block: it merges the lenses that returned and records `missing: <lens>` | `grep -cF 'missing:' commands/test-plan-review-team.md` >= 1 AND `grep -cF 'times out' commands/test-plan-review-team.md` >= 1. Revert: delete the partial-merge instruction -> RED. All-lenses-return control: the `missing:` slot reads "none" (see coverage notes; all-lenses-absent is OOS) |
| 7 | replace-not-stack rule is encoded | regression | AC1 | the command prose mandates replacing an existing `## Test plan critique` (from heading to next `## `), not appending a second | `grep -cF 'REPLACE it' commands/test-plan-review-team.md` >= 1 AND `grep -cF 'do not stack' commands/test-plan-review-team.md` >= 1. Revert: delete the replace-not-stack rule -> RED. Live single-block-survives is attested in Case 8b |
| 8a | dogfood contract check over the recorded run (CI-blocking, deterministic) | regression | AC1, AC2 | the committed recorded run satisfies a mechanized contract: contains `[[QL-VERDICT`, a `## Test plan critique` heading, <= 3 round markers, and a distinct-reviser note | `grep -cF '[[QL-VERDICT' docs/verification/test-plan-review-team.md` >= 1; `grep -cF '## Test plan critique' docs/verification/test-plan-review-team.md` >= 1; `test "$(grep -cF '[[QL-VERDICT round=' docs/verification/test-plan-review-team.md)" -le 3`; `grep -cF 'reviser' docs/verification/test-plan-review-team.md` >= 1 |
| 8b | dogfood live run , loop dynamics (manual / nightly, non-blocking, human-attested) | live | AC1, AC2, AC3 | a real `/kit:test-plan-review-team` invocation on a seeded-gap `## Test plan` exercises the loop, and an operator attests: (i) Coverage+Oracle lenses raise CRITICAL on the seeded gap (RED-as-expected negative control); (ii) the strictly-falling halt fires on an EQUALITY plateau , a round whose findings equal the prior round's (e.g. 3,2,2 -> halt at the 2==2 round, NOT a further revise); (iii) the cap stops a still-falling-but-nonzero run , a sequence like 4,3,2 that would emit a round 4 stops at round 3 because of the cap, so the cap (not natural convergence) is the stopping cause; (iv) report-only , the run never blocks `/kit:execute`; the recorded run lands at `docs/verification/test-plan-review-team.md` | run `/kit:test-plan-review-team` against the seeded-gap fixture; human attests (i)-(iv) and the regenerated `docs/verification/test-plan-review-team.md`. A named command an operator runs, not a pointer |
| 9 | lenses cite the standard, one cite per lens (5 occurrences) | happy-path | AC4 | each of the 5 lenses references `docs/verification/test-design-standard.md` | `test "$(grep -cE '\(std §' commands/test-plan-review-team.md)" -eq 5` (one `(std §...)` tag per lens; the lenses cite by shorthand, not full filename) AND `grep -qF 'test-design-standard.md' commands/test-plan-review-team.md` (the canonical full-filename reference exists). Revert: drop a lens's `(std §...)` tag -> != 5 -> RED |
| 10 | meta-suite green, no prior pin regressed | regression | AC5 | the new critique-heading + spec-first pins PASS and no previously-green pin in the suite flips to FAIL | `bash tests/test-meta.sh` exits 0 (property assertion: zero failures; no hard-coded total count) |
| 11 | V-model names the test-design-review node (anchored to the node row) | happy-path | AC6 | SPEC-031 references `test-plan-review` ON the V-model node/row, not an incidental prose mention | `grep -cF 'test-plan-review' docs/specs/SPEC-031-v-model-and-convergence.md` >= 1 AND the matched line is the V-model node row: `grep -F 'test-plan-review' docs/specs/SPEC-031-v-model-and-convergence.md \| grep -qF -- '->'` (`--` so the dash-leading pattern is not read as a flag) (or the table-row pipe) exits 0 |
| 12 | clean-input green control is encoded (SOLID, no revise round) | happy-path | AC1, AC3 | the command prose defines the clean path: findings=0 on round 1 -> SOLID verdict, no reviser dispatched | `grep -cF 'SOLID' commands/test-plan-review-team.md` >= 1 AND `grep -cF 'Stop early' commands/test-plan-review-team.md` >= 1 (early-exit-at-clean encoded). Revert: delete the stop-early-at-0 rule -> RED. Live SOLID-with-no-revise is the falsification side attested in Case 8b |

### Coverage notes
- **Behavioral loop dynamics are NOT deterministically testable in CI for a prose-LLM command.** Kit
  precedent: `tests/test-review-team-plants.sh` ("We cannot dispatch a live Claude reviewer in CI, so we
  test prompt completeness instead"). The command has no executable entrypoint and no stub seam, so there
  is no honest deterministic behavioral test of the loop. CI therefore asserts **prompt-completeness**
  (Lane A: cases 1a-7, 9-12 minus 8b): each pin greps that the rule is ENCODED in
  `commands/test-plan-review-team.md`, with a real revert target (delete the sentence -> RED). The genuine
  **loop dynamics** (strictly-falling halt on an equality plateau, cap-as-stopping-cause, distinct reviser,
  report-only) live in ONE human-attested Lane-B dogfood (Case 8b), recorded at
  `docs/verification/test-plan-review-team.md`; Case 8a is the deterministic contract check over that
  recorded artifact. There is no scripted-critique stub and no synthetic `out.md` anywhere , those cannot
  exist for this artifact.
- **Why an equality plateau, not a rising sequence, is the boundary.** The strictly-falling rule halts the
  moment a round's findings are NOT LESS than the prior round's. The tight boundary is EQUALITY (2 == 2),
  not a rise (5 -> 6); equality is the case a `<` guard must reject and a `<=` guard would wrongly pass.
  Case 8b attests the halt on a 3,2,2 plateau (stop at the 2==2 round).
- **Why the cap case must stay falling and nonzero at round 3.** If the seeded gap naturally converges to 0
  by round 3, the loop stops for convergence, not the cap, and the cap is never exercised. Case 8b uses a
  still-falling-but-nonzero sequence (4,3,2 with a would-be round 4) so the CAP is the stopping cause.
- **Count cross-check.** The 5 numbered lenses (Case 1a) should be the SAME 5 that each cite the standard
  (Case 9): one standard cite per lens, so the lens-set size and the cite-occurrence count both land at 5.
- **Lens-timeout control.** Case 6b pins the partial-merge `missing:` path. The all-lenses-return control is
  the same field reading "none". The all-lenses-absent edge (every lens times out) is **OUT OF SCOPE**: a
  pure-prose command cannot encode a deterministic test for a total-dispatch failure, and the operator would
  observe it directly in a Lane-B run. Owned by orchestrator-level dispatch handling (the Task layer), not the
  command contract; revisit if the kit gains a programmatic dispatch layer.
- **Categories.** happy-path, boundary, failure-injection, regression, live are all exercised.
  Security/abuse is skipped: this is a docs/command artifact with no untrusted input path or network/data
  surface to attack.
- This is a coverage TARGET, not an exhaustive list. Every AC maps to >= 1 case: AC1 (1a,1b,7,8a,10),
  AC2 (3,4,5,6b,8a,8b), AC3 (1c,2,8b,12), AC4 (9), AC5 (10), AC6 (11).

## Verification

Proof at `docs/verification/test-plan-review-team.md` (table-first per ADR-0026, dogfooding the new
convention): the meta-test green run + a dogfood critique run on a seeded-gap test plan showing the negative
control (Coverage/Oracle lenses bite) and convergence.

## Out of scope

- Making `/kit:test-plan` a roundtable. It stays the deterministic matrix-writer (personas belong in the
  adversarial review, per its own rationale, SPEC-016 DEC-004).
- A hard gate. Report-only by decision (matches devs-team/visual-team; the team-never-blocks philosophy).
- Per-lens agent files. The lenses are inline (devs-team shape); minimum infra.

## Test plan critique
Date: 2026-06-09
Spec: SPEC-052
Lenses run: coverage, oracle, feasibility, test-ladder, determinism (round 1+2 full; round 3 re-ran oracle, feasibility, test-ladder, the lenses holding the open critical, and carried coverage/determinism from round 2)
Rounds:
- `[[QL-VERDICT round=1 clean=false findings=13]]`
- `[[QL-VERDICT round=2 clean=false findings=11]]`
- `[[QL-VERDICT round=3 clean=false findings=5]]` (3-round hard cap reached; stopped with OPEN findings)

Findings strictly fell 13 -> 11 -> 5. The loop converged on shape but hit the cap with 5 mechanical findings open. The arc is the interesting part: round 1 found the plan was ~90% prose-grep with the load-bearing behaviors untested; the round-2 reviser OVER-corrected by inventing a "scripted-critique stub" harness that cannot exist for a pure-prose LLM command (a new CRITICAL, which is why round-2 findings barely fell); the round-3 reviser fixed that by adopting the kit's real pattern (prompt-completeness pins with real "delete-the-sentence -> RED" revert targets + one human-attested live dogfood). Round 3's remaining findings are RED-on-green matcher bugs the lenses caught by actually running the pins against the committed files.

### High findings (round 3, OPEN)
1. Pin 1a regex is wrong: `grep -cE '^  [1-5]\.'` (two-space indent) matches 0 lines; the 5 lenses are numbered at column 0. The pin is RED on the correct command. found by: oracle, feasibility , fix: `grep -cE '^[1-5]\. \*\*' commands/test-plan-review-team.md` (hits exactly the 5 bold lens names) , RESOLVED post-cap 2026-06-10 (pin 1a now anchors on the lens line WITH its `(std §` tag; verified == 5)
2. Pin 9 expects `>= 5` occurrences of `test-design-standard.md` but the truth is 3: the lenses cite the standard by `(std §N)` shorthand, not the full filename. RED on green. found by: oracle, feasibility , fix: count the per-lens shorthand `grep -cE '\(std §' == 5`, or assert the single canonical reference + the 5 `(std §...)` tags , RESOLVED post-cap 2026-06-10 (pin 9 now counts `(std §` == 5 + canonical filename present)
3. Pin 8a's contract greps `[[QL-VERDICT` in the recorded run `docs/verification/test-plan-review-team.md`, which carries 0 literal markers (it is the table-first ADR-0026 prose). The proof and the artifact it certifies disagree. found by: oracle, feasibility , fix: regenerate the recorded run so it contains a real `[[QL-VERDICT round=N ...]]` line, OR change 8a to match the table-first proof shape , RESOLVED post-cap 2026-06-10 (recorded run carries the R5 verbatim `[[QL-VERDICT` markers + reviser note; 8a contract green)

### Medium findings (round 3, OPEN)
1. Pin 11's `grep -qF '->'` treats `->` as an option flag and errors on BSD/GNU/ugrep; the runner claims portability. found by: feasibility , fix: `grep -qF -- '->'` , RESOLVED post-cap 2026-06-10 (pin 11 carries the `--` guard)

### Low findings (round 3, OPEN)
1. The all-lenses-absent OOS entry should name its owner (the orchestrator/dispatch layer, not the command contract) rather than leave a silent void. found by: test-ladder , fix: one line on the OOS entry: "owned by orchestrator-level dispatch handling; revisit if the kit gains a programmatic dispatch layer" , RESOLVED post-cap 2026-06-10 (owner line added to the OOS entry)

### Resolved across rounds
- R1 CRITICAL "report-only untested" + "loop invariants prose-only" -> fixed R2 (behavioral cases), refined R3 (honest prompt-completeness pins with real revert targets).
- R2 CRITICAL "fictional scripted-stub harness" -> fixed R3 (adopted the kit's prompt-completeness + human-attested pattern; cited `tests/test-review-team-plants.sh` precedent).
- R2 MEDIUMs "strictly-falling tested at a rise not the equality plateau" + "cap=3 not isolated as the stopping cause" -> fixed R3 (Case 8b attests the 3,2,2 equality halt and the 4,3,2 cap-isolation; coverage notes justify both boundaries).
- R1/R2 "prior 390 hard-coded count", "non-deterministic LLM oracle in CI", "vague unpinned grep" -> all fixed by R3 (property assertion, two-lane split, pinned commands with real paths).

### Scores (round 3)
- Coverage completeness: 8/10 (carried from round 2)
- Oracle & falsifiability: 7/10
- Feasibility & reproducibility: 6/10
- Test-ladder & boundary depth: 9/10
- Determinism & maintainability: 8/10 (carried from round 2)

### Verdict: SOLID (post-cap operator pass, 2026-06-10)

Original at-cap verdict: REVISE (below, kept verbatim). The 2026-06-10 operator pass ran every
Lane-A pin against the committed files and resolved all 4 matcher findings (1a, 9, 8a, 11);
the full pin set is green (see the recorded run's R5). The remaining LOW is out-of-scope
ownership, accepted. Original reasoning:

The plan's STRUCTURE is now correct and honest: it states the proof-class reality (a prose-LLM command cannot be behaviorally tested deterministically in CI), splits CI-blocking prompt-completeness pins (each with a real delete-the-sentence -> RED control) from one human-attested live dogfood, and specifies the loop boundaries correctly (equality plateau, cap isolation). The remaining 5 findings are mechanical: 3-4 pin matchers are RED on the correct committed files (1a regex, 9 count, 8a marker, 11 portability) plus one OOS-ownership LOW. The fix is a single dogfood pass , run each Lane-A grep against the committed file once and correct the matcher, and regenerate the recorded run to carry a literal `[[QL-VERDICT` marker. Not RECONSIDER (the feature is testable, the design is sound); not SOLID (a falsifiability plan whose own pins are RED on green has not been dogfooded against ground truth, which is exactly the discipline this lane enforces).

### Post-cap operator note
Running the round-3 pins against the committed files to green them surfaced a REAL bug in the command itself (not just the plan): lens 5 (Determinism & maintainability) had no `(std §...)` citation, so AC4 ("the 5 lenses map to test-design-standard.md") was only 4/5 satisfied. Fixed in `commands/test-plan-review-team.md` (added `(std §3/§5)` to lens 5); `grep -cE '\(std §'` is now 5. The other 3 matcher findings (1a regex, 8a marker, 11 portability) remained OPEN at that point , the critique recorded them rather than hand-greening them outside the bounded loop. The 2026-06-10 follow-up pass then resolved all of them against ground truth (see the verdict addendum + the recorded run's R5). This is the lane catching a real defect in its own feature: the most honest dogfood result there is.
