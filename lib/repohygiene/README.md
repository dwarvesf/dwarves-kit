# repohygiene

Tier 1 of the `kit:repo-hygiene` audit loop. It enumerates files inside ONE git repo that
have decayed and prints one finding per line, each carrying the evidence that proves it. It
is mechanical and costs no model tokens.

The skill that drives it is `skills/repo-hygiene/SKILL.md`; the contract both implement is
`docs/specs/SPEC-256-repo-hygiene.md`; the pattern is `docs/patterns/audit-loop.md`.

## Use

```
bash lib/repohygiene/repohygiene.sh scan --repo /path/to/repo
bash lib/repohygiene/repohygiene.sh scan --repo . --detectors 3,4
bash lib/repohygiene/repohygiene.sh detectors
```

Output is TSV: `detector`, `verdict`, `path`, `evidence`, then a `SUMMARY` line. Only
findings are printed, so an empty body is a clean repo. Verdicts are the audit-loop grammar
(`FIX`, `REMOVE`, `UNSURE`); `OK` items are never emitted.

## Detectors

| # | Name | Flags | Default threshold |
|---|---|---|---|
| 1 | `unreferenced-doc` | a tracked non-code file no other tracked file references | older than `--stale-days 180` |
| 2 | `stale-inbox` | an entry under `_inbox` / `inbox` / `_staging` | mtime older than `--inbox-days 30` |
| 3 | `misplaced-record` | a record in `_meta` / `docs/research` / `docs/briefs` owned by one tool or experiment | the owner holds at least half the file's commits |
| 4 | `log-budget` | an append-only log past the budget the repo's own docs state | the repo's numbers, never ours |
| 5 | `cold-ignored-dir` | a gitignored directory that is large and cold | `--cold-mb 100`, `--cold-days 90` |

Overrides: `--staging-dir`, `--central-dir`, `--log` (each repeatable), and
`--max-candidates` for detector 1's per-candidate grep budget.

## What it will not do

- **It never deletes, and never proposes a deletion command.** The only fix the loop applies
  is `git mv` for a detector-3 finding, and the skill applies it, not this script. Detector 5
  is REPORT ONLY unconditionally: the scanner cannot see what a gitignored path is for.
- **It never invents a threshold for detector 4.** A repo that documents no line budget gets
  the counts and an honest UNSURE.
- **It never leaves a git repo.** The machine surface, a home folder's abandoned tool dirs,
  package caches, anything outside a checkout, belongs to ops-toolkit `tools/disk-reclaim`.
  A non-git target is refused with that pointer.

## Cost

Detector 1 is the expensive half: one age pass over the whole history (batched, one
subprocess) and then one `git grep` per candidate past the age threshold. That per-candidate
grep IS the evidence, so it is not batched away. A threshold low enough to admit thousands of
candidates hits `--max-candidates` and reports the overflow rather than running for minutes.
Detectors 2 through 5 are seconds on any repo.
