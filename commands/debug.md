---
description: "Systematic debug loop: root cause before any fix. Four phases, an evidence ledger, the 3-fix architecture wall."
---

You are debugging a defect, regression, or test failure. You are not here to guess. Random fixes waste time and create new bugs.

## The Iron Law

```
NO FIX WITHOUT A RECORDED ROOT CAUSE.
```

You may not edit code to "fix" the bug until the ledger's `## Root cause` is filled with the actual cause, traced to its source. A symptom patch is a failure, not a fix.

## Before you start: open the ledger

Pick a short `<slug>` for this bug, sanitized to `[a-z0-9-]+` (lowercase, digits, hyphens only; no spaces, no `/`, no `.`). Reject anything else; never let a slug contain a path separator.

Write `.claude/debug/<slug>.md` from this template, and **append to it before each action, not after**, so a context reset shows what you were about to do:

```
## Symptoms
(immutable: exactly what was reported, the error text, the failing test name)

## Root cause

## Evidence
(append: timestamp / what you checked / what you found / what it implies)

## Eliminated
(append: each hypothesis you falsified + the evidence that killed it)

## Fix attempts
(append: a count; the 3-fix wall reads this)

## Resolution
(the fix + the verification result)
```

Leave `## Root cause` blank until you have actually found it. While it is blank, the anti-rationalization hook will block any guess-fix "done" claim and send you back here. That is intended.

## Phase 1: Root cause investigation

Do all of this before forming any fix.

1. **Read the error completely.** Stack trace, line numbers, codes. The answer is often in the message.
2. **Reproduce reliably.** Exact steps. Every time? If you cannot reproduce, gather more data; do not guess.
3. **Check recent changes.** `git diff`, `git log`. If it worked before and is broken now (a regression), run `git bisect` to find the introducing commit: `git bisect start`, mark a known-good ref `git bisect good <ref>` and the broken `git bisect bad`, let it converge, then **always** `git bisect reset` when done. If there is no known-good ref, skip bisect and trace data flow instead.
4. **Gather evidence at component boundaries.** In a multi-layer system, log what enters and exits each boundary so you can see WHERE it breaks before deciding WHY. Tag every probe `[DEBUG H1]`, `[DEBUG H2]`, ... mapping each log line to the hypothesis it tests, and redirect output to `.claude/debug/<slug>.log` (not stdout, so the context window stays clean). Wrap injected instrumentation in region markers so it can be removed in one pass:
   ```
   # #region DEBUG
   ...instrumentation...
   # #endregion
   ```
5. **Trace the bad value backward.** Where does it originate? What passed it in? Keep going up until you reach the source. Fix at the source, not the symptom.

Record findings in `## Evidence` as you go. When you can name the cause and point to its origin, write it in `## Root cause`.

## Phase 2: Pattern analysis

1. **Find a working example.** Similar code in this repo that works.
2. **Compare.** List every difference between working and broken, however small. Do not assume "that can't matter."
3. **Understand dependencies.** What config, environment, or assumptions does the broken path rely on?

## Phase 3: Hypothesis and testing

1. **One falsifiable hypothesis.** State it: "I think X is the root cause because Y." If you cannot design a test that could disprove it, it is not a useful hypothesis.
2. **Test minimally.** The smallest change that confirms or kills it. **One variable at a time.**
3. **Verify before continuing.** Confirmed -> Phase 4. Killed -> record it in `## Eliminated` and form a new hypothesis. Do not stack fixes.

## Phase 4: Implementation

1. **Write the failing test first.** The simplest reproduction, automated. This is the concrete pass/fail signal; it feeds the existing verification pipeline (worker -> task-verifier -> fix-agent) the same way `/execute` tasks do. No test, no fix.
2. **One fix, at the root cause.** No "while I'm here" changes, no bundled refactoring.
3. **Verify.** The new test passes; no other test broke; the original symptom is gone.
4. **Clean up.** Remove all instrumentation in one pass over the region markers (`sed '/# #region DEBUG/,/# #endregion/d'` or equivalent). Confirm `git bisect reset` ran if you bisected.
5. **Do not declare "fixed" until the human confirms.** Increment `## Fix attempts`. Write the result in `## Resolution`. Then ask the human to confirm before you call it done or strip the ledger.

## The 3-fix architecture wall

If a fix does not work:
- Fewer than 3 attempts: return to Phase 1 with the new information. Do not attempt another fix on top.
- **3 or more attempts, or each fix reveals a new problem in a different place: STOP.** That pattern means the architecture is wrong, not the hypothesis. Do not attempt fix #4. Present the `## Eliminated` list to the human and question the design.

## Red flags (stop and return to Phase 1)

- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "It's probably X, let me fix that"
- "I don't fully understand it but this might work"
- Proposing a fix before the ledger's `## Root cause` is filled

## Scope

This loop is for defects, regressions, and test failures (the `bug` lane in WORKFLOW.md). A one-character obvious typo fix does not need it (tiny lane). After a confirmed fix, run `/kit:review` on the diff.

Source: obra/superpowers `systematic-debugging` (four phases, iron law, 3-fix wall); glittercowboy/get-shit-done `gsd-debugger` (the evidence ledger, falsifiability); doraemonkeys/claude-code-debug-mode (`[DEBUG Hn]` tagged logs to a debug file, region-marker cleanup, human-confirm before victory); SuperClaude `/sc:troubleshoot` (fix gated behind confirm). Classic lineage: David Agans, "Debugging: The 9 Indispensable Rules" (audit trail, change one thing, "if you didn't fix it, it ain't fixed"); Andreas Zeller, "Why Programs Fail" (delta debugging / minimal reproduction). See docs/specs/SPEC-013-debug-loop.md and ADR-0012.
