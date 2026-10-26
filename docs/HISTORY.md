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

The public history was squashed into one commit for the release. The full pre-squash history, every old tag (including `history/2026-10-27`) and every removed file live in the private `dwarvesf/dwarves-kit-internal` repo, on branch `archive/master-pre-squash`. Maintainers with access read an old file there:

```
git clone git@github.com:dwarvesf/dwarves-kit-internal.git
git -C dwarves-kit-internal show history/2026-10-27:docs/verification/advisor.md
```

Specs, decisions and the changelog still cite removed paths, and living docs and code comments cite them as `history/2026-10-27:<path>`. Those paths resolve in the private archive.

## New work

Nothing changes for new work. Proof of done still goes in `docs/verification/`, implementation notes in `docs/implementation-notes/`, retros in `docs/retro/`, research in `docs/research/`, and briefs in `docs/briefs/`. The ship gate, `/kit:retro` and the other commands write there as before.

## Restore

To bring a removed file back, copy it from the private archive at `history/2026-10-27`.
