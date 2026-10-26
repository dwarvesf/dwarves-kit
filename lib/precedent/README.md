# precedent

Answers "have we done something like this before?" at intake. The records surface reads the written record (specs, decisions, retros, verification, run ledger). The inventory surface reads what was built (tools, scripts, skills, commands, agents, crons, memory notes).

**Entry points**
- `lib/precedent/precedent.sh find "<task>" [--surface records|inventory|all] [--limit N] [--quiet] [--json] [--registry <file>] [--repo-root <path>]`: ranked hits. Unquoted words also work. The default surface is `all`.
- `lib/precedent/precedent.sh find --explain "<hit label>"`: show the header of the file behind an inventory hit.
- `lib/precedent/precedent.sh find "<words>" [--layer L] [--cluster C] [--kind K]`: filter inventory hits by declared layer, cluster, or kind.
- `lib/precedent/precedent.sh index [--layer L] [--cluster C] [--kind K] [--out <file>]`: a markdown page of every item.
- `bin/precedent` forwards to `lib/precedent/precedent.sh`.

**Layout**
- `precedent.sh`: the verb dispatcher and the grep-based records surface.
- `inventory.py`: the inventory scanner and scorer, called by `precedent.sh`.

**Tests**: `bash tests/test-precedent.sh` and `bash tests/test-precedent-index.sh`.

**Spec and docs**: `docs/specs/SPEC-068-precedent-lookup.md`, `docs/specs/SPEC-245-precedent-inventory.md`, `docs/specs/SPEC-308-precedent-partial-match.md`.
