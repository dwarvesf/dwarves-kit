# Mega-goal: learning-boundary

**Destination:** Every learning-shaped surface in the estate lives in the kit whose learner it serves, and the engine knows none of them by name. dwarves-kit keeps the process plane (gates, ledgers, the landing step, telemetry reflection) and exactly one seam key per hand-off. learning-kit owns every skill and command whose subject is a person understanding something, in two lanes: `study` (students, the existing lanes.d/study.plan) and `dev-learner` (an engineer understanding the code they shipped, today's understanding gate). context-kit owns every skill whose job is writing knowledge into the tree. One concept ledger, one store format, one flush skill.
**Quality bar:** No consumer named in the engine (SPEC-249's rule, now enforced by a lint over `lib/`, `commands/`, `tests/`). No second engine: every move is a `git mv` plus a path fix plus a seam key, never a rewrite. Each move ships with its tests and its proof-of-done file, and the engine's suite stays green with zero skips at every sub-goal boundary. Adopters of dwarves-kit alone lose nothing they had that was not already dark for them (the moved commands only ever worked with the operator's dotfiles present).
**Work repo:** dwarves-kit for 00, 01, 05; learning-kit for 02, 03; context-kit for 04; dotfiles carries the retirements (chezmoi remove entries) in the same PR as each move.
**Stacking tool:** gh, one PR per sub-goal, sequential (cross-repo, no stacking).
**Merge mode:** bottom-up, each sub-goal merged before the next starts.
**Merge autonomy:** gated-final on 00 (the ADR is Han's click); `auto` from 01 on.
**Terminus:** 05 merged and `bin/config seams` shows `wrap.learn` filled by learning-kit's `dev-learner` lane on the operator machine.
**Started:** 2026-09-10

## Gate zero (decision before code)

**ADR-0031 placed the understanding gate INSIDE dwarves-kit**, on purpose, in 2026-07 (accepted, PR #146). Its substance stands: significance classification, the DEBT marker, the nudge, the weekend paydown. What this mega-goal reverses is only its PLACEMENT of the pedagogy: `/kit:explain`, `/kit:quiz-gate`, `/kit:absorb`, and the weekend paydown orchestration are learning about code, which by the operator's stated rule (2026-09-10: "if the learning skill happens to be in the dev kit, it should belong to the learning kit") is learning-kit's. Sub-goal 00 writes the superseding ADR and stops for Han's acceptance. Nothing after it starts until that ADR reads Accepted.

## Decisions already made (2026-09-10, operator said "proceed all")

1. **The surviving concept store is `learned-ledger.md`'s format**, today at `ops-toolkit/_meta/learned-ledger.md`. It has the routing (til, research, GLOSSARY) and the history. learning-kit's `bin/study-concepts` becomes its CLI: same verbs (`add`, `check`, `flush`), reads and writes that format, store path from `STUDY_CONCEPT_STORES`. The dotfiles `learning-ledger` skill and learning-kit's `concept-flush` collapse into ONE skill in learning-kit; dotfiles keeps a one-line chezmoi remove.
2. **The engine keeps the DEBT ledger writer and reader** (`significance-classify.sh record`, `learn debt list/collect/mark-paid`): those are process records about which shipped changes were significant, data the engine produces. What moves is everything that TEACHES from that data.
3. **Engine `learn propose/drain` is renamed `reflect`.** It reads gate telemetry and stages backlog rows; nothing about it is learning, and the name is the reason the boundary has been unreadable.
4. **One seam key, `wrap.learn`**, replaces the engine's knowledge of Step 7a's consumer. `wrap.before` and `wrap.after` stay as the generic seams they are.

## Authority

SPEC-249 (estate seams, the one-config-key rule). ADR-0031 (superseded in placement by 00's ADR, not in substance). learning-kit `docs/ARCHITECTURE.md` (the overlay contract). The candidate-scan finding that opened this: `ops-toolkit` session 2026-09-10, the transcript tally in dwarves-kit `docs/verification/wrap-candidates-scan.md`.

## Sub-goals

- [ ] 00-adr-placement , the superseding ADR: learning lives in the learner's kit, the engine keeps one seam per hand-off; supersedes ADR-0031 §placement only , `gated-final`
- [ ] 01-engine-seam-and-lint , `wrap.learn` key + registry row + seams-table row; Step 7a/7c prose calls the seam, not a skill; `lib/`+`commands/`+`tests/` lint that fails on any consumer skill name or dotfiles path; `learn` → `reflect` rename with a forwarder , `auto`
- [ ] 02-dev-learner-lane , learning-kit gains `lanes.d/dev-learner.plan` + `skills/{explain,quiz-gate,absorb,weekend-paydown}` moved from dwarves-kit `commands/` and dotfiles `weekend-debt-paydown` (git mv across repos = copy with `Moved-from:` trailer), their tests, the install step that fills `wrap.learn` , `auto`
- [ ] 03-one-ledger , `bin/study-concepts` adopts the learned-ledger format; `concept-flush` + dotfiles `learning-ledger` → one `concept-flush`; dotfiles `learning-router`, `learning-day-process`, `learn-skill`, `concept-explain`, `deep-understand` → learning-kit `presets/operator/skills/`; chezmoi remove entries , `auto`
- [ ] 04-context-kit-writers , dotfiles `knowledge-capture` + `memorize` → context-kit `skills/`; both already write into a tree and both name `knowledge.root`; chezmoi remove entries , `auto`
- [ ] 05-docs-and-terminus , WORKFLOW.md, AGENTS.md, README of all three kits state the boundary in one table; `config seams` on the operator machine shows every seam filled by the kit the table names; SPEC-249's `## Seams` gains `wrap.learn` , `auto`

## Dependencies

- 01 depends on 00 (Accepted).
- 02 depends on 01 (the key it fills must exist).
- 03 depends on 02 (the lane the presets join).
- 04 is independent of 02/03; sequence after 01 for the lint.
- 05 last.

## Not in this mega-goal

- Any change to the significance classifier, the nudge, or what counts as DEBT (ADR-0031's substance).
- Rewriting any moved skill's body beyond path fixes.
- learning-kit's student lane, `study-session`, `teach`, and the rest: untouched.
- The `precedent` tool and `wrap stage`: process plane, stay.
