# Sub-goal 05K: ledger-observatory moves into the kit (+ mega-durations)

**Merge policy:** auto
**Time budget:** 4-6 hours
**Proof:** OVER-TEST: full existing test suite green post-move (13 test files, byte-identical behavior) + relocation NC (old ops-toolkit paths gone, new kit paths resolve) + adapter-default NC (kit-internal sources now repo-relative, ops-toolkit-specific sources now opt-in-only) + the mega-durations fixture/NC/live-run from the original ask + COVERAGE-DELTA + rung-4 not required (data-analytics tool, no injection surface; over-test suffices)
**Design:** bearing (first tool to land under a NEW `tools/` top-level in the kit; sets precedent for the deferred harness-kit-consolidation program's other engine candidates)
**Repo:** dwarves-kit (hand-made worktree from `master`)
**Depends on:** none (touches a new `tools/` top-level, disjoint from `lib/`; can run in wave 1 alongside 03K/04)
Model: sonnet
**Branch:** `feat/observatory-to-kit` (dwarves-kit)
**PR base:** master

## Outcome

`dwarves-kit` gains `tools/ledger-observatory/` (the whole tool: `src/`, `tests/`, `docs/`, `skill/`, `pyproject.toml`, `uv.lock`, `README.md`, `tool.toml`), migrated verbatim from ops-toolkit, PLUS the `mega-durations` query (per-rid wall time + phase split from `kit_gates`, honest-zero) that was the original ask of SG-05. Rationale (Han, 2026-07-05): ledger-observatory reads `gate-ledger` data, and gate-ledger already lives in the kit; keeping the query engine on the other side of a repo boundary from its data source is the same split this mega already fixed for board/runner. ops-toolkit's copy is retired by the paired sub-goal 05R (after this merges).

## Quality bar

**Verbatim migration first, feature second, in the SAME PR (mirrors how 04 did migrate-render+add-queue in one sub-goal).** Do not redesign the tool while moving it. Two adapter classes behave differently after the move (read `src/ledger_observatory/config.py` first to confirm current defaults before changing them):

- **Kit-internal sources** (`DWARVES_KIT_LOG_DIR`, `DWARVES_KIT_LIB`, and the `kit_gates` telemetry the mega-durations query reads): defaults become relative to the tool's OWN repo root (it now lives inside the kit, so `~/.claude/dwarves-kit/lib`-style hardcoded install paths collapse to a same-repo relative path). This is a simplification, not new machinery.
- **ops-toolkit-specific sources** (`LEDGER_OBS_TIDE_DB`, `LEDGER_OBS_TGCLEANUP_DIR`, `LEDGER_OBS_LEARNED_MD`, `LEDGER_OBS_REPOS`, `CC_BACKLOG_STAGING`, `CC_BACKLOG_BACKLOG`): these are NOT kit-generic (tide/tg-cleanup/learned-ledger/cc-backlog are ops-toolkit tools). Their relative-path DEFAULTS (e.g. `_meta/learned-ledger.md`) silently resolve wrong once cwd is the kit, not ops-toolkit. Fix: flip these five to REQUIRE an explicit absolute path via env var (no default, or an empty/unset default that the existing "missing source is skipped, never fatal" contract already handles), ops-toolkit sets them when invoking. **Verify the kit's actual consumer-repo-path convention before inventing one**: `weekend-batch.sh`/`mega-merge.sh` use a `--repo-root`/`REPO_ROOT` flag + `_repo_root()` helper, NOT a `CONSUMER_ROOT` env var (that phrase in this mega's DECISIONS/04's goal-file was an unverified assumption from earlier in the session, flag it, do not propagate it further here).
- **Docs move WITH the code** (deploy/subject-of-doc-wins + the ops-toolkit `megagoal-lifecycle-rule` memory: a completed mega co-locates to its owner tool): `docs/megagoals/ledger-observatory/` (the tool's own build history, already inside it) AND ops-toolkit's `_meta/megagoals/harness-observatory/` (the mega that built the 5 lens sub-goals: kit-gates-lens, defect-correlation, deviation-rate, sessions-digest, memory-lens , all shipped, all living in this tool's `src/`) both land at `dwarves-kit/tools/ledger-observatory/docs/megagoals/{ledger-observatory,harness-observatory}/`. SPEC-126..137 keep their historical numbers (archival, not part of the kit's own SPEC sequence).
- **Skill discovery**: `skill/SKILL.md` moves with the tool. ops-toolkit currently has NO symlink/CLAUDE.md pointer wiring it in (checked: none found), so there is no consumer-side reference to fix, but confirm the kit's OWN skill-distribution mechanism (how kit skills reach consumer repos) picks it up the same way other kit skills do; if the kit has no precedent for a skill living under `tools/<x>/skill/` rather than the top-level `skills/`, note the gap in DECISIONS rather than inventing a new distribution mechanism.
- **`tool.toml`**: update `consumers` to name ops-toolkit (it becomes a consumer of the kit's copy, not the owner).

## How to close the loop

1. `git mv` (or copy + `git rm` if `git mv` can't cross the ops-toolkit checkout , this is two separate repos, so it is a copy-then-remove, not a single `git mv`; 05R does the removal side) the full `tools/ledger-observatory/` tree (minus `.venv/`, `.gitignore`-covered caches, `.claude/session-state/`) into `dwarves-kit/tools/ledger-observatory/`.
2. Fold in `_meta/megagoals/harness-observatory/` (ops-toolkit) as `docs/megagoals/harness-observatory/` alongside the tool's existing `docs/megagoals/ledger-observatory/`.
3. Fix the adapter defaults per the Quality bar split above; re-run the FULL existing suite (13 test files) and confirm byte-identical pass/fail behavior against a fixture set (the relocation NC).
4. `uv sync` fresh in the new location; confirm `ledger rebuild`/`ledger tables`/`ledger show` still work against a fixture ledger.
5. ADD the `mega-durations` query (this is the ORIGINAL SG-05 ask, unchanged in substance): read the ACTUAL `kit_gates` schema (`rid, gate, outcome, caught, reason, start_ts, end_ts`) from `adapters.py`, follow the `gate-yield` query as template (data-driven GROUP BY, no whitelist). Per-rid wall time = `max(end_ts) - min(start_ts)`; rows missing `end_ts` excluded AND counted ("N rows excluded"). Golden fixture with known durations; NC: fixture stripped of `end_ts` -> "0 rids with complete timestamps (N rows excluded)", exit 0. Live run over the real (now-relocated) ledgers, table + `n` pasted into proof-of-done , this is the first actual answer to Han's 2-3h question.
6. Update `tool.toml` (`consumers`) and the kit's own doc index for the new `tools/` tree (if the kit has a top-level tools index; if not, note the gap).

**Done =** full suite green (13 files, relocation NC) + adapter-default NC + mega-durations fixture+NC+live-table-with-n + proof-of-done.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. HANDOFF: next = 05R (ops-toolkit retire), which needs this PR's merged SHA + the exact new path to point its README banner at.
3. DECISIONS: the adapter-default split (kit-internal vs ops-toolkit-specific), the `--repo-root` vs `CONSUMER_ROOT` correction, the doc-tree co-location, any skill-distribution gap found.
4. Report IN the records, EXIT.

## Scope edges

**In:** the full tool migration (code+tests+docs+skill+specs), the two megagoal doc-tree relocations, the adapter-default fix, the `mega-durations` query.
**Out:** ops-toolkit's removal side (05R, separate sub-goal so the two repos' commits are independently reviewable), any NEW analytics beyond `mega-durations`, changing `kit_gates`' emission format.
**Not:** a Go/bash rewrite (Python+DuckDB is the deliberate, confirmed exception per ROADMAP Assumption 8), redesigning the CLI surface, inventing a `CONSUMER_ROOT` mechanism that doesn't already exist in the kit.

## Where to look

ops-toolkit `tools/ledger-observatory/` (source of the move, read `src/ledger_observatory/config.py` first), `_meta/megagoals/harness-observatory/` (the doc tree that moves alongside), dwarves-kit `lib/weekend-batch.sh`/`lib/mega-merge.sh` (the REAL `--repo-root` consumer-path convention), the repo-memory note `harness-machinery-in-the-kit.md`.

## PR body

- Outcome: `ledger-observatory` relocates into dwarves-kit as `tools/ledger-observatory/` (verbatim + adapter-default fix) and gains the `mega-durations` query.
- Verification: full existing suite green + relocation/adapter NCs + mega-durations fixture/NC/live-table.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes
