# repo-layout: implementation notes

The delta from the move manifest. Everything else was done as written.

## Decisions the manifest did not settle

- **`docs/absorption/README.md` already existed.** It described the directory. `docs/ABSORPTION.md` moved onto it, and the old directory text became a closing section "This directory" (naming, what a run records). Nothing was lost, one file now owns both.
- **`docs/v-model.svg` was kept**, moved to `docs/figures/`. `docs/WORKFLOW.md` still links it, so a living file embeds it. Its link was already wrong (`docs/v-model.svg` from inside `docs/`); it is now `figures/v-model.svg`.
- **`CHANGELOG.md` is the real file at the root.** The root stub was removed, `docs/CHANGELOG.md` moved onto it. `bin/release`, `wrap rebase` (its CHANGELOG union path) and the lint exemptions now name the root file. `/kit:ship` and `/kit:kit-health` keep their "docs/CHANGELOG.md wins if present" resolution on purpose: it serves consumer repos that keep a thin root stub, and the kit's own repo resolves to the root file with no code change. The prose that named the path as a backticked repo file now says "the changelog under `docs/`", so the link checker does not flag a path that is runtime-resolved.
- **`wrap rebase` generated-file path** (`_RB_GENERATED`) now names `docs/reference/FEATURES.md`. The wrap fixtures write that path, and create the directory first.
- **`lib/precedent/inventory.py`** scans other repos' registries too. It tries `docs/reference/FEATURES.md` first and keeps `docs/FEATURES.md` as a second candidate so a repo with the old layout still indexes.
- **The doc-drift item set widened.** The living-doc default in `lib/docdrift/refcheck.sh` and `skills/doc-drift/SKILL.md` gained `docs/reference/*.md` and `docs/guides/*.md`. The old default would have stopped checking the reference docs after the move. The root `MANUAL.md` entry went with the stub.
- **`lib/adopt/agents-known.sha256` was regenerated** because `AGENTS.md` changed. One older entry that no branch history carries was kept, so the list only grew.

## Pre-existing behavior surfaced, not fixed

- `tests/test-meta-agents-commands.sh` scanned the root `MANUAL.md` stub for bare agent names. The stub had none, so the check never read the real manual. Pointing it at `docs/MANUAL.md` finds many bare names. The scan was returned to commands, skills and agents only. The manual's bare names are a separate cleanup.

## Left alone on purpose

- `CHANGELOG.md` entries, dated records, and tool-local `docs/` trees under `lib/` keep their old citations.
- Fixtures that model another repo's `docs/research/architecture.md` (`tests/test-repohygiene.sh`) are not kit paths.
- `lib/skill-curator` links are relative to that tool.
