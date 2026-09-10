# SPEC-256: repo-hygiene, an audit loop over a repo's own files

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Foundation:** `docs/patterns/audit-loop.md` (four slots, verdict grammar). **Mirrors:** `skills/doc-drift/SKILL.md` (general-purpose, PR-gated apply), `skills/backlog-reconcile/SKILL.md` (batched Tier 1, delta-only Tier 2). **Source:** a hand pass over `ops-toolkit` on 2026-09-10, whose fixes landed as `b2644f33`, `c2e7ae56`, `a7f17ba9`. **Board:** ID-829.

## Problem

Every audit-loop instance the kit ships judges what a file SAYS. `doc-drift` asks whether a
doc still matches the code. `backlog-reconcile` asks whether a row matches its spec.
`ci-drift`, `web-drift`, and `gauntlet-proof-audit` ask the same question of a workflow, a
site, and a run record. None of them asks whether the file should still be sitting where it
is.

That question has a real answer surface and a real cost. A hand pass over one repo found
eight research and brief files written to fixed central paths, each run overwriting the last;
a closed mega-goal still parked in the control surface; a map nothing referenced; and an
append-only log at more than twice the line budget the repo's own docs state. None of that
is a claim drifting from code, so no existing instance would ever look at it.

The hand pass also produced two findings about the pass itself, and they are the reason this
is a spec rather than a script:

- **Verification, not detection, was about 90 percent of the cost.** Finding a candidate is a
  grep. Proving nothing references it, that a duplicate is really a duplicate, that a
  threshold is real, took the rest of the session. A findings list without evidence hands
  that whole cost back to the operator.
- **Route versus trash needed a human call four times, and twice the human chose against the
  recommendation.** A loop that proposes deletions would have been wrong about a third of
  the time, on irreversible actions.

## Decision

Add `lib/repohygiene/` (a bash Tier-1 scanner) and `skills/repo-hygiene/SKILL.md`, an
audit-loop instance whose item is a FILE. Evidence is emitted INLINE per finding. The only
fix the loop ever applies is `git mv`.

### The four slots

| Slot | This instance |
|---|---|
| Item set | five detector classes over ONE git repo, enumerated by `bash lib/repohygiene/repohygiene.sh scan --repo <dir>` |
| Contract | a file earns its place: something references it, or it is young, or it sits with its owner, or it is inside its own documented budget. A gitignored directory has no contract here, only a size and a date |
| Evidence class | Tier 1: the scanner's own per-finding proof, inline. Tier 2: `agents/audit-scanner.md`, dispatched only on the FIX and REMOVE rows |
| Apply mechanics | `git mv` for a confirmed detector-3 FIX, and nothing else. No deletion is applied, proposed as a command, or staged |

### The five detectors

| # | Name | Threshold | Evidence |
|---|---|---|---|
| 1 | `unreferenced-doc` | last touched more than `--stale-days` ago, default 180 | the exact path-boundary `git grep` and its `0 hits outside itself`, plus the last-touch date and age |
| 2 | `stale-inbox` | mtime older than `--inbox-days`, default 30 | the age against the threshold, plus `duplicate-of <path> (identical sha256 <first12>)` when a content-identical copy exists |
| 3 | `misplaced-record` | the owner accounts for at least half the commits touching the file | the owner, the owning-commit count out of the file's total, the latest commit subject, the destination path |
| 4 | `log-budget` | the numbers the repo's own docs state, never the scanner's | total lines against the threshold, the busiest `YYYY-MM` against the per-month threshold, and the quoted `file:line` that states them |
| 5 | `cold-ignored-dir` | at or above `--cold-mb` (default 100) with no file newer than `--cold-days` (default 90) | the size in MB and the cold-since fact, tagged `REPORT ONLY, gitignored, never a deletion proposal` |

### Why the owner comes from commit scope, not from content

Content was tried first against the real pre-fix tree and is too noisy. Of the eight
mis-shelved files, only one yields a single dominant owner by content: a research note names
every tool it surveyed, so a file owned by `vps-mon` also mentions four other tools, and two
of the eight files were empty. The conventional-commit SCOPE of the commits that touched the
file resolves seven of the eight cleanly and the eighth to an honest two-owner UNSURE.

A majority rule guards it: one stray commit under a tool's scope does not claim a file some
other surface owns. Without the rule, `_meta/study-queue.md` was mis-attributed to `vps-mon`
on the strength of a single touch.

### Verdict mapping

| Finding | Verdict | Applied? |
|---|---|---|
| detector 3, one owner confirmed by Tier 2 | FIX | yes, `git mv` |
| detector 3, two or more owners, or a closed mega-goal with no resolvable owner | UNSURE | no |
| detector 2 with a content-identical copy elsewhere | REMOVE, the copy being the named successor | never |
| detector 1, detector 2 without a duplicate | UNSURE | never |
| detector 4 | FIX, rotate or compact per the repo's own procedure | never |
| detector 5 | UNSURE, always | never |

A REMOVE here is a proposal with a named successor, which is what the pattern's grammar
means. The operator deletes. This instance never issues a delete.

## Wiring (one edit per surface)

| Surface | Edit |
|---|---|
| `lib/repohygiene/` | new module: `repohygiene.sh`, `README.md`, `SPEC.md`, `tool.toml`, `docs/proof-of-done.md` |
| `skills/repo-hygiene/SKILL.md` | new skill, auto-namespaced `kit:repo-hygiene`, frontmatter `name` + long-form `description` with NOT-for clauses + `disable-model-invocation: false` |
| `tests/test-repohygiene.sh` | real throwaway git repos per detector, the contract cases (no deletion verb anywhere, every detector-5 finding UNSURE, every finding carries evidence), and a hostile-input block treating the audited repo as untrusted |
| `agents/audit-scanner.md` | its instance list gains repo-hygiene, both in the description and in the body |
| `docs/patterns/audit-loop.md` | a Known-instances paragraph and an SDLC-instances row |
| `README.md` | one row in the skills inventory table, pinned by `tests/test-meta.sh` |
| `docs/FEATURES.md` | regenerated, a generated projection whose freshness `tests/test-meta.sh` pins |
| `_meta/BACKLOG.md` | ID-829 flipped to shipped |

## Non-goals

- No deletion, ever, in any form. Not a `rm`, not a `git rm`, not a staged patch, not a
  suggested command in a PR body.
- No machine-surface scanning. A home folder's abandoned tool dirs, package caches, and
  anything outside a git checkout belong to ops-toolkit `tools/disk-reclaim`, which already
  owns read-first machine cleanup.
- No cross-repo sweep mode. One repo per invocation; a sweep is that command in a loop.
- No new install module, no new hook, no scheduled job.
- No `bin/repohygiene`. ADR-0034 decision 7 admits subsystem entries and module CLIs only;
  `lib/webcheck` is the precedent for a module CLI with no `bin/` entry.
- No content-based owner inference. Measured against the real tree and rejected, above.

## After state

- `bash lib/repohygiene/repohygiene.sh scan --repo <dir>` emits TSV findings, one line each,
  every line carrying its evidence, and exits 0.
- `bash lib/repohygiene/repohygiene.sh detectors` prints the five detector ids.
- A target that is not a git repo exits 2 with a message naming `disk-reclaim`.
- `kit:repo-hygiene` is discoverable and states its own four slots, its detector table, its
  verdict mapping, and its scope boundary.
- `bash tests/test-repohygiene.sh` is green, including the hostile-input block.
- `docs/FEATURES.md` regenerates clean, so `tests/test-meta.sh` gains no new failure.

## Test plan

| Category | Case | Where |
|---|---|---|
| Refusal | a non-git target exits non-zero and names disk-reclaim | `tests/test-repohygiene.sh` |
| Detector 1 | an unreferenced note past the threshold is flagged; a referenced one is not | same |
| Detector 1 | a young file is below the threshold and is not flagged | same |
| Detector 1 | a basename carrying regex metacharacters is matched literally | same |
| Detector 1 | evidence carries the exact grep and its zero-hit result | same |
| Detector 2 | a stale drop with a content-identical copy is REMOVE, naming the path and the sha | same |
| Detector 2 | a stale drop with no duplicate is UNSURE | same |
| Detector 2 | a freshly touched drop leaves the item set (mtime, not git) | same |
| Detector 3 | an owned record is FIX with owner, commit evidence, and destination | same |
| Detector 3 | the control surface's own log is never an owned record | same |
| Detector 3 | a minority owner scope does not claim the file | same |
| Detector 4 | an over-budget log is FIX with counts and the quoted threshold source | same |
| Detector 4 | a repo documenting no budget yields UNSURE with counts, never an invented number | same |
| Detector 5 | a large cold ignored dir is UNSURE tagged REPORT ONLY | same |
| Detector 5 | under the size threshold, or warm, is not flagged | same |
| Contract | no scan output and no scanner line carries a deletion verb against a target repo | same |
| Contract | every detector-5 finding is UNSURE | same |
| Contract | every emitted finding carries a non-trivial evidence field | same |
| Wiring | the skill dispatches `kit:audit-scanner`, names the fallback, and is registered in the pattern doc, README, and the agent | same |
| Hostile input | a newline or tab in a filename or commit subject cannot forge a row or a column | `tests/test-repohygiene.sh` |
| Hostile input | a path shaped like the git-log header does not hide a real candidate | same |
| Hostile input | a non-ASCII path and a path with a space both reach detectors 1 and 3 | same |
| Hostile input | a `..` commit scope never resolves as an owner | same |
| Hostile input | a lax decoy budget cannot suppress the strict one | same |
| Hostile input | an operator-supplied directory outside the repo is refused | same |
| Hostile input | a non-numeric threshold is rejected at parse time | same |
| Acceptance | the detectors rediscover the 2026-09-10 hand-pass findings at their pre-fix commits | `lib/repohygiene/docs/proof-of-done.md` |
| Negative control | break the majority rule, the detector-3 tests go red, restore | same |
| Negative control | make detector 5 emit REMOVE, the report-only cases go red, restore | same |

## Verification

- `bash tests/test-repohygiene.sh` exits 0.
- `bash lib/repohygiene/repohygiene.sh scan --repo <ops-toolkit at b2644f33^> --detectors 3,4`
  reproduces the mis-shelved research and brief files and the over-budget log, recorded in
  `lib/repohygiene/docs/proof-of-done.md`.
- `bash tests/test-meta.sh` fails no more assertions than the pre-branch baseline.
- `bash tests/test-kit-contract.sh` gains no new C3 or C4 offender.
- `bash tests/test-audit-scanner-contract.sh` exits 0.
