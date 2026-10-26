# History

The public release tree carries the kit, its design record and its living docs. The old internal history records were removed from it.

## What was removed

Dated working records that nothing reads at runtime:

- `docs/verification/`: proof-of-done records and run logs, except the files listed below
- `docs/implementation-notes/`, `docs/retro/`, and the audit reports (the `audits/` folder under `docs/`)
- `docs/research/`: the dated scans (`research/foundations/` stays)
- `docs/briefs/`: the dated briefs (the brief template, `CONTEXT.md` and the docs rewrite ledger stay)
- `docs/absorption/`: the dated reports (the ritual README and `TEMPLATE.md` stay)
- `_meta/megagoals/_archive/`: the closed mega-goal folders (the whole `_meta/` tree has since moved to the private `dwarves-kit-internal` repo)

## What stays

- `docs/specs/`, `docs/decisions/`, `docs/releases/` and `CHANGELOG.md`: the design record, whole
- `docs/verification/gauntlet/`: the corpus the gauntlet-proof-audit skill checks
- Files code, tests or commands read at runtime: the task-type registry, the test-design standard, the rejected-findings ledger, `COUNTS.md`, `done-modes.md`, the lanes-as-data baseline and the ceremony-lens baseline
- Every `README.md` and `TEMPLATE.md` in these folders

## Read an old file

Every removed file is kept by the annotated tag `history/2026-10-27`.

```
git fetch origin tag history/2026-10-27
git show history/2026-10-27:docs/verification/advisor.md
git ls-tree -r --name-only history/2026-10-27 docs/retro
```

On GitHub: `https://github.com/dwarvesf/dwarves-kit/tree/history/2026-10-27`.

Specs, decisions, the changelog and the board still cite removed paths. Those paths resolve at the tag. Living docs and code comments cite them as `history/2026-10-27:<path>`.

## New work

Nothing changes for new work. Proof of done still goes in `docs/verification/`, implementation notes in `docs/implementation-notes/`, retros in `docs/retro/`, research in `docs/research/`, and briefs in `docs/briefs/`. The ship gate, `/kit:retro` and the other commands write there as before.

## Restore

To bring a removed file back, check it out of the tag: `git checkout history/2026-10-27 -- <path>`. To undo the whole prune, revert its squash commit.
