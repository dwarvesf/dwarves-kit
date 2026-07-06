# SPEC-182: stats-plane (ledger/stats event-sourcing split + tools/ fold)

Status: DRAFT
Lane: full
Type: spec-feature

## Problem / Context

kit-modularity SG-02. The observability domain is a write/read plane that is currently
tangled: `ledger-observatory` (a read-side DuckDB projection tool) still carries a `-ledger`
name and, worse, PERSISTS a derived DuckDB cache (`~/.cache/ledger-observatory/ledger.duckdb`),
which makes a projection a second source of truth , the exact drift-bug class the
event-sourcing invariant (DECISIONS.md E) exists to forbid. Meanwhile row-append logic is
re-implemented in `gate-ledger.sh`, `proof-ledger.sh`, and the log-dir resolver, with no single
substrate. And SG-01 deferred the physical `tools/` -> `lib/` fold here (to avoid double-churn
against this rename), so `tools/` still holds six modules and the lib-vs-tools split is not yet
retired.

This spec does the event-sourcing plane split AND finishes the `tools/` fold.

## Bearing design decisions

**D1. Write plane = a `ledger/` append substrate (`lib/ledger/ledger.sh`).** ONE place where
row-append + root-location live. Interface (sourced by writers, also a standalone CLI):

- `ledger append <stream> <text...>` , append ONE line to `<root>/<stream>` (newlines
  collapsed to spaces, append-only, parent dir auto-created). `<stream>` is a root-relative
  path (`runs/<rid>.log`, `proof-overrides.log`, ...).
- `ledger read <stream>` , print `<root>/<stream>` (honest-empty if absent, never a crash).
- `ledger root` , print the resolved root.

`gate-ledger.sh` and `proof-ledger.sh` source this and call `ledger_append`/`ledger_read`
instead of re-implementing `printf >> "$file"` + `mkdir -p`. Back-compat: identical bytes to
identical files.

**D2. `KIT_LEDGER_DIR` is the one root, aligning the legacy `DWARVES_KIT_LOG_DIR`.** ONE
resolver (`lib/telemetry/kit-log-dir.sh`, extended) with precedence:
`KIT_LEDGER_DIR` (canonical, wins) -> `DWARVES_KIT_LOG_DIR` (back-compat alias) -> XDG default
(`${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`). A **set-but-empty** `KIT_LEDGER_DIR`
is a FATAL clean error (the "silent-wrong-path" guard: an empty root would append to a relative
`runs/...` path). Both planes (substrate writer + `stats` reader) resolve through the same
precedence, so the writer writes and `stats` reads the SAME root. Tests point `KIT_LEDGER_DIR`
at mktemp.

**D3. Read plane = `stats`, a PURE stateless projection (renamed from `ledger-observatory`).**
The persistent DuckDB cache is REMOVED. Every command materializes an in-memory
(`:memory:`) DuckDB from the canonical sources, runs the query, and discards the connection.
Delete `stats`' output (there is none) and re-run: same answer from the log. This is the
event-sourcing invariant (E) made literal and is REQUIRED by the load-bearing no-persist NC,
not scope creep. Lens outputs are unchanged; only the persistence model changes. `rebuild`
becomes an in-memory diagnostic that reports row counts and writes nothing. The read-side
identifier `observatory` is retired; env prefix `LEDGER_OBS_*`/`LEDGER_OBSERVATORY_DB` ->
`STATS_*`. The bare word "ledger" is KEPT wherever it names the WRITE plane or a source ledger
(`ledger-event-schema`, `learned-ledger`, `gate-ledger`, the new substrate) , per the invariant
"renaming the write-side `-ledger` streams is out of scope."

**D4. `tools/` fold homes (tools/ ends EMPTY):**
- `ledger-observatory` -> `lib/stats/` (real subsystem module, the D3 rename).
- `session-observe`/`session-recall`/`session-intel` -> `lib/session/{observe,recall,intel}/`
  (they share the session-transcript domain + the `lib/session/parse_transcript.py` parser SG-01
  already extracted). Their `_repo_root()` walk-up-to-`lib/session` locators keep resolving after
  the move (verified).
- `skill-curator`, `plugin-check` -> BARE orphan module dirs at `lib/` root (`lib/skill-curator/`,
  `lib/plugin-check/`). JUSTIFICATION: each is a single cohesive tool with no sibling that would
  form a subsystem (unlike the session trio). Forcing an artificial `meta/` subsystem is premature
  abstraction (kit code-quality rule). This extends SG-01's "orphan reals stay bare at lib/ root"
  precedent from bare scripts to bare self-contained module dirs; the load-bearing NC is `-type l`
  (no symlink shims), which bare real dirs satisfy. If a third such tool appears, THEN group.

**D5. STANDING anti-drift lint.** A durable check (`tests/test-stats-no-persist.sh` + a CI step)
asserts no persisted derived-view file (`*.db`, `*.duckdb`, `.stats-cache/`) can appear under the
`stats` module output path across a lens run , so a future "perf cache" cannot silently
re-persist a projection.

## Verification

Run from the worktree root.

1. **stats lenses over a fixture ledger** , `KIT_LEDGER_DIR=<fixture> uv run --project lib/stats
   stats gate-yield` (+ mega-durations) produce correct rows.
2. **substrate round-trip** , `ledger append <stream> "x" && ledger read <stream>` returns the row;
   `ledger root` prints the resolved root. (`tests/test-ledger-substrate.sh`)
3. **KIT_LEDGER_DIR shared-root** , a writer (`gate-ledger.sh record`) writes under
   `$KIT_LEDGER_DIR`, and `stats` reads the same root.
4. **NC no-persisted-projection (LOAD-BEARING)** , run `stats <lens>` TWICE with no intervening
   ledger write; a FULL temp-HOME filesystem snapshot before/after shows NO file created ANYWHERE
   (not just under the ledger dir). `tests/test-stats-no-persist.sh`. Fresh-context recheck.
5. **NC unset/empty KIT_LEDGER_DIR** , `KIT_LEDGER_DIR="" ledger append ...` -> clean fatal error,
   not a silent relative-path write.
6. **NC honest-zero** , empty ledger -> zeros, not crash/garbage.
7. **NC tools/-empty** , after the fold, `/usr/bin/find tools -type f` is empty (or tools/ removed).
8. **NC suite-identical-or-better** , the CI-enumerated suite is identical-or-better vs the recorded
   baseline (38 pass / 1 pre-existing local-only env fail in `test-board.sh` NC-e).
9. **COVERAGE-DELTA** , every moved call-site + every renamed ref resolves; `.github/workflows`
   paths audited.

## After state

- `lib/ledger/ledger.sh` substrate exists; `gate-ledger.sh`/`proof-ledger.sh` route through it.
- `KIT_LEDGER_DIR` honored by resolver + `stats`; `DWARVES_KIT_LOG_DIR` still works.
- `lib/stats/` (was `tools/ledger-observatory/`); no persistent DuckDB cache; no read-side
  `observatory` identifier survives.
- `lib/session/{observe,recall,intel}/`, `lib/skill-curator/`, `lib/plugin-check/` exist;
  `tools/` empty/removed.
- New tests wired into `.github/workflows/test.yml`.

## Test plan

| Category | Case | Where |
|---|---|---|
| substrate | append+read+root round-trip; empty-KIT_LEDGER_DIR fatal | test-ledger-substrate.sh |
| projection | stats lens over fixture; honest-zero on empty | test-stats-lens.sh (or port existing tool tests) |
| no-persist | full temp-HOME snapshot diff across 2 runs | test-stats-no-persist.sh |
| shared-root | gate-ledger writes, stats reads same root | test-ledger-substrate.sh |
| structure | tools/ empty; -type l empty at lib root | verified in proof |
| regression | full CI suite identical-or-better | run-suite baseline vs after |
