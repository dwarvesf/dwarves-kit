# doc-figures implementation notes

## Decisions the brief did not settle

- **Hash input.** A sheet's hash is sha256 of the lines between its `uml` fences, each ended by a newline. Prose, headings and other sheets never move it. Confirmed by a test: appending prose leaves `check` green.
- **Scale 2.** `render` sets `SHOT_SCALE=2` unless the caller sets it. The 1x shots of small sheets fall under the 10 KB floor in `shots.mjs`, and 2x text reads at README width.
- **Scratch shots.** `render` shoots into a temp directory and moves only `d-<id>.png` to `<id>.png`. A stray never reaches the output directory, so no delete step exists. `check` reports a PNG the manifest does not list.
- **Root override.** `DOC_FIGURES_ROOT` sets the root `check` scans for `README.md` and `docs/**/*.md`. The tests use it to point at temp copies. Default is the repo root.
- **Reference pattern.** `figures/<id>.png` with `[A-Za-z0-9_-]` ids. The `<id>` placeholder in prose never matches.

## Layout choices forced by the renderer

- Sequence labels sit on the arrow midpoint. An arrow that spans two lifelines puts its label on the middle lifeline. Every sequence sheet is a chain, so each arrow spans neighbors; a third party that would break the chain became a self message (execute, wrap, gauntlet) or a merged participant (push-gate: `ledgers`).
- Edge labels on a shared bus land mid-path and read as belonging to a neighbor. `lanes` carries its condition in each node note instead of on the edge.
- A component note allows about three lines, then overflows the box. Notes stay under about 65 characters.

## Deviations from the brief's figure table

- **wrap:** the board flip comes first, not last. `/kit:wrap` step 1 flips the row; `wrap land` itself never touches the board. The figure follows the source.
- **execute:** `you` is not a participant. Both human moments (say go, decide on escalate) are self messages on `/kit:execute`, and the fix-agent is a self message too. This avoids labels that sit on a lifeline.
- **review:** the `## Review` write and read are self messages. The spec is not a participant.
- **debug:** five states, phases 0 to 4, because the source numbers the feedback loop as phase 0.

## Skips

- No dark variant (RL-05).
- No `review:` items (brief).
- `loop` omits the FIX THEN SHIP edge back from review to execute; the caption and the review figure carry it.

## Open

- `board-row`: nothing flips `validated` to `executing`. The figure marks it amber, "you, by hand". If a command takes that over, update the sheet.
