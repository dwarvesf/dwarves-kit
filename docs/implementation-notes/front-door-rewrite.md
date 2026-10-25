# Front door rewrite: implementation notes

Delta from the brief, not a mirror of it.

## Decisions the brief did not settle

- Rosters were not copied into the MANUAL. The command, agent and hook rosters already live in `docs/MANUAL.md` (one `### /kit:<name>` section per command, an agents table) and `docs/hooks.md` (every hook file). The README copies were dropped; the row-count pins now read those homes.
- Only the skills table had no home. It moved into the MANUAL as `## Skills (Claude-triggered)`.
- Credits moved to the MANUAL. `/kit:kit-health`, `/kit:absorb` and `docs/ABSORPTION.md` parse or cite them, so those three were repointed by one line each.
- "Your first cycle" and "Changelog" were dropped from the moved block: QUICKSTART and the README link list replace them.
- The tests that pinned README rows now pin MANUAL and `docs/hooks.md`. The kit-contract dispatcher check reads the MANUAL agents table, which is stricter than the README row was.
- `check-submission-user*.sh` greps read the fixture repo's README, not the kit's, so they needed no change. `tier1.sh` gained `docs/QUICKSTART.md` in its existence list.

## Skips

- Mermaid and ASCII diagrams moved into the MANUAL as they were. RL-03 scopes README, QUICKSTART and guides only.
- Comments in `install.sh` and one test still say "README Option 2". Only the user-visible installer message was repointed.

## Open

- README and QUICKSTART link `docs/figures/loop.png`, `docs/figures/adopt.png` and the new `adopt`, `review`, `wrap` guides; they resolve once the figure and guide branches land.
- The doc-drift Tier 1 pass shows only those pending links dead on the new files.
