# Mega-goal: learning-boundary

**Destination:** The three kits split every loop by ONE axis, who changes when the loop runs, and the engine knows no consumer by name. dwarves-kit keeps the process plane: gates, ledgers, the landing step, its own reflection loop (the system improves itself from its telemetry), and the understanding GATE (that a human owes understanding on a shipped change, which change, and when it is due) with one seam for how a human pays it. learning-kit owns every surface where a human learns: the `study` lane (outside material, expansion) and the `understand` teacher that fills the engine's teach seam (the explainer, the quiz, the paydown pedagogy). context-kit owns writing knowledge into the tree. One concept ledger, one store format, one flush skill.
**Quality bar:** No consumer named in the engine (SPEC-249's rule, now enforced by a lint over `lib/`, `commands/`, `tests/`). No second engine: every move is a `git mv` plus a path fix plus a seam key, never a rewrite. Each move ships with its tests and its proof-of-done file, and the engine's suite stays green with zero skips at every sub-goal boundary. An adopter of dwarves-kit alone keeps every gate and every ledger; what they lose without learning-kit is the teacher, and the gate says so in one `skipped: no teacher` line instead of teaching badly.
**Work repo:** dwarves-kit for 00, 01, 05; learning-kit for 02, 03; context-kit for 04; dotfiles carries the retirements (chezmoi remove entries) in the same PR as each move.
**Stacking tool:** gh, one PR per sub-goal, sequential (cross-repo, no stacking).
**Merge mode:** bottom-up, each sub-goal merged before the next starts.
**Merge autonomy:** gated-final on 00 (the ADR is Han's click); `auto` from 01 on.
**Terminus:** 05 merged and `bin/config seams` shows `understand.teach` filled by learning-kit's `understand` teacher on the operator machine.
**Started:** 2026-09-10

## The axis: who changes

The operator's question that opened this (2026-09-10): the dev kit has an auto-improvement half, and that feels like learning too, so where is the line against a learning kit that is about learning MORE, not reflecting and then learning? The line is who changes.

| Loop | Who changes | Input | Output | Kit |
|---|---|---|---|---|
| Reflect | the system | gate telemetry, run ledgers, retros | backlog rows, skill patches, config | dwarves-kit (`reflect`, ex `learn`) |
| Understand, the gate | a human, about work the system did | diff, tests, the significance verdict | the DEBT row: that understanding is owed, on what, by when | dwarves-kit (`significance-classify`, Step 7a, `reflect debt`) |
| Understand, the teacher | the same human, paying that debt | the DEBT row, the diff | an explainer, a quiz, a paid row | learning-kit `understand`, through `understand.teach` |
| Study | a human, expanding | lectures, books, topics | notes, cards, glossary rows | learning-kit `study` |

Two consequences the earlier draft of this roadmap got wrong. `absorb` (external ideas into the workflow) changes the system, so it is Reflect and stays in the engine. And `explain` and `quiz-gate` do not move as commands: the engine keeps them as gate-side entry points that gather the data (diff, tests, DEBT rows) and hand it to the seam; only the pedagogy bodies move to learning-kit. ADR-0031 was right about the gate's placement. What it never separated was the gate from the teacher.

## Names (binding for every sub-goal)

One word per loop, everywhere that loop appears. A sub-goal that introduces a second word for the same loop has failed its own quality bar.

| Loop | Stage (ADR-0034 table) | Engine subsystem | Seam key | learning-kit lane and skill dir | Command names kept |
|---|---|---|---|---|---|
| Reflect | Reflect (was Learn) | `bin/reflect`, `lib/reflect/` (was `learn`; forwarder kept one release) | none (engine-internal) | none | `absorb`, `retro` |
| Understand | none (a gate, not a stage) | `significance-classify`, `reflect debt` | `understand.teach` | `lanes.d/understand.plan`, `skills/understand/{explain,quiz,paydown}` | `explain`, `quiz-gate` (thin, gate-side) |
| Study | none | none | `wrap.after` (the operator's flush) | `lanes.d/study.plan`, the existing study skills; `concept-flush` is the one flush | none |

Retired words, never reintroduced: `dev-learner`, `learn` as a subsystem name, `session-closeout`, `session-distill`, `learning-ledger` as a skill name (the store keeps `learned-ledger.md` as its file name; the skill is `concept-flush`).

## Gate zero (decision before code)

**ADR-0031 placed the understanding gate INSIDE dwarves-kit**, on purpose, in 2026-07 (accepted, PR #146). Its substance stands and so does the gate's placement. What this mega-goal separates is the TEACHER from the gate: the pedagogy bodies of `explain`, `quiz-gate`, and the weekend paydown are learning-kit's, reached through one seam. Sub-goal 00 writes ADR-0036 with the axis table above as its core and stops for Han's acceptance. Nothing after it starts until that ADR reads Accepted.

## Decisions already made (2026-09-10, operator said "proceed all")

1. **The surviving concept store is `learned-ledger.md`'s format**, today at `ops-toolkit/_meta/learned-ledger.md`. It has the routing (til, research, GLOSSARY) and the history. learning-kit's `bin/study-concepts` becomes its CLI: same verbs (`add`, `check`, `flush`), reads and writes that format, store path from `STUDY_CONCEPT_STORES`. The dotfiles `learning-ledger` skill and learning-kit's `concept-flush` collapse into ONE skill in learning-kit; dotfiles keeps a one-line chezmoi remove.
2. **The engine keeps the whole understanding GATE**: `significance-classify.sh record`, the DEBT ledger, `reflect debt list/collect/mark-paid`, the nudge at merge, and the `explain` / `quiz-gate` commands as data-gathering entry points. What moves is the teaching: how to explain, how to quiz, how to run a paydown session.
3. **Engine `learn propose/drain` is renamed `reflect`.** It reads gate telemetry and stages backlog rows; the system changes, nobody learns. `learn debt` moves under `reflect debt` for the same reason: the DEBT ledger is the gate's record.
4. **One seam key, `understand.teach`**, names the teacher. `wrap.before` and `wrap.after` stay as the generic seams they are. Empty seam: the gate still records, the commands print `skipped: no teacher` and hand the operator the raw material (the diff, the DEBT row) instead of a worse lesson.

## Authority

SPEC-249 (estate seams, the one-config-key rule). ADR-0031 (the gate, upheld; the teacher separated by ADR-0036). learning-kit `docs/ARCHITECTURE.md` (the overlay contract). The candidate-scan finding that opened this: dwarves-kit `docs/verification/wrap-candidates-scan.md`.

## Sub-goals

- [x] SG-00 adr-placement , ADR-0036: loops split by who changes; the engine keeps reflect and the understanding gate, learning-kit owns the teacher and study, context-kit owns the tree; one seam `understand.teach`; ADR-0031 upheld, its gate/teacher conflation resolved , gate , PR #556 (Accepted by the operator on the PR, 2026-09-10)
- [x] SG-01 engine-seam-and-lint , `understand.teach` key + registry row + seams-table row; `explain`, `quiz-gate`, Step 7a and 7c gather data and invoke the seam, naming no skill; `lib`+`commands`+`tests` lint that fails on any consumer skill name or dotfiles path; `learn` → `reflect` rename with a forwarder, and the Learn stage → Reflect in every five-stage table , auto , depends SG-00 , PR #560 , PR #560 merged bfd1334
- [ ] SG-02 understand-teacher , learning-kit gains `skills/understand/{explain,quiz,paydown}` (the pedagogy bodies from dwarves-kit `commands/explain.md`, `commands/quiz-gate.md`, dotfiles `weekend-debt-paydown`; `Moved-from:` trailers), `lanes.d/understand.plan`, their tests (incl. the routing assertions #554 retired), the install step that fills `understand.teach` , auto , depends SG-01
- [ ] SG-03 one-ledger , `bin/study-concepts` adopts the learned-ledger format; `concept-flush` + dotfiles `learning-ledger` → one `concept-flush`; dotfiles `learning-router`, `learning-day-process`, `concept-explain`, `deep-understand` and claude-skills `learn-skill` (dotfiles holds only a chezmoi symlink to `~/workspace/claude-skills/skills/learn-skill`) → learning-kit `presets/operator/skills/`; chezmoi remove entries , auto , depends SG-02
- [ ] SG-04 context-kit-writers , claude-skills `knowledge-capture` (dotfiles holds only a chezmoi symlink to `~/workspace/claude-skills/skills/knowledge-capture`) + dotfiles `memorize` → context-kit `skills/`; both already write into a tree and both name `knowledge.root`; chezmoi remove entries , auto , depends SG-01 , PR context-kit#7, PR claude-skills#6, PR dotfiles#436
- [ ] SG-05 docs-and-terminus , WORKFLOW.md, AGENTS.md, README of all three kits carry the axis table; `config seams` on the operator machine shows every seam filled by the kit the table names; `lib/config/module-registry.md` `## Seams` gains `understand.teach` (the table SPEC-249 documents and does not hold) , auto , depends SG-02 SG-03 SG-04

## Dependencies

- 01 depends on 00 (Accepted).
- 02 depends on 01 (the key it fills must exist).
- 03 depends on 02 (the lane the presets join).
- 04 is independent of 02/03; sequence after 01 for the lint.
- 05 last.

## Not in this mega-goal

- Any change to the significance classifier, the nudge, or what counts as DEBT (ADR-0031's substance).
- Moving `absorb`, `explain`, or `quiz-gate` out of the engine (Reflect and the gate stay).
- Rewriting any moved skill's body beyond path fixes.
- learning-kit's student lane, `study-session`, `teach`, and the rest: untouched.
- The `precedent` tool and `wrap stage`: process plane, stay.
