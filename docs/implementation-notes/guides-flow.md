# guides-flow: implementation notes

Scope: rewrite of the spine, v-model, gates-and-proof and autonomy guides, a new review guide, and removal of the lanes guide (folded into the spine guide).

## Decisions the brief did not settle

- Lane tree: the old ASCII decision tree became a question-to-lane table, because the brief bans ASCII box diagrams in guides (the `lanes` figure carries the picture).
- Normal lane: the old lanes guide said normal runs a fresh-context validation and a light test plan. `docs/WORKFLOW.md` now says validation runs on large specs only, so the new text follows WORKFLOW.
- "A tie goes to the heavier lane" is dropped. It no longer matches the classifier, which never picks full from words and leaves the lane choice to the operator.
- Spine fixes carried over from the guides audit: assign claims the row (validate and wrap also flip status), wrap sits after ship, and `/kit:start --full` shows the open queue plus the last five commits.
- Gates guide: the four hard stops are now listed there, the spec-drift guard moved under "advises", and the override command uses `bin/gate proof-ledger override`.
- Autonomy guide: solo decisions are said to land in `docs/implementation-notes/<spec-slug>.md`, because that is the log `/kit:execute` tells the builder to keep. The old text said only "a ledger".
- Samples: the lane-classify lines and the proof-of-done block are real output from a run in this checkout and a temp repo. The start, verify and review samples are the formats quoted from the command sources.

## Link repoints (files outside the slice)

- `docs/guides/README.md`: the lanes row removed, the spine row now covers both.
- `tests/gauntlet/journey.md`: the tiny-lane reference now points at the spine guide.

## Open questions

- The guides index has no row for the new review guide; its owner should add one.
- Five figure files (`loop`, `lanes`, `push-gate`, `review`, `v-model`) do not exist yet. The embeds resolve once the figure PR lands.
