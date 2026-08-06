# Sub-goal 05: Cross-repo deterministic sweeps

**Time budget:** ~4-6 hours loop work (new tool, 6 sweeps)
**Depends on:** none
**Branch:** feat/cc-elevation-05-sweeps
**PR base:** main

## Outcome

A new `tools/repo-sweep/` provides a read-only harness that walks my repos under `~/workspace/tieubao/` and runs six deterministic sweeps, emitting one consolidated digest: (1) stale branches + abandoned `.claude/worktrees/`, (2) dependency + advisory audit (npm/pip/uv + the patch-exploit advisory check) on deployed repos, (3) doc-drift (CLAUDE.md/README claims vs reality), (4) memory hygiene (`.claude/memory/MEMORY.md` refs to files/flags that no longer exist), (5) proof-of-done gaps (`tools/` entries missing `docs/proof-of-done.md`), (6) MANIFEST / tool.toml drift.

## Quality bar

Read-only and safe: the harness never writes to any swept repo, it only emits a digest. Each sweep is a small independent module so one failing sweep does not sink the run. Honest output: a sweep that cannot run says so, it does not silently report "clean".

## How to close the loop

- `repo-sweep run` produces a digest with one section per sweep across the repos.
- Each sweep proven on at least one real or seeded finding: seed an abandoned worktree and a memory ref to a deleted file in a fixture repo, confirm the digest flags both; confirm a tool missing proof-of-done is listed.
- Assert read-only: run against a fixture repo, `git status` in it is unchanged after the sweep (safety negative control).
- Lane via lane-classify; owes `tools/repo-sweep/docs/proof-of-done.md`.

**Done =** `tools/repo-sweep/` runs all six read-only sweeps across the repos and emits one digest, each sweep proven on a seeded finding, the harness provably writes nothing to swept repos, with proof-of-done + runbook, on PR #NN with green CI.

## Scope edges

**In:** `tools/repo-sweep/` (harness + 6 sweep modules + digest writer + fixtures + tests + proof).
**Out:** the reasoning sweeps (backlog-triage, learning-flush) which are 06; scheduling it (a later launchd/Routine wiring, runbook only); posting to Discord/Notion (open knob, v1 writes to stdout/file).
**Not:** any write to a swept repo; auto-fixing findings; a daemon.

## Where to look

The repo list under `~/workspace/tieubao/`, the patch-exploit skill for the advisory check, `MANIFEST.md` + the `tool.toml` schema (`_meta/SCHEMAS.md`), the proof-of-done gate convention, `tools/tide/` for tool shape.

## PR body

Outcome: a read-only `tools/repo-sweep/` that runs six cross-repo health sweeps (stale-branch, dep/advisory audit, doc-drift, memory hygiene, proof-of-done gaps, manifest drift) into one digest.
Verify: `repo-sweep run` flags seeded findings per sweep; swept repos' `git status` unchanged (read-only proven).
Roadmap: `_meta/megagoals/cc-elevation/ROADMAP.md` (sub-goal 05).

## Notes
