# repohygiene module contract

The cycle spec is `docs/specs/SPEC-256-repo-hygiene.md`; the skill that drives this module is
`skills/repo-hygiene/SKILL.md`. This file pins the invariants a change to `repohygiene.sh`
must not break, so a future edit does not have to re-derive them from the cycle spec.

## Surface

```
repohygiene.sh scan [--repo DIR] [--detectors 1,2,3,4,5]
                    [--stale-days N] [--inbox-days N] [--cold-days N] [--cold-mb N]
                    [--max-candidates N]
                    [--staging-dir D]... [--central-dir D]... [--log GLOB]...
repohygiene.sh detectors
```

TSV on stdout: `detector`, `verdict`, `path`, `evidence`, then a `SUMMARY` row. Exit 0 when
the scan ran, whatever it found; exit 2 on bad usage or a target that is not a git repo.

## Tests

`bash tests/test-repohygiene.sh` (root-level, named for the MODULE so
`tests/test-kit-contract.sh` C4 resolves it).

## Invariants

| # | Invariant | Enforced by |
|---|---|---|
| 1 | The script never deletes anything in a target repo, and never emits a deletion command in a finding | `tests/test-repohygiene.sh` contract cases, both directions (output and source) |
| 2 | Every emitted finding carries a non-trivial evidence field | contract case, asserted over a full five-detector run |
| 3 | Every detector-5 finding is `UNSURE`; a gitignored path never earns `FIX` or `REMOVE` | contract case |
| 4 | Detector 4 never invents a threshold; no documented budget yields `UNSURE` with the counts | detector-4 cases |
| 5 | A basename entering a grep pattern is regex-escaped first | detector-1 metacharacter case |
| 6 | A target that is not a git repo is refused, naming `disk-reclaim` | refusal-guard case |
| 7 | The only mutation the loop ever applies is `git mv`, applied by the skill, never by this script | invariant 1 plus the skill's own Apply step |

## Mega-goal completion precedence

**Invariant.** A mega-goal folder's completion is decided by the folder's own record, per the
precedence below, and a commit subject alone never earns it a `FIX`. Enforced by the mega-goal
completion cases in `tests/test-repohygiene.sh`, one per real misread.

Detector 3 judges mega-goal FOLDERS as well as files. A folder's completion test runs in this
order, and stops at the first step that answers:

| # | Step | Effect |
|---|---|---|
| 1 | An explicit status marker in the folder's top-level docs: a `Status:` or `State:` heading or bold label. An OPEN marker anywhere wins over a closed one | open, no finding. closed, continue |
| 2 | An unchecked checklist item anywhere in the folder (`- [ ]`, and the `- [~]` in-progress form), counted only at the start of a line or of a table cell | any open item, no finding, or `UNSURE` when a closed marker contradicts it |
| 3 | Only for a folder that declares nothing: the commit subjects that touched it | `UNSURE` at most, never `FIX` |

`FIX` requires all three: a closed marker, no open item, and a commit scope that resolves an
owner to give the move a destination.

The order exists because commit keywords alone were the first test and misread three of five
real folders on the first live run. A sweep commit reading "co-locate completed mega-goals"
carries a keyword about OTHER goals, and "mochi build complete, 08 shipped" closed nothing
while that folder's ROADMAP still carried four open sub-goals. Detector 3 is the one verdict
the loop acts on, so its precision is load-bearing. Full before-and-after:
`docs/proof-of-done.md`.

Two consequences, both deliberate:

- **A stale unchecked box suppresses a genuinely finished goal.** Two of the five real folders
  were finished but never had their last box flipped. The loop stays silent on them rather
  than moving a folder whose own record says it is unfinished, because a missed move costs one
  un-filed finding and a wrong move takes a live engine out of the control surface.
- **Prose describing a checkbox is not an open sub-goal.** Every POINTER_PROMPT.md in the
  estate spells the convention out mid-sentence as `` `- [ ] NN-... PR #N` ``. Matching that
  instruction made all seven already-archived mega-goals read as unfinished, so a box counts
  only at the start of a line or of a table cell, which is where a checklist puts one.
- **A checklist inside a fenced code block still counts**, because the line anchor cannot see
  the fence. The effect is conservative (the folder reads unfinished and no finding is
  emitted), so it costs a missed move, never a wrong one.

## The audited repo is hostile input

A contributor to the audited repo picks its filenames and its commit subjects, and a
detector-3 FIX row is the one verdict the loop acts on. These invariants exist because a
review broke each one against a live fixture, not as precautions.

| # | Invariant | Enforced by |
|---|---|---|
| 8 | Every TSV field is scrubbed of tab, newline, and carriage return in `emit`, so no filename or commit subject can forge a row or a column | hostile-input field-count case |
| 9 | The git-log header is found by the blank line that follows it, never by a text prefix a path could carry | hostile-input `COMMIT <ts>` path case |
| 10 | Paths arrive NUL-delimited with `core.quotePath=false`, so a non-ASCII or spaced path never drops out of a detector | hostile-input unicode and spaced-path cases |
| 11 | A commit scope must start alphanumeric and carry no `..` segment before it can name an owner | hostile-input traversal case |
| 12 | Detector 4 reads EVERY matching threshold source and takes the strictest, so a lax decoy cannot suppress a real finding | detector-4 decoy case |
| 13 | An operator-supplied `--staging-dir` or `--central-dir` that resolves outside the repo root is refused | hostile-input out-of-repo case |
| 14 | Every numeric flag is validated before any arithmetic or `find` argument sees it | hostile-input non-numeric-threshold case |
| 15 | An unreadable age fails CLOSED (`-1`, older than any threshold), so a poisoned timestamp keeps the item in the set instead of skipping it | `days_since` guard, exercised by invariant 9's case |

## Deliberate deviations

- **Detector 1's reference grep stays per-candidate**, against the kit's usual batch-it rule.
  A batched alternation would prove the SET unreferenced without proving any single member
  so, and the per-candidate command IS the evidence the finding carries. The batch discipline
  applies instead to the age pass, which is one `git log --name-only` subprocess for the whole
  repo. `--max-candidates` bounds the per-candidate cost.
- **Detector 3 reads git history, not file content**, for owner inference. Content was
  measured against the real pre-fix tree and resolves one of eight files; commit scope
  resolves seven cleanly and the eighth to an honest two-owner `UNSURE`.
- **Detector 2 reads filesystem mtime, not git**, because a staging directory is normally
  gitignored and has no history to read.

## Portability

`stat` is the one portable hazard (BSD `-f %m` against GNU `-c %Y`) and every age in the
script goes through `mtime_of`, so the split lives in exactly one place. The script targets
bash 3.2, the version macOS ships: no associative arrays, no `mapfile`.
