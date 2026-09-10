# Sub-goal 03: one concept ledger, one flush, the operator preset

**Merge policy:** auto
**Time budget:** 4 hours
**Proof:** run-table: `bin/study-concepts add/check/flush` round-trips a row in the learned-ledger format against a fixture store (`tests/test_study_concepts.sh` updated); `flush` routes `home: research` to a `research/<date>-<slug>.md` and `home: glossary` to a GLOSSARY append, the two homes the dotfiles skill routed to; `skills/concept-flush` is the only flush skill in the estate (`rg -l 'learning-ledger' ~/.claude/skills` returns only forwarders); `presets/operator/skills/{learning-router,learning-day-process,learn-skill,concept-explain,deep-understand}` exist with `Moved-from:` lines; dotfiles `.chezmoiremove` lists all six; NEGATIVE CONTROL: a row already present in a configured store is refused by `add` with the store path named.
**Depends on:** 02.
Model: sonnet
Effort: high
**Branch:** feat/one-ledger (learning-kit); chore/retire-learning-skills (dotfiles)

## Outcome

The decision in ROADMAP.md "Decisions already made" 1, executed. `bin/study-concepts` reads and writes the learned-ledger row format (`status: queued|flushed:<ref>`, `kind`, `home`, the capture-bar fields the dotfiles skill documents) with the store path from `STUDY_CONCEPT_STORES`, so the operator points it at `ops-toolkit/_meta/learned-ledger.md` and a student points it at their vault. `concept-flush` absorbs the dotfiles `learning-ledger` skill's "Flush at session end" section (incidents, research notes, ledger rows) and its return contract (`**Distilled:**`, `**Published:**`); it is what `wrap.after` names on the operator machine from now on. The five teaching and routing skills that fed the ledger move to `presets/operator/skills/` as an installable preset, bodies unchanged beyond paths. Four are dotfiles directories; `learn-skill` is a chezmoi `symlink_*` entry pointing at `~/workspace/claude-skills/skills/learn-skill/`, so its body moves from the claude-skills repo and the dotfiles half is removing the symlink entry.

## Quality bar

The store format is the dotfiles one, byte-compatible with today's `learned-ledger.md`, so no migration of the file. The til leg still routes through `knowledge-capture` (which moves in 04; until then, by its dotfiles name through the seam, never a direct write). The dedup gate keeps its line-level confirmation rule; a filename hit is not a concept hit.

## How to close the loop

Spec the format adoption first; the CLI change is the only code. Then the skill merge (concept-flush absorbs), then the preset move, then the dotfiles retirements. Run `/kit:wrap` once on the operator machine with `wrap.after = "concept-flush"` and confirm the `**Seam:**` line reports it.

**Done =** the proofs above; one flush skill in the estate; `wrap.after` names it; suite green in both repos.

## Scope edges

**In:** the CLI format, the skill merge, the preset, the retirements, the operator `kit.toml` flip.
**Out:** `knowledge-capture` and `memorize` (04).
**Not:** a second store format, a migration script, or any change to what the capture bar accepts.
