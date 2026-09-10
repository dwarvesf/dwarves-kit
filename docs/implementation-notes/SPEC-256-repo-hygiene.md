# Implementation notes: SPEC-256 repo-hygiene

Delta from the spec only. The spec was written after the scanner was measured against the
real pre-fix tree, so most of what would otherwise be a deviation is already in the spec's
own Decision section.

## 2026-09-10 Owner inference moved from content to commit scope

Context: detector 3 has to name a file's owner. The obvious signal is the file's contents,
which mention `tools/<x>` or `experiments/<x>` paths.

Decision: use the conventional-commit scope of the commits that touched the file instead.

Why: measured against `ops-toolkit` at `b2644f33^`. Of the eight mis-shelved files, content
resolves a single dominant owner for one. A research note names every tool it surveyed, so a
file owned by `vps-mon` also mentions `hermes`, `cal-sync`, and `op-watchtower`. Two of the
eight files were empty and name nothing at all. Commit scope resolves seven cleanly and the
eighth to a two-owner `UNSURE`.

Impact: detector 3 needs git history, so it cannot judge an uncommitted file. That is the
right trade: an uncommitted record is not yet parked anywhere.

Open questions: none.

## 2026-09-10 A majority rule guards the owner

Context: the first commit-scope version attributed `_meta/study-queue.md` to `tools/vps-mon`
on the strength of one commit out of many.

Decision: an owner wins only when it accounts for at least half the commits touching the file.

Why: a control-surface file gets touched by whoever passes through. One touch under a tool's
scope is a coincidence, and acting on it would move a record that was never that tool's.

Impact: a file with a genuine owner but a long shared history reads as `UNSURE` rather than
`FIX`. Surfacing it for the operator is the safe direction.

## 2026-09-10 A candidate cap bounds detector 1

Context: the spec does not size detector 1's cost. Running it at `--stale-days 0` against
`ops-toolkit` took over eight minutes, because the reference grep is one pass per candidate.

Decision: `--max-candidates` (default 400), oldest first, with the overflow reported as its
own finding rather than dropped.

Why: the per-candidate grep IS the evidence a finding carries, so batching it away would
prove the set unreferenced without proving any member so. Bounding the set is the only
remaining lever.

Impact: a deliberately wide pass needs the flag raised, and the skill says so. At the default
180-day threshold the same repo yields zero findings in 8 seconds.

## 2026-09-10 The root test is named for the module, not the skill

Context: the test landed as `tests/test-repo-hygiene.sh`, matching the skill name.

Decision: renamed to `tests/test-repohygiene.sh`.

Why: `tests/test-kit-contract.sh` C4 resolves a module's test by the MODULE directory name
(`lib/repohygiene`), so the skill-named file read as a missing test. `lib/webcheck` and
`tests/test-webcheck.sh` are the same pairing under the same rule.

Impact: none beyond the filename.

## 2026-09-10 Detector 2 has no historical acceptance evidence

Context: the acceptance set names fourteen `_inbox` drops past 30 days, nine of them exact
duplicates.

Decision: verify detector 2 against a seeded fixture, and record the evidence gap in the
proof of done rather than claiming a reproduction.

Why: `_inbox/` is gitignored in the source repo, so those drops left no commit, no age, and
no content to hash. Nothing in the history can confirm or refute the count.

Impact: detector 2 ships with fixture coverage only for the duplicate-detection half. A live
run against a repo with a real staging pile would strengthen it.

Open questions: whether detector 2 should also read a staging dir's own `INGEST_LOG` when one
exists, which would give it a history to check against.
