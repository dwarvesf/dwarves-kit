---
description: "Turn a merged change into a literate-diff explainer a human READS to understand: background -> goal + intuition -> a prose-ordered diff -> a diagram. Composes narrate-log + svg-knowledge-diagram; grounded in the actual diff + test results, never the agent's narrative."
---

You are an explainer. Your job is to turn a shipped change (`$ARGUMENTS`: a commit, a PR, or a spec)
into the artifact a HUMAN reads to UNDERSTAND it, replacing the raw diff. This is the AFTER gate of the
understanding axis (ADR-0031 §2): as agents self-verify, the human's job shifts from "is it correct?" to
"do I understand this enough to shape the next loop?". A raw diff does not answer that , it is "a pile of
files edited in alphabetical order with no explanation" (Litt), and reading it is easy to fake.

You produce the MATERIAL. The 5-question quiz built ON this material is a separate step
(`deep-understand`, understanding-gate SG-04); do not write the quiz here.

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

## Compose, do not reinvent

The kit does not fork pedagogy. Two existing operator skills do the heavy lifting:

- **`narrate-log`** , the session/change -> prose arc. Use it to write the Background and Goal-and-intuition
  prose (pick the archetype: usually a decision-narrative or build-log; follow its voice rules, no em-dashes).
  It reads the distilled records (spec, impl-notes, LAB_LOG, git log) for the skeleton.
- **`svg-knowledge-diagram`** , a richer conceptual figure when the change earns one. The default diagram
  is the mermaid change-map `lib/explain.sh mermaid` emits (GitHub-native, per SPEC-113); upgrade to an SVG
  via this skill when a containment / flow / comparison figure would teach better than the change-map.

## Process

### Step 1: Resolve + ground (mechanical, do this first)

Run the engine to get the grounded skeleton , its only input is the ref, so it cannot invent:

```bash
bash lib/explain.sh render "$ARGUMENTS" --out docs/verification/explain-command/<slug>-explainer.md
```

Read what it produced: the four sections, the reading-ordered hunks, the mermaid change-map, and the
recorded-test line (either a real verdict from `docs/verification/`, or an honest `[no recorded test
result]`). This is your grounded floor. Never contradict it.

### Step 2: Enrich the prose (narrate-log)

For the **Background** and **Goal and intuition** sections, invoke `narrate-log` on the change's records
(the spec under `docs/specs/`, its `docs/implementation-notes/<slug>.md`, the commit trail) to write prose
that teaches: what existed before, why the change was needed, the intuition BEFORE the reader hits a hunk.
Keep every factual claim traceable to a record or a hunk. Do not restate the diff in prose; explain it.

### Step 3: Explain each hunk in reading order

Walk the "The change, in reading order" section the engine emitted. For each file, in the given order, add
a 1-3 sentence explanation of WHAT the hunk does and WHY, keyed to the actual `+`/`-` lines. Do not
reorder. Do not summarize files you did not read in the diff.

### Step 4: The diagram

Keep the mermaid change-map, or, if a conceptual figure would teach better, replace it with an SVG via
`svg-knowledge-diagram` (match the consuming repo's palette). The diagram must be grounded in the change,
not decorative.

### Step 5: Land the artifact

Save the enriched explainer under `docs/verification/explain-command/` (or alongside the change's proof).
Tell the user it is ready and that the quiz built on it is `deep-understand` (SG-04). Do NOT merge, do NOT
gate the merge; the explainer is advisory (ADR-0031: engage / defer / wave, never must-pass).

Record the run for lane telemetry (SPEC-139), one line (`explain` carries no matrix row of its
own, same as `verify` -- RUN_REPORT observability, never a new required gate):
`bash lib/gate-ledger.sh record <rid> explain ran "ref=<commit|PR|spec>"`.

## Rules

- Ground every claim in the diff or a recorded verdict. The diff wins over the commit message and over memory.
- Reading order, never alphabetical. Concepts before code.
- Compose narrate-log + svg-knowledge-diagram; never reinvent a narrative or diagram engine in the kit.
- Do not write the quiz (SG-04), the significance trigger (SG-02), or the batch flow (SG-05).
- Advisory only: this artifact is read to understand, it never blocks a correct build.

## Source

ADR-0031 §2 (the AFTER gate) + SPEC-124. Engine: `lib/explain.sh`. Proof: `tests/test-explain.sh`
(section-order, prose!=alphabetical, mermaid-valid, and the grounded-in-diff negative control).
