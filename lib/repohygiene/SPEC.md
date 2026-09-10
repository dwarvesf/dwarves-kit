# repohygiene module contract

The cycle spec is `docs/specs/SPEC-256-repo-hygiene.md`; the skill that drives this module is
`skills/repo-hygiene/SKILL.md`. This file pins the invariants a change to `repohygiene.sh`
must not break, so a future edit does not have to re-derive them from the cycle spec.

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
