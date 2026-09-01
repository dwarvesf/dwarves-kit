# NOTES , ledger-observatory

## Active blockers

- [none] No ADR gate-zero: the research Addendum (2026-07-03) IS the decision (the Go/bubbletea TUI is DELETED; collapse to an agent-callable read-only CLI + skill + feedback loop). Soft sequencing (non-blocking): the research prefers building AFTER the debt (understanding-gate SG-02) + token (kit-face SG-03) ledgers exist, but per the BINDING assumption Phase 1 runs over the EXISTING ledgers (kit corpus + learned-ledger + tide + tg-cleanup) and SG-01 CONFIRMS the debt/token schema conforms on arrival rather than waiting. Build in a FRESH session (the source session hit the 873k/87% ceiling).

## Proposed additions

- 2026-07-03: the ledger-event schema (SG-01) is the SAME additive `ISO8601 | VERB | k=v` marker convention already shared by kit-face SG-03 (TOKENS) + understanding-gate SG-02 (debt ledger). SG-01 formalizes it as THE canonical schema; reuse it, do NOT invent a third/fourth marker convention (mirrors understanding-gate's same note).
- 2026-07-03: micro-worlds rendering (an `interactive-concept-board`-style inhabitable view of the ledger state) is a possible FUTURE 03 enhancement; deferred , Phase 1 renders terminal (bot-reply-formatting) + web Artifact only. Surface to the advisor over-suggest at TIER-4.
- 2026-07-03: the feedback loop (SG-04) gives the kit ledgers a CONSUMER, the same "reverse the write-only drop" move understanding-gate made for impl-notes (ID-234). If a proposed anomaly row overlaps understanding-gate's debt-ledger paydown, dedup at work-intake rather than double-filing.
- 2026-07-04 (TIER-4 findings, routed for follow-up work-intake; out of SG-05's code scope):
  - Single column-spec (or a parity assert) to kill the `adapters.KIT_COLUMNS` / `materialize._KIT_DDL` schema double-definition silent-drift.
  - A field-count assert in `read_kit()` so lane-telemetry `_rows()` drift fails loud instead of truncate-padding with empty strings.
  - `ledger anomalies` `--repo` group-by + data-derived `home` (fix the global-sum vs. single-repo-stage attribution seam); surface the unattributed `repo="?"` bucket (~44% of `kit_runs` as measured 2026-07-04) as a caveat in the tool itself, not just the docs.
  - A `ledger doctor` / `--verbose` per-source reachability report ("tide: not found, skipped" vs. "found, 0 rows"), so a silent source-skip stops reading identically to a genuinely-empty source.
  - Pipe `ledger anomalies` output through the SG-03 `render.py` formatters (reuse, one render story, instead of `anomalies`' own ad-hoc table print).
  - Real end-to-end `uv run ledger render` CLI tests (currently grep/unit-level only) + a `tests/test-all.sh` wrapper that rebuilds and runs all 5 suites in one call.
  - A staleness-aware re-fire for an already-staged-but-worsening anomaly (today's title-dedup is deliberately count-free, so a worsening debt count never re-proposes).
  - Consolidate the duplicated ops-toolkit root path (`anomalies.py` resolves `~/workspace/<owner>/ops-toolkit` itself; move to `config.py`); wire or drop the dead `TERMINAL_CELL_BUDGET` if it exists unused in `render.py`.
  - Privacy-surface tightening (security lens): drop `tide_moves.ai_response_json` (raw AI response bodies) + `tg_dialogs.access_hash` (Telegram peer hashes) from the materialized lens columns unless a detector needs them (as of 2026-07-04, neither does); narrows what any local agent can read via `ledger query` from the gitignored cache db.

## Event log

2026-07-04 · closed · ledger-observatory built , 4 merged (#672-#675), final docs PR #676 HELD for Han; TIER-4 clean (integration/security/architecture/test-coverage/advisor, 0 blockers). Conductor switched run-mode `claude -p` -> in-harness worktree subagents after SG-02's first worker was killed ~15m in (recovered from git; OPERATE kill-resilience). SG-02 review caught+fixed HIGH-1 (read-only PRAGMA bypass). Over-claim NC + no-orphan sweep green. RUN_REPORT.md written to this dir. On #676 merge: flip box 05 + co-locate the folder per the lifecycle rule.

2026-07-03 HH:MM · scaffold · ledger-observatory mega-goal created from the research note's "Addendum , the agent-driven ledger observatory" (the operator reframe: TUI DELETED, collapse to a read-only agent-callable CLI + render skill + work-intake feedback loop). 5 sub-goals, gh-stacked (linear 01<-02<-03<-04<-05) + auto-bottom-up + gated-final, RUN MODE = delegate (thin-conductor per the plan-for-mega-goal run-mode option). Work repo = ops-toolkit (tool `tools/ledger-observatory/` + a render skill; SG-01's schema doc references the dwarves-kit marker convention). No ADR gate-zero (the Addendum is the decision); Phase 1 over existing ledgers, debt/token conform on arrival. Over-test 02 (cross-format read + JOIN + delete-and-rematerialize) + 04 (thresholds + false-positive NC). 3 forks surfaced non-blocking (harness language, refresh trigger, anomaly thresholds) for /spec.
