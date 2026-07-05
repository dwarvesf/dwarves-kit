# Mega-goal: understanding-gate

**Destination:** The dwarves-kit SDLC gains an UNDERSTANDING axis orthogonal to its verification gates , the human gates DIRECTION off a design record (diagram) before build, and gates UNDERSTANDING off an explainer + quiz when something significant ships, routed through the operator's existing learning skills. Two firing modes: inline-on-significant (default) and a weekend batch-learning flow. The operator stops accruing cognitive debt on fast autonomous runs.
**Quality bar:** Advisory, not a new hard block (ADR-0024/0025 stay the only correctness blocks). Proportional , obvious work collapses to one line, only significant work triggers the gate; a mis-tuned significance classifier (quiz fatigue vs. debt returning) is the load-bearing knob. The kit does NOT reinvent pedagogy , `/kit:explain` COMPOSES `deep-understand` / `narrate-log` / `svg-knowledge-diagram` / `learning-ledger`. The quiz is generated from the ACTUAL diff + test results, never the agent's narrative (Litt's plausible-but-wrong caveat).
**Work repo:** `dwarves-kit` (SG-01's template field + SG-05's learning flow carry dotfiles/ops-toolkit halves , edit chezmoi source, apply, stage+commit in ONE call).
**Stacking tool:** gh (stacked; 04 + 05 base their deps; 06 last)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final (the final PR is Han's click; once SG-04 ships, a FUTURE run's gate PR is quiz-gated , this mega-goal's own final is not, to avoid a build-time circularity)
**Terminus:** build + merge + the held final PR.
**Started:** 2026-07-03

**Close-out , OSS-readiness (operator 2026-07-03):** the repo front docs must be OSS-ready before this
mega-goal completes. The bulk is kit-face's job (SG-01 README/mermaid, SG-02 docs index, SG-08 v2.0.0
release + LICENSE/CONTRIBUTING/CHANGELOG already present). This mega-goal's obligation is narrower: SG-06
must leave the understanding-axis additions (design record, `/kit:explain`, the nudge gate, the debt
ledger, the weekend batch) coherently explained in the OSS-facing front docs , not half-documented kit
internals a new external reader trips over. If kit-face has NOT yet shipped its front-door work when this
runs, SG-06 flags the gap rather than duplicating it.

## Gate zero (decision before code)

**ADR-0031 (understanding gate) must be ACCEPTED first.** DONE , ACCEPTED (dwarves-kit PR #146,
2026-07-03; was Proposed in #126), so gate-zero is satisfied. This
mega-goal EXECUTES that ADR; it does not re-decide it. The pointer's turn-1 checks `docs/decisions/
0031-understanding-gate.md` Status; if not Accepted, it stops for Han's bless (ADR-0028 gate-zero
pattern). Sequenced AFTER kit-face ships (dogfood a production kit; do not stack ahead of need). Re-sequenced 2026-07-03 (operator): ledger-observatory now runs BEFORE this mega-goal's remainder (SG-02 / #148 is in flight; 03-06 resume after) , the observatory is the benchmark that measures THIS gate's own impact, and it needs no output of this mega-goal (its flagship `gate-yield`/`defect-correlation` queries run on the existing gate logs + `git log`; the debt ledger SG-02 builds conforms on arrival).

## Authority

ADR-0031 (dwarves-kit) + `ops-toolkit/research/2026-07-03-understanding-bottleneck-sdlc.md` (the full
analysis of Litt's "Understanding is the New Bottleneck"). Each sub-goal runs `/spec` + `/spec-validate`.

## Sub-goals

- [x] 01-design-record , `## Design` block in specs for design-bearing work (diagram/ADR/C4-lite, proportional) + spec-validate enforcement + design.md emit + WORKFLOW row + subgoal-template `Design:` field (dotfiles half) , `auto` , PR #149 merged 8c1f13e
- [x] 02-worthiness-classifier , `lib/significance-classify.sh` (sibling to lane-classify): TWO signals , significance (did a lot change) AND understanding-worthiness (will not-understanding cost a later loop); reads impl-notes as a worthiness feed; ★-taps only high×high; writes the debt-ledger marker , `auto` , PR #148 merged ce880ce (spec renumbered 122->123 at merge)
- [x] 03-explain-command , `/kit:explain`: literate-diff explainer (background -> intuition -> prose-ordered diff -> diagram), composing narrate-log + svg-knowledge-diagram, generated from the ACTUAL diff + test results , `auto` , PR #150 merged 2cb2238 (explain spec 124; also corrected significance refs 122->123)
- [x] 04-nudge-gate , 5-question quiz from actual diff+tests via `deep-understand`; a ★-tap NUDGE (engage/defer/wave, all logged to the debt ledger) before merging a significant+worthy gate PR, NEVER must-pass (Flow A, default, inline) , `auto` , PR #151 merged c3de8e7 (SPEC-125)
- [x] 05-weekend-batch , the ops-toolkit learning flow (Flow B, the debt paydown): collect the week's deferred+waved ledger items + their impl-notes/explainers, route through learning-day-process/learning-ledger/deep-understand, flush evergreen bits to til (dotfiles half) , `auto` , PR #152 merged 77815c2 (SPEC-126; dotfiles skill weekend-debt-paydown local branch)
- [x] 06-docs-wiring , WORKFLOW.md + AGENTS.md declare the understanding axis + the debt-budget model (honestly, only what dispatches); README notes `/kit:explain`; the no-orphan wiring check , `auto` , PR #153 merged 13c95c2 (SPEC-127; caught + fixed a real over-claim: significance record verb under-wired; wired 4 orphan test files into CI)

## Dependencies

- 04 depends on 02 (significance decides WHEN) + 03 (the explainer produces the quiz material).
- 05 depends on 02 (the significance records to collect) + 03 (the explainer material).
- 06 depends on ALL (docs-last: reflect the final wired state, per the kit-face lesson).
- 01, 02, 03 are independent (03's explainer builds without the classifier; the classifier decides when to invoke it).
- Execution order: {01, 02, 03} -> {04, 05} -> 06. Stack: 01/02/03 off `master`; 04 bases 03; 05 bases 03; 06 off `master` last.

## The conscious-debt-budget model (operator 2026-07-03; ADR-0031 Refinement , BINDING)

The gate does NOT quiz every significant change (fatigue; fights the operator's deliberate
hands-off default). It manages a **cognitive-debt budget**: the only failure is UNTRACKED debt.
Waving a change through is fine when RECORDED. Two signals + three responses + one ledger:

```
       worthiness LOW                         worthiness HIGH
  sig  ── ignore ──                           ── ignore (rare) ──
  LOW
  sig  wave-through, LOG silently             ★ TAP (one line + why): engage / defer / wave
  HIGH                                             all three -> the DEBT LEDGER
```

- **Two signals (SG-02):** significance (did a lot change) AND **understanding-worthiness** (will
  not-understanding cost a later loop?). Worthiness triggers: introduces a primitive future work
  builds on · irreversible/costly-to-reverse (data model, API contract, security boundary) ·
  first-of-kind/novel · high blast radius if misunderstood · the human must explain/defend/decide.
  Only high×high taps; low-worthiness significant work is waved+logged, never quizzed.
- **The tap is a NUDGE, three responses (SG-04):** engage now (explainer+quiz) / defer (weekend) /
  wave (accept knowingly). All logged to the **debt ledger**; NEVER must-pass-to-merge.
- **impl-notes are the agent-side FEED (integration):** `docs/implementation-notes/<slug>.md` is the
  spec->reality DELTA (decisions the spec did not pin down). An impl-note entry IS a high-worthiness
  candidate. SG-02 reads impl-notes as a worthiness signal; the human's engage/defer/wave lands in
  the debt ledger; SG-05 reads both (impl-notes = what was decided, ledger = what is unpaid). This
  gives impl-notes a consumer , REVERSING the 2026-07-02 audit's "write-only, drop it" finding
  (ops-toolkit ID-234): keep + wire impl-notes for spec work. Pipeline:
  `impl-note -> worthiness-flag -> ledger (engage/defer/wave) -> paid down (inline or weekend)`.

## Assumptions (2026-07-03; ADR-0031 + its Refinement resolved most forks; per-sub-goal /spec re-frames)

- **Firing mode default = INLINE ★-tap on significant+worthy** (Han); weekend-batch is the debt paydown (SG-05). Both configurable/off-able.
- **`/kit:explain` COMPOSES existing skills**, never reinvents: `narrate-log` (session->prose), `svg-knowledge-diagram` (the diagram), `deep-understand` (the quiz + mastery gate). The literate diff is a prose-ORDERED walk, not `git diff` order.
- **Hard constraint (all sub-goals producing explainer/quiz):** generate from the ACTUAL diff + recorded test results, NEVER the agent's own narrative (else it teaches the agent's misconceptions).
- **SG-05 is the SDD<>learning merge point + the debt paydown:** reuses `learning-day-process` / `learning-ledger` / `til`. An IMPROVEMENT to the existing weekend-learning cadence, not a parallel system.
- **Wiring gate (cross-cutting, kit-face lesson):** every new artifact (Design block, classifier, `/kit:explain`, the nudge gate, the batch flow, the debt ledger) must prove a live invocation path; WORKFLOW/AGENTS claim only what dispatches; TIER-4 runs the no-orphan check.
- **OSS-readiness is a close-out requirement (Han):** before the mega-goal completes, the repo front docs must be OSS-ready , see the close-out note below. (Most of this is kit-face's job; this mega-goal only ensures the understanding-axis additions do not leave the front docs half-explained.)

## Open forks (2 of 3 RESOLVED by the debt-budget refinement)

1. ~~Significance threshold~~ -> RESOLVED: it is TWO signals (significance × understanding-worthiness), tap only high×high; impl-notes feed the worthiness signal. /spec pins the exact worthiness regexes.
2. ~~Quiz-gate strictness~~ -> RESOLVED: a NUDGE (engage/defer/wave, all logged), never must-pass-to-merge.
3. **Batch cadence (SG-05, still open):** weekend-only vs. any on-demand batch; and where it runs (a skill Han invokes vs. a scheduled launchd job like the learning cadence). /spec defaults to a Han-invoked skill unless Han picks scheduled.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
