# Mega-goal: ledger-observatory

**Destination:** The scattered ledgers (kit gate/proof/telemetry, the learning ledger, tide's state, tg-cleanup snapshots, plus the planned debt & token ledgers) become one AGENT-CALLABLE observability surface: an on-demand, queryable + renderable lens the Claude Code agent drives (or a shareable web Artifact), that GENERATES improvement backlog rows , the feedback loop that stops the ledgers being write-only. NOT a human TUI (the operator never opens an app; everything goes through the agent or an Artifact). DuckDB is a read-only LENS over the ledger files, never a second source of truth: the files stay canonical, delete the db and re-materialize.
**Quality bar:** Read-only over the ledgers, always , the lens never writes back to a ledger, and the tool never moves or mutates the data it observes (icy-ops/asus-mesh/growatt-pull read-only-by-contract shape). Files stay canonical: the DuckDB db is derivable + disposable (the delete-and-rematerialize property is a named proof). Reuse , do NOT rebuild lane-telemetry for the kit-side read, do NOT invent a second quiz/marker/board convention. The feedback loop PROPOSES rows into the cockpit, never auto-files noise , a false-positive negative control is load-bearing (04). Over-test 02 (cross-format read correctness) + 04 (threshold correctness).
**Work repo:** `ops-toolkit` (a tool `tools/ledger-observatory/` + a render skill; SG-01's schema doc references the dwarves-kit `~/.local/state/dwarves-kit/logs/` marker convention but the doc lands here).
**Stacking tool:** gh (stacked; linear 01<-02<-03<-04<-05)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final (the final PR , 05 docs , is Han's click; 01-04 auto-merge as gates pass)
**Run mode:** delegate (5 sub-goals > 4; the `/goal` loop is a THIN CONDUCTOR that delegates each sub-goal to a fresh headless `claude -p` and absorbs one terse line , per the plan-for-mega-goal run-mode option)
**Terminus:** build + merge + the held final PR.
**Started:** 2026-07-03

## Provenance

`ops-toolkit/research/2026-07-03-understanding-bottleneck-sdlc.md` , the "Addendum (2026-07-03): context hygiene under /goal + the agent-driven ledger observatory" section IS the design source. The operator reframe there is BINDING: the custom Go/bubbletea TUI is DELETED; the design collapses to an agent-callable read-only CLI (the icy-ops/asus-mesh/growatt-pull shape) + a render skill + a feedback loop into `work-intake`. This mega-goal EXECUTES that reframe; it does not re-decide it. Build in a FRESH session (the source session hit the 873k/87% context ceiling this observatory is partly a response to).

## Sub-goals

- [x] 01-ledger-schema , merged b4ff175e , formalize the kit `ISO8601 | VERB | k=v` append-only marker (`~/.local/state/dwarves-kit/logs/`) as THE canonical ledger event schema; confirm the planned debt (understanding-gate SG-02) + token (kit-face SG-03) ledgers conform; specify the 3 outlier adapter contracts (learned-ledger.md=markdown, tide state.sqlite=sqlite, tg-cleanup *.json=json) , `auto` , PR #672
- [x] 02-etl-cli , the `ledger` tool: DuckDB views over the ledgers IN PLACE (one pipe-log reader drains the ~10 kit stores + 3 native adapters; DuckDB reads sqlite + json natively) + an agent-callable `ledger query` / `ledger show <name>` CLI returning structured output (json/table). Reuse `lane-telemetry` for the kit read. Harness = Python+uv. SUBSTANTIAL , OVER-TEST , `auto` , PR #673 , merged e6ff875b
- [x] 03-render-skill , a skill firing on "show me the ledger state / my debt / telemetry / token cost" that queries via 02 and renders EITHER in-terminal (bot-reply-formatting: tables/bars) OR as a web Artifact (share/review) , `auto` , PR #674 , merged 7f8f7e2c
- [x] 04-feedback-loop , anomaly detection over the ledger state (unpaid-debt count, cost spike vs median, misfire rate) that PROPOSES backlog rows via `work-intake` into the cockpit boards , the improvement loop that stops the ledgers being write-only. SUBSTANTIAL , OVER-TEST , `auto` , PR #675 , merged a0806ff3
- [x] 05-docs-wiring , tool README/proof-of-done (ops-tool-shape/ops-tool-docs shape) + the no-orphan wiring check (the render skill fires on its triggers; the CLI is actually invoked; work-intake actually receives a proposed row) , `auto` , PR #676 , merged 883801e8

## Dependencies

- 02 depends on 01 (the schema + adapter contracts define what the views read).
- 03 depends on 02 (renders the CLI's structured output).
- 04 depends on 02 (the queryable state to detect anomalies over) + 03 (surfaces the proposed rows).
- 05 depends on ALL (docs-last: reflect the final wired state, per the kit-face lesson).
- Execution order: 01 -> 02 -> 03 -> 04 -> 05 (mostly linear; 01 is independent). Stack: 01 off `main`; 02 bases 01; 03 bases 02; 04 bases 03; 05 bases 04, LAST.

## The DuckDB-as-lens principle (BINDING)

```
canonical ledger FILES                 DuckDB (derivable, disposable)
  kit corpus (~10 + 2 planned):          `ledger` CLI reads views ->
   ISO8601 | VERB | k=v  ─── pipe-log ──► structured out (json/table)
   under ~/.local/state/dwarves-kit/logs   ▲
  learned-ledger.md (markdown) ── adapter ─┤   render skill:
  tide state.sqlite (sqlite)  ── native ───┤    - terminal (bot-reply-formatting)
  tg-cleanup *.json (json)    ── native ───┘    - web Artifact (share/review)
                                                    │
                                                    ▼  FEEDBACK
                                    anomalies -> work-intake -> board rows
```

- The FILES are canonical. The db is a lens: `ledger rebuild` (or first-run) re-materializes it from the files; deleting it loses nothing. No sync, no write-back, no second source of truth.
- One pipe-log reader drains the whole schema-uniform kit corpus (SG-01 confirms debt + token conform). Only 3 bespoke outliers need small adapters.
- The kit-side read REUSES `lane-telemetry` (do not rebuild it). ETL = a handful of DuckDB views + a refresh, NOT a custom engine.

## Assumptions (2026-07-03; the research Addendum resolved the shape; per-sub-goal /spec re-frames)

- **DuckDB = read-only LENS; the files stay canonical** , no sync, no second source of truth, delete-and-rematerialize is a property (proven in 02).
- **Consumer is the AGENT on-demand, NOT a human TUI** , the custom Go/bubbletea TUI is DELETED per the operator. Same shape as icy-ops/asus-mesh/growatt-pull: a read-only CLI the agent drives + a skill.
- **Phase 1 works over EXISTING ledgers** (kit corpus + learned-ledger + tide + tg-cleanup); the debt (understanding-gate SG-02) + token (kit-face SG-03) ledgers CONFORM on arrival , SG-01 confirms the schema, it does not wait for them to exist.
- **Reuse `lane-telemetry` for the kit read** , do not re-implement the pipe-log parse.
- **Feedback wires to `work-intake` + the cockpit boards** (`_meta/boards.txt`) , anomalies PROPOSE rows, never auto-file.
- **Over-test 02 + 04** , 02 owes cross-format read correctness + a cross-ledger JOIN + the delete-and-rematerialize property; 04 owes threshold correctness + a false-positive negative control. Both carry a COVERAGE-DELTA row in the proof.
- **Cross-cutting WIRING GATE (kit-hardening c6fbd99 lesson):** every artifact proves a live invocation path; TIER-4 runs a no-orphan check (a defined-but-never-dispatched skill/CLI/feedback path = blocking).

## Open forks (surface, non-blocking; /spec defaults)

1. **Harness language (02):** Python+uv default (Han's stack: DuckDB SQL for the transform always; Python uv harness for ad-hoc non-daemon). Reconsider Go ONLY if it hardens into a scheduled daemon. /spec defaults to Python+uv.
2. **Refresh trigger (02/03):** on-demand (the agent triggers a rebuild when it queries) vs scheduled launchd. Default ON-DEMAND (minimum-infra; no new daemon in Phase 1).
3. **Anomaly thresholds (04):** the exact unpaid-debt / cost-spike / misfire cutoffs. /spec PINS these after real ledger data has accrued; scaffold with defensible defaults + one flag to tune.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo tieubao/ops-toolkit --json state,reviewDecision,statusCheckRollup
    done
