# 0036. Loops split by who changes

Date: 2026-09-10
Status: Proposed
Relates-to: ADR-0031 (the understanding gate, upheld in substance and in the gate's placement; this ADR separates the gate from the teacher it left fused), ADR-0034 (harness-loop taxonomy, whose `learn` subsystem this ADR renames to `reflect`), SPEC-249 (estate seams, the one-config-key rule this ADR extends with `understand.teach`), `_meta/megagoals/learning-boundary/ROADMAP.md` (the axis table below, verbatim, and the sub-goals that execute it), `docs/verification/wrap-candidates-scan.md` (the candidate-scan regression that opened the question), learning-kit `docs/ARCHITECTURE.md` (the overlay contract the teacher joins)

## Context

The operator asked one question on 2026-09-10. The dev kit has an auto-improvement half, and that half feels like learning, so where is the line against a kit that is about learning MORE rather than reflecting and then learning? Both halves distill a record into something better. Neither name tells an adopter which kit owns which loop.

The boundary had already blurred, and the estate showed it in four places.

The candidate-scan regression is the surface that opened the question. `docs/verification/wrap-candidates-scan.md` tallies two weeks of real `/kit:wrap` reports: every non-empty `Built:` line named the session's own deliverable, thirteen reports read `SKIPPED: nothing to build`, and no report named an existing tool to enhance. The standalone closeout that step replaced had printed a concrete `ENHANCE <home>` candidate most sessions. Tracing why the replacement lost that signal is what exposed the rest.

The estate carried three concept ledgers with three formats and three homes, so a concept captured in one was invisible to the other two. Two flush skills sat on two different seam sides, one in the operator's dotfiles behind `wrap.after` and one inside learning-kit, each believing it owned the flush. A kit test reached across repos and grepped the operator's dotfiles by absolute path, which made the engine's suite depend on a consumer's private tree; PR #554 removed that reach. Each failure has the same root: a loop was placed by what it felt like rather than by what it changes.

## Decision

Split every loop by one axis, who changes when the loop runs.

| Loop | Who changes | Input | Output | Kit |
|---|---|---|---|---|
| Reflect | the system | gate telemetry, run ledgers, retros | backlog rows, skill patches, config | dwarves-kit (`reflect`, ex `learn`) |
| Understand, the gate | a human, about work the system did | diff, tests, the significance verdict | the DEBT row: that understanding is owed, on what, by when | dwarves-kit (`significance-classify`, Step 7a, `reflect debt`) |
| Understand, the teacher | the same human, paying that debt | the DEBT row, the diff | an explainer, a quiz, a paid row | learning-kit `dev-learner`, through `understand.teach` |
| Study | a human, expanding | lectures, books, topics | notes, cards, glossary rows | learning-kit `study` |

### Reflect: dwarves-kit

The engine keeps every surface that changes the system from its own telemetry. `bin/learn propose` and `bin/learn drain` become `bin/reflect propose` and `bin/reflect drain`, because they read gate telemetry and stage backlog rows while nobody learns. `lib/learn/weekend-batch.sh` keeps the DEBT ledger and answers to `reflect debt`.

The `absorb` call is the hard case, so this ADR decides it out loud. `/kit:absorb` reads an external idea and changes the workflow, the skills, or the config. The system changes, the human does not sit an exam, so `absorb` is Reflect. It stays whole in the engine, body included, and no part of it moves to learning-kit.

### Understand, the gate: dwarves-kit

The engine keeps the whole gate. `lib/classify/significance-classify.sh record`, the DEBT ledger, `reflect debt list`, `reflect debt collect`, `reflect debt mark-paid`, and the merge-time nudge all stay. The gate produces process data about the engine's own runs, so an adopter who installs no overlay still gets a complete record of what understanding is owed.

`explain` and `quiz-gate` stay in the engine as commands. They are gate-side entry points, not lessons. Each gathers the material the gate already owns (the diff, the recorded test results, the DEBT row), then hands that material to the seam. Only the pedagogy bodies move: how to write an explainer, how to build a quiz from a diff, how to run a paydown session.

### Understand, the teacher, and Study: learning-kit

learning-kit ships `skills/dev-learner/` with the explain, quiz, and paydown bodies, plus its `lanes.d/dev-learner.plan`. Its install step fills the seam. The `study` lane is untouched by this ADR and keeps every surface where a human expands from outside material.

### Knowledge writers: context-kit

The skills that write knowledge into the tree (`knowledge-capture`, `memorize`) join context-kit, because both already write into a tree and both already name `knowledge.root`.

### One seam, `understand.teach`

The engine reaches the teacher through exactly one config key, `understand.teach`, of kind `skill`. It resolves with `kit_config_get_root`, the same rule `wrap.before` follows: the operator `kit.toml` or the kit-root `kit.toml` only, never a project `.kit.toml`, because the key names code a command runs and a project toml rides inside an untrusted pull request. It gains a row in `lib/config/module-registry.md`, a row in that file's `## Seams` table filled by learning-kit, and a row in SPEC-249's own `## Seams` section. No engine file names a consumer skill; a lint over `lib/`, `commands/`, and `tests/` fails on any consumer skill name or dotfiles path.

### The empty seam

With no teacher installed, the gate still records. `significance-classify record` writes the DEBT row, the nudge still fires, and `reflect debt list` still reports the balance. `explain` and `quiz-gate` print one line, `skipped: no teacher`, and hand the operator the gathered material: the ordered diff, the recorded test results, the DEBT row. A missing overlay costs the lesson, never the record, and never a worse lesson invented by the engine.

## Consequences

**An engine-only adopter keeps the gate whole.** Every ledger, the significance classifier, the nudge, the debt balance, `reflect` in all three verbs, and `explain` and `quiz-gate` as material-gathering commands all work with zero overlays present. What that adopter loses is pedagogy, and the `skipped: no teacher` line says so in one line at the moment it matters.

**learning-kit owes three things before the seam has a filler.** The `dev-learner` skill with the explain, quiz, and paydown bodies moved under `Moved-from:` trailers. The `lanes.d/dev-learner.plan` those bodies run inside. An install step that writes `understand.teach` into the operator `kit.toml`, so `bin/config seams` resolves the row instead of reporting it empty.

**The `learn` to `reflect` rename touches every call site.** `bin/learn` gains a forwarder so an existing consumer script keeps working through one release, per the kit's repoint-everything discipline. Documentation, the module registry, the five-stage tables, and the weekend-paydown skill's entry point all move to the new name in the same release. The Learn stage of ADR-0034's five-stage table keeps its name, because the stage is metadata over modules and this ADR renames a subsystem.

**One concept store survives.** The `learned-ledger.md` format wins, learning-kit's `bin/study-concepts` becomes its CLI, and the two flush skills collapse into one skill in learning-kit. Three ledgers going to one is what makes a concept captured in a dev session visible to a study session.

**The lint is the durable guard.** The reach-across that PR #554 removed cannot return quietly, because a consumer name or a dotfiles path in `lib/`, `commands/`, or `tests/` fails the suite.

## Alternatives considered

**Move every learning-shaped command to learning-kit.** Rejected. The gate produces process data about the engine's own runs, so its ledger belongs beside the gate ledger and the proof ledger. Moving `explain` and `quiz-gate` wholesale would strand an engine-only adopter with no record of what understanding is owed, which is the exact debt ADR-0031 exists to track.

**Keep everything in the engine.** Rejected. SPEC-249's rule says the only thing the engine may know about an overlay is a config key the overlay fills, and a pedagogy body inside `lib/` breaks that rule by definition. The dotfiles reach-across in PR #554 is what the rule looks like when it is violated.

## Relation to ADR-0031

ADR-0031 stands. Its substance is untouched: the design record before build, the significance and worthiness signals, the conscious-debt budget, the three-response nudge, the debt ledger, and implementation notes as the agent-side feed. Its placement call stands too: the understanding gate belongs inside dwarves-kit, and this ADR keeps it there.

What ADR-0031 never separated was the gate from the teacher. It named the gate and the explainer as one thing, and its own alternatives section already pointed the other way when it rejected a brand-new learning engine in the kit and said `/kit:explain` composes the operator's existing learning skills. That composition had no named seam, so the composition became a reach into the operator's tree. This ADR gives it the seam.
