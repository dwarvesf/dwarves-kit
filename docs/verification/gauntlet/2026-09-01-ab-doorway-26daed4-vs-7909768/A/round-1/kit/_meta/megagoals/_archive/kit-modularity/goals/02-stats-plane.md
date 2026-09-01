# Sub-goal 02: stats-plane (ledger/stats event-sourcing split)

**Merge policy:** auto
**Time budget:** 3-5 hours of loop work
**Proof:** run-table, `stats <lens>` produces correct output over a fixture ledger (yield/durations at minimum); the `ledger/` append substrate has its own unit test (append + read round-trip); `KIT_LEDGER_DIR` config test (writer writes there, `stats` reads the SAME root); named NCs: (a) a derived view is NEVER persisted (a full temp-HOME filesystem-snapshot diff across two `stats` runs shows NO file written anywhere, not just under the ledger dir , advisor P5), (b) missing `KIT_LEDGER_DIR` = clean error not silent-wrong-path, (c) honest-zero on an empty ledger. COVERAGE-DELTA. Rung 3 (fresh-context recheck of the no-persisted-projection NC, it is the load-bearing event-sourcing guarantee).
**Design:** bearing (the ledger substrate interface + the write/read plane boundary is a real design; spec it per design note E)
**Depends on:** 01 (stats + the ledger substrate land as modules in the collapsed structure)
Model: opus
**Branch:** refactor/kitmod-02-stats-plane
**PR base:** master (rebased after 01)

## Outcome

The observability domain is an event-sourcing plane split. **Write plane:** a `ledger/` append substrate, one `append` + `read` + `KIT_LEDGER_DIR` location handling, that `gate-ledger`/`proof-ledger`/session writers call instead of each re-implementing row-append; append-only, the source of truth. **Read plane:** `ledger-observatory` renamed to `stats` (read-side never carries `-ledger`), a stateless projection engine (`stats gate-yield|durations|deviation-rate|correlation|anomalies|scorecard`) that recomputes from the ledger and persists NOTHING. `KIT_LEDGER_DIR` is essential-tier config (one root per consumer, via `--repo-root`/`_repo_root()`). RUN_REPORT stays the mega flow's closing verb, not a `stats` subcommand.

## Quality bar

A projection is never a second source of truth, `stats` writes nothing to the ledger; delete its output and re-run and you get the same answer from the log. The substrate is the ONE place row-append + location live (DRY over 3+ streams). Honest-zero everywhere. The rename is complete, no `ledger-observatory` name survives in a read-side context.

## How to close the loop

- Rename `ledger-observatory` → `stats` (module dir + entry + any internal identifiers + skill/docs refs); leave a within-repo pointer if needed for one release.
- Extract the `ledger/` append substrate: read how `gate-ledger.sh`/`proof-ledger.sh` currently append; design ONE interface (`ledger append <stream> ...`, `ledger read <stream>`), route both writers through it, keep back-compat.
- Wire `KIT_LEDGER_DIR` (align the existing `DWARVES_KIT_LOG_DIR`): substrate writes there, `stats` reads there; one root, per-consumer.
- Commit a small fixture ledger; run-table the `stats` lenses over it + the substrate unit test.
- NCs: (a) no-persisted-projection , run `stats <lens>` TWICE with NO intervening ledger write and diff a FULL temp-HOME filesystem snapshot before/after: NO file written ANYWHERE (advisor P5: a ledger-dir-scoped grep passes even if `stats` caches a derived view in `~/.cache` / a repo-local `.stats-cache/`, which violates the invariant outright , snapshot the whole tree, not just `$KIT_LEDGER_DIR`); (b) unset `KIT_LEDGER_DIR` → clean error; (c) empty ledger → honest-zero.
- STANDING anti-drift lint (advisor P6): the "persists nothing" guarantee needs to survive future contributors, not just this PR , add a durable check (a lint/CI grep asserting no persisted file appears under the `stats` module's output path, e.g. no `*.db`/`.stats-cache/`). A one-time NC does not stop a "convenient perf cache" slipping in six months later; the standing check does.

Kit-adopted: record build + review + recheck via `bash lib/gate-ledger.sh`.

**Done =** `stats <lens>` is correct over the fixture ledger, the `ledger/` substrate + `KIT_LEDGER_DIR` work with the writers, `stats` provably persists no derived ledger, and no read-side `ledger-observatory` name survives, captured in `docs/proof/kitmod-stats-plane.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-03 wraps `stats` (and the other modules) in a standalone entry; SG-05/06 reference the new names.
3. DECISIONS.md: record the `ledger` substrate interface contract + `KIT_LEDGER_DIR` default.
4. Report in records, EXIT.

## Scope edges

**In:** rename observatory→`stats`; the `ledger/` append substrate; `KIT_LEDGER_DIR`; routing gate/proof/session writers through the substrate.
**Out:** the module collapse (SG-01); command entries (SG-03); RUN_REPORT rendering (stays the mega flow's verb); new analytics lenses (none, port what exists).
**Not:** persisting any derived view; adding a new metrics-pipeline; renaming the WRITE-side `-ledger` streams (they correctly carry it); changing lens output formats beyond the rename.

## Where to look

kit's `ledger-observatory` (now under the collapsed structure), `gate-ledger.sh`/`proof-ledger.sh` append paths, `DWARVES_KIT_LOG_DIR` usage, design note E/E1/E2.

## PR body

Event-sourcing plane split: rename `ledger-observatory`→`stats` (read-side never carries `-ledger`) + a `ledger/` append substrate the gate/proof/session writers share + a configurable `KIT_LEDGER_DIR`. `stats` persists nothing (projections recompute from the log).

Verify: `stats` lenses over a fixture ledger + substrate unit test + no-persisted-projection NC + unset-DIR NC + honest-zero. Proof: `docs/proof/kitmod-stats-plane.md`. Stacked on #<SG-01>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes

**2026-07-05 CONDUCTOR ADDENDUM (scope expansion, transcribed from SG-01):** SG-01 met its crisp Done= (no-alias NC + suite-identical + resolution e2e + F-bar) but DEFERRED the physical fold of `tools/` into subsystem modules, because ledger-observatory folds naturally with THIS sub-goal's `stats` rename (avoids double-churn) and the other tools needed a home decision. So SG-02 now ALSO owns finishing the `tools/` fold so the lib-vs-tools split is fully retired (the mega terminus needs `tools/` empty):
- `ledger-observatory` → the `stats` module, folded into the collapsed subsystem structure (not left at `tools/`). This is already your rename; just land it as a real subsystem module, not under `tools/`.
- `session-observe` / `session-recall` / `session-intel` → fold into the existing `session/` subsystem (they are self-contained tools; watch their repo-root locators + `tool.toml` + any out-of-CI tests, SG-01 flagged these as the friction).
- `skill-curator` + `plugin-check` → genuinely single-purpose orphans with no obvious subsystem. DECIDE + JUSTIFY a home in your spec (Design: bearing): either bare orphan modules at `lib/` root (the adopt/explain/pitch/precedent precedent SG-01 set) or a subsystem. Whichever you pick, `tools/` must end EMPTY (or removed).
- ADD to your NC set: `tools/` directory is empty/gone after this PR (the split is retired), AND the full suite stays identical-or-better, AND every folded tool's call-sites + CI paths resolve (same LIB_ROOT discipline + `.github/workflows` audit SG-01 used).
This does NOT change your primary deliverable (the event-sourcing rename + ledger substrate + KIT_LEDGER_DIR). It absorbs the structural remainder that SG-01 correctly punted here.
