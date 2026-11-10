# Audit pass state: delta note

## Decisions not in the brief

- No `audit status` verb exists. `audit due` is the only lister, so the two new states replace the DUE column value. No new column, so a ran-only log prints byte for byte as before.
- The timeout is a constant (`STARTED_TIMEOUT_SECS`, 6 hours) in `lib/audit/audit.sh`. The kit has no audit config section, so no knob.
- A `started` line is `<epoch> <iso> <instance> started`: exactly four fields, note `started`. A `ran` line with any other note, or a longer note that begins with `started`, still counts as a ran.
- `last_run_epoch` now skips started lines. Without that, `start` would clear DUE.
- A started line only matters when it is strictly newer than the last ran. Same-second ties read as ran.
- `start` refuses an undeclared instance like `ran` does. The check moved into one shared `require_declared` helper.
- Skills: one unnumbered line under `## Process` in each of the eight audit skills, so step numbers stay put. It says to start after any refusal guard passes, so a refused pass does not log as started.

## Tradeoffs

- A `ran` call with the literal single-word note `started` reads as a started line. Accepted: no skill writes that note.
- `start` does not clear an earlier abandoned start. The next `ran` does, and a second `start` supersedes it.

## Open questions

- None.
