# Implementation notes , /kit:explain (SPEC-122)

The DELTA from SPEC-122 / ADR-0031 §2. Decisions the spec did not pin down, deviations, and the
constraints that shaped the build. Not a mirror of the spec.

## 2026-07-03 12:00 Lane = normal (not full), by the classifier

Context: the conductor's brief guessed "likely full , new command surface + composes skills".
Decision: lane = **normal**. Why: `lib/lane-classify.sh classify` returns `normal` for every phrasing
of this task (command + lib + tests). `explain.sh` is a NEW feature lib, not one of the enforcement/
telemetry libs (lane-telemetry / mega-merge / proof-ledger / gate-ledger) that escalate to full.
Alternatives: force `full` "to be safe" , rejected as cargo-cult ceremony the classifier does not ask
for (kit-faithful: follow the tool). Impact: fewer required gates (spec/build/ship measure-twice); I
still ran `/kit:review-team`-level scrutiny because the change touches `lib/` (AGENTS.md SPEC-069), and
still wrote the `## Design` block because the work is design-bearing per ADR-0031 §1 (new component).

## 2026-07-03 12:10 Split plane: grounded lib + composing command (the architectural guarantee)

Context: the hard constraint is "ground in the diff, never the agent's narrative". Decision: put ALL
grounding + ordering in `lib/explain.sh`, whose ONLY input is a git ref , there is no argument through
which a narrative could enter. The command (`commands/explain.md`) composes narrate-log + svg-knowledge-
diagram ON TOP of the grounded skeleton. Why: making the constraint STRUCTURAL (no narrative channel)
beats making it a prose promise the LLM might break. Impact: the load-bearing NC (AC4) tests the lib
directly and is deterministic.

## 2026-07-03 12:20 The negative-control fixture carries the false narrative in the commit BODY, not subject

Context: AC4 needs "the agent's stated intent differs from the diff". Naive reading: put the false
intent in the commit message. Constraint the spec missed: the engine seeds the "Goal" line from
`git log -1 --format=%s` (the SUBJECT), so a "multiply" subject would legitimately surface in the
artifact and the `! grep multiply` assertion would misfire. Decision: the NC fixture keeps the subject
NEUTRAL ("update calc helper") and carries the false "multiply" narrative in (a) the commit BODY (which
the engine never reads) and (b) an uncommitted `AGENT_NARRATIVE.txt` (outside the ref's diff entirely).
The diff truthfully adds `subtract`. Assertion: the explainer names `subtract` and never says `multiply`.
Why this is the RIGHT test, not a dodge: it proves the real guarantee , the tool has no narrative
channel, so only the committed diff + subject-as-label reach the output. A commit-message claim that
contradicts the code is exactly untrusted narrative; the diff wins. (The subject IS metadata the engine
surfaces as an unverified label, so an honest fixture does not weaponize the one field the engine reads.)

## 2026-07-03 12:30 Frozen surfaces: no BLOCKED flag needed

Context: the brief flagged a possible BLOCKED if test-meta demanded the new command be registered in a
frozen surface (`plugin.json` / `marketplace.json`). Finding: neither file enumerates commands , the kit
auto-discovers `commands/*.md` , so a new command needs NO edit there. The companions that test-meta
DOES hard-enforce are non-frozen: `docs/architecture.md` inventory-table row (row-count == live file
count) and the README command summary count + table rows (28 == live). MANUAL.md is the advisory
doc-impact companion. No frozen file was touched; no BLOCKED flag.

## 2026-07-03 12:35 Mermaid default in the lib; svg-knowledge-diagram escalation in the command

Context: ADR-0031 says "a diagram (via svg-knowledge-diagram / mermaid)". Decision: the lib emits a valid
mermaid change-map (grounded in the diff's file/rank structure, GitHub-native per SPEC-113) as the
default, testable diagram; the command layer escalates to an SVG via svg-knowledge-diagram when a
conceptual figure teaches better. Why: keeps a grounded + assertable diagram in the testable plane while
honoring "compose, don't reinvent" (the pedagogy skill is invoked, not forked) at the command layer.
