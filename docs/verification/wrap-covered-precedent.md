# Proof of done: a fully covered precedent closes as NOTE with a pointer

2026-09-25. Acceptance: `report-lint.sh` fails a `**Built:**` item whose verdict is REPORTED and whose `reported:` reason says "already covers" or "nothing missing", case-insensitive, and tells the author to close it as NOTE with the pointer written. The NOTE form `NOTE <label> ENHANCE <home>: covered, pointer added at <file> (lane=tiny, verified: <check>, <commit>)` passes. Lane: tiny. Files: `commands/wrap.md`, `lib/wrap/report-lint.sh`, `tests/test-wrap.sh`, `docs/CHANGELOG.md`.

## The failure this replaces

A real `/kit:wrap distill` found two candidates where the session hand-rolled code while an existing tool did the whole job. Step 7b printed them as REPORTED with "the existing tool already covers it". Step 10 then had nothing to build and did nothing. The real gap was discoverability, so the next session would hand-roll the same code again.

## Green run

| Command | Exit | Output | Verdict |
|---|---|---|---|
| `bash tests/test-wrap.sh` (before the lint change) | 1 | `test-wrap: 1148 passed, 3 FAILED of 1151` (only the 3 new covered-precedent cases) | RED as expected |
| `bash tests/test-wrap.sh` | 0 | `test-wrap: all 1151 passed` | PASS |
| `bash tests/test-meta.sh` | 0 | clean | PASS |
| `bash tests/test-docs-wiring.sh` | 0 | clean | PASS |
| `bash lib/wrap/report-lint.sh <incident sample>` | 1 | `item 1 is REPORTED but its tool already covers it; close it as NOTE ...`, the NOTE item beside it passes | PASS |

## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' "s/\*'already covers'\*|\*'nothing missing'\*)/*'__negctl_never__'*)/" lib/wrap/report-lint.sh
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS

## Reproduce

`bash lib/gate/negctl.sh . "bash tests/test-wrap.sh" "<the mutation above>"` from a clean checkout of this branch.

## Known interaction

A pointer written as a memory note is a prose target, so a report whose only item is that NOTE also owes `PROSE-ONLY: <why>`. `commands/wrap.md` orders the pointer homes skill trigger first, README or quick-ref second, memory note last, and says so.
