# 0031. The understanding gate (design record + explainer/quiz)

Date: 2026-07-03
Status: Proposed
Relates-to: ADR-0018 (v-model phase frame , this adds a third axis to it), ADR-0024 (gate-ledger + ship-enforcement), ADR-0025 (proof-of-done ship gate , the VERIFICATION gate this complements), ADR-0028 (autonomous-loop hardening , the fast autonomous runs this counterbalances), SPEC-008 (solution-design depth), SPEC-011 (design lane), ops-toolkit `research/2026-07-03-understanding-bottleneck-sdlc.md` (the motivation) + the `understanding-gate` mega-goal + the learning skills (`deep-understand`, `narrate-log`, `svg-knowledge-diagram`, `interactive-concept-board`, `learning-ledger`)

## Context

The kit ships only VERIFICATION gates: proof-of-done (ADR-0025), review-team, the ship-gate
(ADR-0024). Every one answers "is it correct?". As ADR-0028's autonomous loop makes agents faster
and self-verifying (8 sub-goals in ~90 minutes on the kit-hardening run), a second question goes
unanswered: **does the human understand the change enough to shape the NEXT loop?**

Geoffrey Litt's "Understanding is the New Bottleneck" (2026-07-02) names the failure: if the human's
only job is verification, the human becomes redundant as agents self-verify , so the human's real job
is to **understand-to-PARTICIPATE** across many loops. Losing that understanding is **cognitive debt**
(Storey): "the humans involved may have simply lost the plot." It is cheap short-term and bites later.

This is observed in this repo's own use. The operator is, by his own description, "hands-off on reading
code, anal about test/feature coverage" , the exact high-verification/low-understanding profile the
article warns about. On the kit-hardening + kit-telemetry runs the operator fell out of the loop over
an ~8h gap and had to re-derive state ("recall where we are", "how many sub-goals"). The runs carried
PROOF forward but never UNDERSTANDING. Coverage kept the work safe; it did not keep the operator fluent.

A raw diff does not close this gap: it is "a pile of files edited in alphabetical order with no
explanation," and reading it is easy to fake ("you fool yourself into thinking you did the reading
when you really didn't retain").

## Decision

Add an **understanding axis** to the V-model, orthogonal to verification, realized as a gate at two
points. It is ADVISORY by default and configurable; it never blocks a correct build from being correct.

### 1. Design record (the BEFORE gate)

For any spec above the tiny lane that is **design-bearing**, the spec MUST carry a `## Design` block
BEFORE `/kit:execute` writes code, so the human gates DIRECTION off a diagram instead of a diff.

- **Design-bearing trigger:** above tiny AND any of , new component/module, non-obvious control flow,
  schema/data-model change, external integration, irreversible choice, 2+ viable approaches. Otherwise
  the block collapses to `obvious: <why>` and no diagram is required.
- **`## Design` contents, scaled (mermaid-first, C4-LITE):** approaches-considered + chosen-and-why
  (existing SPEC-008 shape); a **diagram** picked by fit , sequence (control-flow/protocol) / state
  (lifecycle) / ER (schema) / flowchart (algorithm) / C4 container-or-component (a new component's
  place); ADR link(s) for lasting/irreversible decisions; boundaries + failure modes when it touches
  data/external/migration.
- **Proportionality is load-bearing:** do NOT cargo-cult four C4 levels , use the ONE level that
  clarifies, only for genuinely new-component work. Prefer Mermaid (GitHub-native, diffable,
  hand-editable) over binary images (aligns with the README mermaid choice, kit-face SG-01).
- **Enforcement:** `/kit:spec-validate` refuses `VALIDATED` on a design-bearing spec whose `## Design`
  block is empty; `/kit:execute` warns (advisory, ship-gate-style) before building one.

### 2. Explainer + quiz (the AFTER gate)

When a **significant** change ships, the kit emits an understanding artifact the human consumes to
stay a participant , not a raw diff.

- A new `/kit:explain` produces a **literate-diff explainer**: background (existing context) -> goal +
  intuition (concepts before code) -> a prose-ORDERED diff (not alphabetical) -> a diagram -> a
  **5-question quiz**. It COMPOSES the existing learning skills (`narrate-log`, `svg-knowledge-diagram`)
  rather than reinventing them.
- **The quiz is a speed regulator** (Litt): before the human merges a `gate` / gated-final PR, they pass
  the 5-question quiz, routed through `deep-understand`'s existing AskUserQuestion mastery-gate engine.
- **Hard constraint:** the quiz is generated from the ACTUAL diff + recorded test results, NEVER from
  the agent's own narrative of them , else it teaches the agent's misconceptions (Litt's plausible-but-
  wrong caveat).

### 3. Firing modes

- **Inline / default:** a significance classifier (sibling to `lane-classify`) fires the gate when a
  change is significant (full lane, or design-bearing, or a tunable heuristic). Explainer + quiz at the
  gate, in-flow.
- **Weekend batch (option):** defer to a weekend batch-learning session that collects the week's
  significant changes and routes them through the ops-toolkit learning kit (`learning-day-process` /
  `learning-ledger` / `deep-understand`). This is where the SDD kit and the LEARNING kit merge.

## Consequences

- The human gates DIRECTION (a diagram) before build and UNDERSTANDING (an explainer + quiz) at merge,
  instead of only correctness. The `gate` PRs stop being "click to merge" and become "understand, then
  merge" , directly countering the AFK-lost-plot failure.
- The kit's LEARNING skills and SDD skills merge: the SDLC now EMITS understanding artifacts routed
  through `deep-understand` / `narrate-log` / `svg-knowledge-diagram` / `learning-ledger`; evergreen
  bits flush to `til` so understanding compounds instead of evaporating.
- Cost: the design record adds a pre-build beat (advisory, proportional , collapses to one line for
  obvious work); the explainer + quiz add a per-significant-change artifact (bounded by the significance
  classifier). Both are configurable/off-able. A poorly-scoped significance classifier over-fires
  (quiz fatigue) or under-fires (debt returns) , it is the load-bearing tuning knob.
- Risk if mis-built: an explainer that narrates the agent's intent rather than the diff's reality
  teaches a false model (mitigated by the actual-diff+tests constraint); a design record that becomes
  compliance theater rather than a real gate (mitigated by proportionality + the human actually gating
  on it).

## Alternatives considered

- **Keep verification-only.** Rejected: the article's core argument , as agents self-verify, a
  verification-only human is redundant AND accrues cognitive debt. The operator's own AFK-lost-plot
  sessions are the evidence.
- **Make the human read the raw diff.** Rejected: raw diffs are alphabetical file piles; reading is
  effortful and easy to fake; the operator is deliberately hands-off on code. An explainer is the
  higher-comprehension, lower-effort channel.
- **A brand-new learning engine in the kit.** Rejected: the operator already owns `deep-understand`
  (mastery-gate quizzes), `narrate-log`, `svg-knowledge-diagram`, `interactive-concept-board`,
  `learning-ledger`. `/kit:explain` COMPOSES them; the kit does not reinvent pedagogy.
- **Micro-worlds (interactive debuggers) for every change.** Deferred: high build cost, proportionality
  unsolved even by Litt. Reserved for genuinely complex subsystems via `interactive-concept-board`, not
  a per-diff default.
- **Notion shared-space by default.** Deferred: team-scale (a dfoundation move), a disclosed-conflict
  recommendation in the source; the solo-kit gate is the explainer + quiz first.

## Refinement (2026-07-03, operator): conscious debt budget + impl-notes as the feed

Two operator clarifications after the first draft. Deltas from the Decision above; fold into the
mega-goal.

**1. The goal is CONSCIOUS debt, not zero debt.** The operator's default mode is deliberately
hands-off-on-code + coverage-focused, and that is a valid strategy , like managing money, you do
not pay every balance the day it posts, you manage it. So the gate does NOT quiz every significant
change (that is fatigue, and it fights the operator's default). It manages a **cognitive-debt
budget**: the only real failure is UNTRACKED debt ("lost the plot"). Waving a change through is
fine when it is a RECORDED choice.

**2. Two signals, not one (understanding-worthiness on top of significance).** Significance ("did a
lot change") fires on big-but-boring refactors. The gate taps the human only when BOTH significance
is high AND **understanding-worthiness** is high , "will not understanding this cost me in a later
loop?". Worthiness triggers: introduces a primitive/concept future work builds on; irreversible or
costly-to-reverse (data model, API contract, security boundary); first-of-kind/novel pattern; high
blast radius if misunderstood; the human will have to explain/defend/decide on it. Low-worthiness
significant changes (mechanical, reversible, well-covered-by-tests, one-off) are waved and LOGGED,
never quizzed. The classifier does the noticing so the human does not carry that load.

**3. The tap is a NUDGE with three responses, never a hard gate.** On a ★ tap (high×high), one line
("worth understanding: <why>") and the human picks: **engage now** (pull the explainer + quiz),
**defer** (to the weekend batch), or **wave** (accept the debt knowingly). All three write to a
**debt ledger**. This resolves the earlier "advisory" question concretely: engage/defer/wave, all
recorded; the quiz is never must-pass-to-merge.

**4. impl-notes ARE the agent-side feed of the debt ledger.** The kit already keeps
`docs/implementation-notes/<spec-slug>.md` , the DELTA between spec and reality (decisions the spec
did not pin down, deviations, tradeoffs, constraints the spec missed). A prior process audit
(ops-toolkit, 2026-07-02) found impl-notes WRITE-ONLY (mandated, never read) and proposed dropping
them (ID-234). This ADR REVERSES that: an impl-note entry IS an unspecified decision the agent made
, exactly a high-understanding-worthiness candidate. So impl-notes become the raw feed: the
worthiness classifier reads them (an entry = a strong worthiness signal), each becomes a ★-tap
candidate, the human's engage/defer/wave lands in the debt ledger, and the weekend batch reads both
(impl-notes = what was decided, ledger = what is unpaid). The pipeline:

```
decision made (impl-note)  ->  worthiness-flagged  ->  human choice (debt ledger)  ->  paid down
                                                        engage / defer / wave        inline or weekend
```

Net: three currently-disconnected artifacts (impl-notes, the new debt ledger, the weekend batch)
become one tracked debt loop. impl-notes stop being ceremony because they finally have a consumer.
Reconcile ID-234 accordingly (keep + wire impl-notes for spec work; the "drop" applies only to
non-spec noise with no decision content).

## Out of scope

- Blocking a correct build on understanding (this axis is advisory/configurable; ADR-0024/0025
  verification gates remain the only hard blocks).
- The weekend-batch learning-session mechanics (ops-toolkit-side; specified in the mega-goal).
- Replacing `/kit:docs` (doc-drift-vs-code) , the explainer is a DIFFERENT artifact (human
  understanding, not doc currency).
