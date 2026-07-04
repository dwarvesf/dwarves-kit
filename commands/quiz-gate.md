---
description: "The ★-tap NUDGE before merging a significant+worthy gate PR: a 5-question quiz built from the ACTUAL diff+tests, routed through deep-understand's mastery gate. Three logged responses (engage/defer/wave); advisory, never must-pass. Gates the human's attention, not the merge."
---

You are the understanding-gate NUDGE (ADR-0031 §2/§3, the AFTER gate's speed regulator). At the merge
boundary of a `gate`/gated-final PR, when a change is BOTH significant AND understanding-worthy, you offer
the human a 5-question quiz built from the actual change BEFORE they click-to-merge. `$ARGUMENTS` is the
change under merge (a commit / PR / spec ref) and its run id (`<rid>`).

This gates the human's ATTENTION, never the merge. It is a NUDGE (ADR-0031 Refinement point 3): a waved
change still merges; you never hard-block a correct build. The only real failure is UNTRACKED debt, so all
three responses are recorded.

## The two hard constraints (do not violate)

1. **Grounded in the DIFF + recorded test results, NEVER the agent's narrative** (Litt's plausible-but-wrong
   caveat). The questions come from `lib/quiz-gate.sh questions <ref>`, whose only input is a git ref , there
   is no narrative channel, so a false story physically cannot leak in. Never hand-write quiz questions from
   memory, the commit message, or what you "meant" to do. If the commit message contradicts the diff, the
   diff wins.
2. **Route through `deep-understand`, do not build a second quiz.** The kit builds the QUESTIONS and dispatches;
   the `deep-understand` skill runs the AskUserQuestion mastery gate (shuffled answer slots, per-item gate on a
   demonstrated answer). The kit scores nothing.

## Process

### Step 1: Decide whether to tap (keyed on the SPEC-123 verdict)

Only a `tap` verdict (significant AND understanding-worthy) on a `gate`/gated-final PR is ever nudged , the
anti-fatigue guard. A significant-but-low-worthiness change (`wave`) or a `not-significant` change is NEVER
quizzed (it is already logged silently by SPEC-123's `significance-classify record`, wired into `/kit:ship`
Step 8 by SPEC-136, immediately before this tap).

```bash
bash lib/quiz-gate.sh tap <rid> --files "<changed files>" --impl-notes docs/implementation-notes/<slug>.md --pr-kind gate "<what changed>"
```

If it prints nothing, there is no tap , stop, the merge proceeds untouched. If it prints the nudge, present
the one line ("★ worth understanding: ...") and the three choices to the human. Do not decide for them.

### Step 2: On the human's choice, record it and (for engage) route

All three responses are logged to the debt ledger (`gate-ledger.sh debt-response`). Run exactly the choice
the human made:

```bash
bash lib/quiz-gate.sh respond <rid> engage --ref <ref>   # pull the quiz now
bash lib/quiz-gate.sh respond <rid> defer                # send to the weekend batch (SG-05)
bash lib/quiz-gate.sh respond <rid> wave                 # accept the debt knowingly
```

- **engage** , `respond ... engage --ref <ref>` emits the `deep-understand` dispatch payload (the 5
  diff-grounded questions + the SPEC-124 explainer material). Invoke the **`deep-understand`** skill with
  that payload: it runs the AskUserQuestion mastery gate until the human demonstrates understanding. You do
  NOT score or grade , `deep-understand` owns the pedagogy.
- **defer** , recorded; the change is queued for the weekend batch (SG-05). The merge proceeds.
- **wave** , recorded; the debt is accepted knowingly. The merge proceeds.

### Step 3: The merge proceeds either way

The quiz is a NUDGE. Whatever the human picked (including ignoring it), the merge is not blocked by this
gate. The correctness gates (ADR-0024 ship-gate, ADR-0025 proof-of-done) remain the only hard blocks.

## Rules

- Ground every question in the diff + recorded tests. The diff wins over the commit message and over memory.
- Tap ONLY on a `tap` verdict + a gate/gated-final PR (anti-fatigue). Never quiz a `wave` or `not-significant`
  change , that IS the fatigue failure mode.
- Route engage through `deep-understand`; never reimplement a quiz/scoring engine in the kit.
- All three responses are logged; waving is a first-class, RECORDED choice, not a failure.
- Advisory only: this never blocks a correct build (ADR-0031). It gates attention, not the merge.
- Do not write the explainer (SG-03, `/kit:explain`), the significance heuristic (SG-02), or the batch flow (SG-05).

## Source

ADR-0031 §2 (the AFTER gate's quiz half) + §3 (the nudge, three responses, debt budget) + SPEC-125. Engine:
`lib/quiz-gate.sh` (questions from the diff+tests, the tap decision keyed on `lib/significance-classify.sh`,
the three logged responses via `lib/gate-ledger.sh debt-response`). Composes the `deep-understand` skill.
Proof: `tests/test-quiz-gate.sh` (5-from-diff, three-responses-logged, deep-understand routing, the grounded
NC, the wiring NC, and never-must-pass).
