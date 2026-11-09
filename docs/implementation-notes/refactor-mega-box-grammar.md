# refactor-mega-box-grammar: implementation notes

Brief: `docs/briefs/DECISION-BRIEF-declared-state-machines.md` (the "Mega sub-goal box" row). Suite: `tests/test-mega-box.sh`. This file is the delta only.

## Decisions not in the brief

- The box and id grammar lives in one file, `lib/mega/box.tsv`, with rows `box` (open, done, parked) and `id` (sg, slug). Aliases: `[X]` is done, `[-]` is parked. `box.sh` serves bash, `box.py` serves Python (loaded by path with importlib, as `mega-review.py` already loads `proof-table-gen.py`).
- Classes reuse the board vocabulary: open is `active`, done is `terminal`, parked is `hold`. Parked counts as not done and never makes a mega active.
- One slug id: `[0-9]+[A-Za-z]?-[A-Za-z][A-Za-z0-9_-]*`. The letter after the dash drops date-led notes (`2026-11-09 ...`), as `work.sh` already did. The optional letter after the digits keeps `02b-` ids, which `mega-report.py` accepted and the other four readers silently dropped.
- Per-reader intent kept: the orchestrator walks SG-NN sub-goals only (goal file `goals/NN-*.md`, branch `wave/sg-NN`, `depends SG-NN` all assume it), so it names the `sg` row, not the union. Parked is never listed there, so `_subgoals` still emits only 0 and 1 and no consumer sees a third value. `megagoals.sh`, `board-mirror.sh` and `mega-cleanup` keep their no-id-required counts.
- `megagoals.sh` totals now include parked boxes. A mega is listed only while an open box remains (was: done below total), so a parked-only mega stays hidden as before.
- `board-mirror.sh` progress is `done/total` with parked in the total. A card for a mega with a parked box gets one content comment on the next tick (the note text changed).
- `mega-report.py` keeps open and done only (a parked sub-goal never ran, so it has no telemetry row). SG-NN rows take their name from `goals/NN-<slug>.md`, else the first title words.
- `mega.sh` skips a box character the table does not declare. It used to accept any single character as an open box.
- `board-run.sh` writes `[ ]` through `box_token open`, so the scaffold writer and the readers share one token.

## Held flag

The old rule was the substring `held` anywhere in the ROADMAP, which also matched "withheld", "held as strings" and "HELD for six of nine apps". New rule, from what the writers record:

- the orchestrator's `.orchestrate/events.log`: a `held` event (the tier-4 close) or a `blocked` event "awaiting human merge" (a gate hold) not superseded by a later event for the same id; or
- an open `gate` or `gate!` sub-goal line that names its `PR #<n>` (the contract `commands/mega.md` gives: gate sub-goal opens a held PR, box stays open).

`mega-merge.sh` hold labels live on the GitHub PR, not in the ROADMAP, so the mirror cannot read them offline. Not used.

## Row-to-card map

`lib/board/native-map.tsv` (state, native) is read by `board-mirror.sh _target_native` and `board-mirror-cleanup.py`. `states.tsv` is untouched. The reverse map in `board-writeback.sh` stays by hand: it is many-to-one the other way and the brief leaves it alone.

## Left as is, with the reason

- `_sub_branch` in `mega.sh` looks for `goals/<id>.md`, so an SG-NN row has no branch signal in `mega status`. `work.sh` and the orchestrator resolve SG goal files by `goals/NN-*.md`. Fixing it changes SG classifications (PENDING to WIP or STALLED), so it is a separate change. `mega review` now lists SG rows with the PR check only.
- `hooks/context-readiness.sh` and `lib/spec/*` read spec task boxes, a different grammar.

## Open questions

- Should `mega.sh _sub_branch` learn the `goals/NN-*.md` lookup? It would give SG roadmaps real git truth.
- Should a parked-only mega show in `megagoals list` with a "parked" marker instead of hiding?

## Follow-up: SG-NN branch signal and parked marker

- `_sub_branch` resolves an SG-NN goal file as `goals/NN-*.md` (first match, as `orchestrate.sh _goalfile` does). With no `**Branch:**` line it falls back to `wave/sg-nn` only when that ref exists in the code root, so a branch nobody created is never printed.
- `megagoals list` shows a mega whose only unfinished boxes are parked, ending the line with ` (parked)`. A fully done mega stays hidden without `--all`. The marker is last so fields 1 to 4 keep their positions.
- Offline measure (local git, `gh` stubbed): 3 of 7 SG roadmaps gain `branch=` text, none change label, because the named branches are not in those repos' local refs. `mega review` reads the same status lines.
