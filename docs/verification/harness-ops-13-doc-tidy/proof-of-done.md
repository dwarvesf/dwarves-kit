# Proof of done: harness-ops-13-doc-tidy

Sub-goal: `_meta/megagoals/harness-ops/goals/13-doc-tidy.md` ("doc-tidy"), the FINAL sub-goal
of the `harness-ops` mega-goal (TIER-4 close).

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | The 90KB one-off report moves to a `docs/audits/` home; no reader references the old path | PASS | `git mv docs/verification/skillspector-report-2026-06-25.md docs/audits/skillspector-report-2026-06-25.md`; grep sweep below |
| AC2 | `kit.toml.example` placement settled | PASS (already resolved by sub-goal 04) | `git ls-files \| grep kit.toml.example` -> empty; repo-root `kit.toml` exists (promoted). 2 stale mentions in `docs/briefs/DECISION-BRIEF-config-layer.md` repointed to say the file is now `kit.toml` |
| AC3 (conductor-assigned orphan) | `docs/runs/harness-ops-03-mega.md` (leftover generated proof-table sub-goal 11's move missed) relocates to `docs/verification/generated/`; `docs/runs/` is gone | PASS | `git mv docs/runs/harness-ops-03-mega.md docs/verification/generated/harness-ops-03-mega.md`; `rmdir docs/runs` (auto-emptied); `ls docs/runs` -> "No such file or directory" |
| AC4 | `docs/README.md`'s subfolder map matches the real `docs/` tree | PASS | see "README-matches-tree" below |
| AC5 | No dangling functional reference to any moved path | PASS | see "Dangling-reference sweep" below |

## Dangling-reference sweep

```
$ grep -rn 'docs/verification/skillspector-report' --include='*.sh' --include='*.py' --include='*.md' .
./_meta/megagoals/harness-ops/goals/13-doc-tidy.md:18   # the conductor-owned goal file, describing THIS task; not a live reader
./docs/verification/briefs-out/proof-of-done.md:26      # historical dangling-reference sweep from sub-goal 10, dated snapshot of the tree at that time; not a live pointer

$ grep -rn 'docs/runs/harness-ops-03-mega' --include='*.sh' --include='*.py' --include='*.md' .
(no output -- both live references (docs/verification/ho-03-wire-mega/proof-of-done.md lines 4 + 112)
 were repointed to docs/verification/generated/harness-ops-03-mega.md in this branch)

$ grep -rn 'kit.toml.example' --include='*.md' --include='*.sh' .
(remaining hits are all historical/comment: docs/specs/SPEC-183-*, docs/verification/manifest-reconcile/proof-of-done.md,
 tests/test-install-modules.sh (asserts the .example no longer exists), lib/queue/orchestrate.sh (comment on the shipped
 default's lineage) -- none assert the file currently exists at repo root; the 2 live-intent mentions in
 docs/briefs/DECISION-BRIEF-config-layer.md were repointed to `kit.toml`)
```

The two remaining `skillspector-report` hits and the historical `kit.toml.example` hits are
point-in-time records (a conductor contract file and dated proof/spec snapshots describing what
was true when written) -- not live pointers whose behavior or accuracy breaks from the move.
No code (`.sh`/`.py`) references either moved path anywhere.

## README-matches-tree

```
$ ls docs/
absorption/  audits/  briefs/  decisions/  implementation-notes/  releases/  research/
retro/  specs/  verification/
ABSORPTION.md  CHANGELOG.md  MANUAL.md  PHILOSOPHY.md  README.md  WORKFLOW.md
architecture.md  consumer-contract.md  v-model.svg

$ grep -oE '`[a-zA-Z_.-]+/?`' docs/README.md | tr -d '`' | sort -u
ABSORPTION.md  CHANGELOG.md  MANUAL.md  PHILOSOPHY.md  README.md  WORKFLOW.md  architecture.md
absorption/  audits/  briefs/  consumer-contract.md  decisions/  implementation-notes/
releases/  research/  retro/  specs/  verification/  (+ docs/, CONTEXT.md, proof-of-done.md,
proof-table-gen.sh as incidental in-prose mentions, not map rows)
```

Every subdirectory and doc file in `ls docs/` is named in `docs/README.md`'s "What's here" table
and/or the "full record, by theme" section, EXCEPT `v-model.svg` (a supporting image asset embedded
by `WORKFLOW.md`/`CHANGELOG.md`/the root README hero, not a standalone doc class -- consistent with
the map's existing convention of listing doc classes, not every asset file).

The map now also states plainly: `verification/generated/` is where `proof-table-gen.sh` writes
(folding in the old repo-root `docs/runs/`), and there is no separate `docs/proof/` (sub-goal 09
folded it into `verification/` already).

## Deviations from the goal file

- The goal file's Scope edges list task (c), the `docs/runs/harness-ops-03-mega.md` orphan
  relocation, as conductor-assigned (added to this dispatch after the goal file was written;
  not in the original `## How to close the loop` bullets). Handled per the dispatch instructions.
- Repointed 2 live references to the moved `docs/runs/harness-ops-03-mega.md` path inside
  `docs/verification/ho-03-wire-mega/proof-of-done.md` (not explicitly named in the contract, but
  a direct consequence of the AC3 move -- leaving them would make that proof doc's "Canonical
  companion run-table" pointer and regen-command comment wrong).
- `kit.toml.example` AC2 required no move (already fully resolved by sub-goal 04); only fixed the
  2 stale prose references the goal file flagged in the config brief.

## Reproduce

```
git mv docs/verification/skillspector-report-2026-06-25.md docs/audits/skillspector-report-2026-06-25.md
git mv docs/runs/harness-ops-03-mega.md docs/verification/generated/harness-ops-03-mega.md
rmdir docs/runs   # auto-empty after the move
bash tests/test-meta.sh
bash tests/test-docs-wiring.sh
```
