---
description: "Turn a merged change into a literate-diff explainer a human READS to understand: background -> goal + intuition -> a prose-ordered diff -> a diagram. Grounds the material mechanically, then hands it to the operator's configured teacher seam; grounded in the actual diff + test results, never the agent's narrative."
---

You are an explainer. Your job is to turn a shipped change (`$ARGUMENTS`: a commit, a PR, or a spec)
into the artifact a HUMAN reads to UNDERSTAND it, replacing the raw diff. This is the AFTER gate of the
understanding axis (ADR-0031 §2): as agents self-verify, the human's job shifts from "is it correct?" to
"do I understand this enough to shape the next loop?". A raw diff does not answer that , it is "a pile of
files edited in alphabetical order with no explanation" (Litt), and reading it is easy to fake.

You produce the MATERIAL. The 5-question quiz built ON this material is a separate step, run by
`/kit:quiz-gate` through its own seam; do not write the quiz here.

## The hard constraint (Litt's caveat , the whole point)

The explainer is grounded in the **ACTUAL diff + recorded test results**, NEVER in your own narrative of
what the change did. An explainer that narrates the agent's intent teaches the agent's misconceptions
(plausible-but-wrong). Concretely:

- **Never** describe a change from memory, from the commit message alone, or from what you "meant" to do.
  Every claim traces to a hunk in `git diff` or a recorded verdict under `docs/verification/`.
- The grounding + ordering is done mechanically by `lib/explain.sh` (its ONLY input is a git ref, so a
  narrative physically cannot leak in). You enrich the prose AROUND that skeleton; you do not override it.
- If the diff contradicts the commit message or your recollection, the DIFF wins. Say what the code does.

## Prose ordering is the point

If your output is `git diff` with headings, you FAILED. A raw diff is alphabetical by filename; an
explainer is in READING order , concepts before code:

```
background (existing context)  ->  goal + intuition (concepts)  ->  the change in reading order  ->  diagram
```

`lib/explain.sh order` ranks the changed files into reading order: background (docs/specs/ADRs) -> the new
concept (added files) -> integration (modified files) -> verification (tests), last. Keep that order.

## Compose through the seam, never by name

The kit does not fork pedagogy, and it does not hardcode which skill supplies it either
(ADR-0036): the engine gathers the grounded material (Step 1) and hands it to whatever
`understand.teach` names, through the Skill tool. It never names a specific skill itself. An
operator with no teacher installed still gets the grounded skeleton, `skipped: no teacher`, and
the material's path, never a broken reference to a skill that was never there.

## Process

Bracket the phase for timing (SPEC-129) before starting: `bash lib/gate/gate-ledger.sh outcome <rid> explain start`.

### Step 1: Resolve + ground (mechanical, do this first)

Run the engine to get the grounded skeleton , its only input is the ref, so it cannot invent:

```bash
bash lib/explain.sh render "$ARGUMENTS" --out docs/verification/explain-command/<slug>-explainer.md
```

Read what it produced: the four sections, the reading-ordered hunks, the mermaid change-map, and the
recorded-test line (either a real verdict from `docs/verification/`, or an honest `[no recorded test
result]`). This is your grounded floor. Never contradict it.

### Step 2: Gather the material and invoke the seam

The grounded skeleton from Step 1 (its path, plus the records it cites: the spec under `docs/specs/`,
`docs/implementation-notes/<slug>.md`, the commit trail) IS the material. Run `bash lib/gate/quiz-gate.sh
teacher` (the one resolver every seam-adjacent site cites; never read `understand.teach` any other way).

- **Empty:** print `skipped: no teacher` plus the skeleton's path, and hand that file to the user
  directly as the deliverable. Skip to Step 5; there is no enrichment step without a teacher.
- **Named:** invoke that skill through the Skill tool, handing it the skeleton's path and the ref. The
  skill owns the prose enrichment (Background, Goal and intuition, per-hunk explanation) and any richer
  diagram; this command names no skill itself and does not reimplement that pedagogy.

### Step 3: Land the artifact

Save whatever came back (the enriched explainer, or the grounded skeleton when there was no teacher)
under `docs/verification/explain-command/` (or alongside the change's proof). Tell the user it is ready
and that the quiz built on it runs through `/kit:quiz-gate`'s own seam. Do NOT merge, do NOT gate the
merge; the explainer is advisory (ADR-0031: engage / defer / wave, never must-pass).

Record the run for lane telemetry (SPEC-139), one line (`explain` carries no matrix row of its
own, same as `verify` -- RUN_REPORT observability, never a new required gate):
`bash lib/gate/gate-ledger.sh record <rid> explain ran "ref=<commit|PR|spec>"`.

Close the timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> explain end` (no verdict at this phase; the verb's own `false` default stands).

## Rules

- Ground every claim in the diff or a recorded verdict. The diff wins over the commit message and over memory.
- Reading order, never alphabetical. Concepts before code.
- Reach the teacher through `understand.teach` only; never name a specific skill in this file or hardcode a fallback narrative/diagram engine in the kit.
- Do not write the quiz, the significance trigger, or the batch flow; those are `/kit:quiz-gate`'s and the weekend batch's own seams.
- Advisory only: this artifact is read to understand, it never blocks a correct build.

## Source

ADR-0031 §2 (the AFTER gate) + SPEC-124. Engine: `lib/explain.sh`. Proof: `tests/test-explain.sh`
(section-order, prose!=alphabetical, mermaid-valid, and the grounded-in-diff negative control).
