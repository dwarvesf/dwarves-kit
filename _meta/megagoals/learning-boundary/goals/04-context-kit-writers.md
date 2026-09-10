# Sub-goal 04: the knowledge writers move to context-kit

**Merge policy:** auto
**Time budget:** 2 hours
**Proof:** run-table: `context-kit/skills/{knowledge-capture,memorize}/SKILL.md` exist with `Moved-from:` lines; both resolve their root from `knowledge.root` (the seam context-kit already fills) before any hard-coded path; `ctx-check` on a fixture tree is clean after a `memorize` write; dotfiles `.chezmoiremove` lists both; NEGATIVE CONTROL: with `knowledge.root` unset, `memorize` refuses with the seam name in its message instead of guessing a directory.
**Depends on:** 01 (the lint, so the move leaves no name in the engine).
Model: sonnet
Effort: medium
**Branch:** feat/knowledge-writers (context-kit); chore/retire-knowledge-writers (dotfiles)

## Outcome

Two skills whose whole job is writing knowledge into a tree: `knowledge-capture` (the til leg: format, privacy strip, push) and `memorize` (route a fact to its durable store). They already read `knowledge.root` in spirit; now they read it by name, the seam SPEC-249 gave context-kit. `memorize` is a dotfiles directory; `knowledge-capture` is a chezmoi `symlink_*` entry pointing at `~/workspace/claude-skills/skills/knowledge-capture/`, so its body moves from the claude-skills repo and the dotfiles half is removing the symlink entry. The til privacy gate moves with `knowledge-capture` unchanged and stays the only path to a public note.

## Quality bar

A move, bodies unchanged beyond the root resolution. The privacy gate's rule list is byte-identical. `memorize`'s routing table gains no rows and loses none; only its "repo memory" destination resolves through the seam.

## How to close the loop

Receive in context-kit, retire in dotfiles, verify `bin/config seams` on the operator machine shows `knowledge.root` filled and a `memorize` dry run names it.

**Done =** the proofs above; `rg -l 'knowledge-capture\|memorize' ~/.claude/skills` returns only forwarders.

## Scope edges

**In:** the two skills, their root resolution, the retirements.
**Out:** the study or dev-learner lanes; the concept ledger.
**Not:** a new write path into the tree (context-kit's rule: no non-file write path).
