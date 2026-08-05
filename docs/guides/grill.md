# The grill (user guide)

Before work runs, the kit may interview you. The grill closes the gap between
what you SAID and what the work actually IS, and it is deliberately not a form:
one question at a time, each carrying a recommended answer so you correct
instead of composing from scratch.

```
 your ask
    │
 unknown-density precheck: is this familiar ground?
    │  (recent commits on the target? domain known to the
    │   repo? you didn't say "I'm new to this"?)
    ├─ familiar -> AUTO-SKIP, logged, no interview
    ▼
 the interview, ordered by blast radius:
   1. CONTRADICTIONS with the repo's own records  ← asked first,
      (a spec, an ADR, a standing policy)           costliest to get wrong
   2. answers that would CHANGE THE ARCHITECTURE
   3. assumptions stated as defaults ("unless you
      say otherwise, I assume X")
   4. taste calls -> offered as quick mocks to
      react to, never asked as questions
    │
 each answer is WRITTEN WHERE IT LIVES the moment it
 resolves (glossary, a sparse ADR, the goal's context),
 then the interview ends: five sharp questions beat twenty
```

## What you do

- **Correct the recommendation, don't compose.** Every question arrives with a
  suggested answer and one line of reasoning. "Yes" is a fine answer; so is
  "no, because X", and X is the valuable part.
- **Expect the contradiction question first.** If your ask conflicts with a
  policy you wrote three weeks ago, that surfaces before anything else. That is
  the grill's highest-value catch, take it seriously before overriding.
- **Wave it off consciously.** You can skip the interview; the skip is logged
  as your call. Waving off on genuinely new territory trades five questions now
  for rework later.
- **Don't repeat yourself.** Answers land in durable records, not chat. A
  question you answered last month should not return; if it does, that is a
  bug worth reporting.

## Common questions

- **"Why did it NOT interview me?"** Familiar ground auto-skips (recent
  commits, known domain, nothing declared new). The skip is on the ledger with
  its reason.
- **"Why one question at a time?"** Batch questionnaires get skimmed; a single
  question with a recommendation gets an actual decision. The dependency also
  matters: your answer often changes what is worth asking next.
- **"It caught a contradiction and I still want my way."** Say so once; the
  override is recorded and the work proceeds. The grill informs, it does not
  veto.
