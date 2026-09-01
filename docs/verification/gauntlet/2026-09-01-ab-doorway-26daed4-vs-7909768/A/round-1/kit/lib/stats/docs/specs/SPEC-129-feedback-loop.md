# Spec: the feedback loop (anomaly -> proposed backlog row, propose not auto-file)
Generated: 2026-07-04
Status: VALIDATED
Lane: full (lane-classify returned full)
Depends-on: SPEC-127 (the `ledger` CLI, shipped, PR #673, merged e6ff875b) + SPEC-128 (the render skill, shipped, PR #674, merged 7f8f7e2c)

## Problem

SG-02 shipped a read-only DuckDB lens + agent-callable `ledger` CLI; SG-03 renders it. But the
ledgers are still WRITE-ONLY: anomalies accumulate (understanding debt piles up, a token-cost
spike passes unnoticed, gate/proof misfires climb) and nothing turns them into action. The loop
that closes this , ledgers -> lens -> anomaly -> proposed improvement row -> operator gate ->
improvement , does not exist. This sub-goal builds the detection + proposal half of that loop.

The load-bearing constraint (ROADMAP Quality bar + the goal file): it must PROPOSE, never
auto-file. A detector that spams the board with garbage is worse than no loop at all. So the
noise-floor FALSE-POSITIVE negative control is the spec's centre of gravity: a normal ledger
state must propose NOTHING.

## Solution

### Approaches considered

1. **A `ledger anomalies` subcommand: pure detection over the SG-02 lens (one data path) +
   an explicit `--propose` that STAGES rows into the EXISTING cc-backlog staging buffer
   (CHOSEN).** A new `anomalies.py` module holds defensible-default thresholds (one `--threshold
   KEY=VALUE` flag to tune, resolving open-fork 3), three detectors that each read ONLY via
   `materialize.query`/`materialize.show` (never a re-query of a raw ledger), and a stager that
   appends a `## [staged]` block to `_meta/backlog-staging.md` in the EXACT format the existing
   `tools/cc-backlog/` tool writes and its `add-backlog` command consumes. Detection is read-only
   and separable (default: report only); `--propose` is the one act that writes, and it writes
   ONLY the gitignored staging buffer, never a board `BACKLOG.md`, never a ledger.
2. **Invent a new proposal/staging convention (e.g. write directly into a board's `queued`
   section as a "proposed" row).** Rejected: the ROADMAP Quality bar says "do NOT invent a second
   quiz/marker/board convention"; the goal file says REUSE the candidate-staging mechanism. The
   cc-backlog staging buffer + `add-backlog` human-gate already IS the propose-then-review path;
   writing a second one fragments the operator's review surface and risks an auto-file.
   - **On the goal file's "via `work-intake`" wording:** the goal file (Outcome + "Where to look")
     names the `work-intake` SKILL as the propose-into-cockpit contract. `work-intake` is a
     CHAT-driven skill whose Step 3 is literally "Write the rows into `_meta/BACKLOG.md`" , it
     writes the BOARD directly, with no file-level staging/gate primitive of its own (its "human
     gate" is Han choosing to invoke it in a session, not a review buffer). Invoking it from an
     AUTOMATED detector would therefore AUTO-FILE the board, violating the propose-not-autofile
     contract. The repo's actual propose-then-human-gate primitive is `cc-backlog`'s staging
     buffer + the `add-backlog` command (the worker brief also directs: reuse the existing
     candidate-staging mechanism, do not invent a second board-write convention). So this spec
     honors the goal file's INTENT (propose into the cockpit, operator gates) via the correct
     primitive, and treats "via work-intake" as naming the propose-INTO-cockpit contract, not a
     literal call into the board-writing skill. See DEC-001.
3. **Auto-file the row straight onto the board when an anomaly fires.** Rejected outright: this
   is the exact anti-pattern the goal file's Scope edges forbid ("Not: auto-filing rows") and the
   false-positive NC exists to prevent. The board is the operator's source of truth; a tool never
   writes it.
4. **Detect by re-reading the raw ledger files (a second data path).** Rejected: the ROADMAP's
   DuckDB-as-lens principle + the goal file ("Detection reads via 02, one data path, never a
   re-query") mandate the single read path. Detectors query the SG-02 lens only.

### Chosen: approach 1.

### Extensibility & boundaries

- A fourth detector later = one more entry in the `DETECTORS` list in `anomalies.py`, taking the
  same `thresholds` dict and returning an `Anomaly | None`. No change to the stager, the CLI, or
  the dedup path.
- When the dedicated understanding-DEBT ledger (kit understanding-gate, future) and TOKEN ledger
  (kit-face, future) materialize as their OWN lens tables, a detector just points its SQL at the
  new table; the threshold + proposal machinery is unchanged. Until then the detectors read the
  debt/cost/misfire signals ALREADY present in the SG-02 lens (see Design, "signal mapping").

## Design

Design-bearing (a new component: the `anomalies.py` detector+stager module; a data-flow contract
, PROPOSE-not-autofile , that the whole loop's safety rests on; and it resolves open-fork 3, the
anomaly thresholds). This block is the design record (ADR-0031 §1).

### Signal mapping (what "debt / cost-spike / misfire" ARE in the SG-02 lens today)

The goal file names three example anomalies. Each maps to a real, materialized SG-02 table/column
(one data path), with a forward path to the dedicated ledgers when they arrive:

| Detector | Anomaly (goal file) | SG-02 lens signal read TODAY | Forward path |
|---|---|---|---|
| `debt` | unpaid-debt count over threshold | `SUM(kit_runs.gates_ovr)` , a gate OVERRIDE is a consciously-WAVED gate = unpaid understanding debt | point at the dedicated debt-ledger table when it materializes |
| `cost_spike` | token-cost spike vs rolling median | `tide_tier_b_calls.cost_usd` ordered series , the real per-call model-cost ledger in the lens | point at the kit token-ledger table when it materializes |
| `misfire` | gate/proof misfire-rate climbing | `kit_runs.lane_misroute`/`type_misroute` , the kit's own routing-misfire counters | add a rate-history store for true trend (see COVERAGE-DELTA uncovered) |

The `debt` detector reads overrides as the debt proxy AVAILABLE in the lens; this is a delta from
the goal file's "debt ledger" wording (the dedicated ledger is not yet a lens table) and is logged
in impl-notes. It is honest and forward-compatible: the machinery does not change when the ledger
arrives.

### Thresholds (open-fork 3, RESOLVED with defensible defaults + one tune flag)

Defaults live in `anomalies.DEFAULTS`; every one is overridable by the single repeatable
`--threshold KEY=VALUE` flag (the "one flag to tune"). They are SCAFFOLDS, deliberately loose-ish,
to be tightened after real ledger data accrues (open-fork 3: "/spec pins after real data"):

| Key | Default | Rationale (defensible scaffold) |
|---|---|---|
| `debt_max` | `5` | a handful of waved gates is normal; >5 accumulated overrides = debt piling faster than paid |
| `cost_window` | `5` | rolling-median window AND the min-sample floor: fewer than 5 prior calls => no stable median => no fire (false-positive guard) |
| `cost_multiplier` | `3.0` | latest cost > 3x the recent median is a defensible "spike", not routine variance |
| `misfire_rate_max` | `0.25` | >25% of runs misrouting is a real signal, not noise |
| `misfire_min_runs` | `4` | below 4 runs a rate is meaningless (1-of-1 misroute = 100% false positive); the min-sample floor |

The two min-sample floors (`cost_window`, `misfire_min_runs`) are the load-bearing
false-positive guards: they are WHY a noise-floor / thin-data state proposes nothing.

### The propose-not-autofile contract (reuses the cc-backlog staging path)

```mermaid
flowchart LR
    L[canonical ledger FILES] --> M[SG-02 DuckDB lens]
    M -->|materialize.query / show, the ONE read path| D[anomalies.detect thresholds]
    D -->|no detector fires: noise floor| Z[propose NOTHING , board untouched]
    D -->|a detector fires| A[Anomaly: stable title + Intent/Approach/Tags/Home]
    A -->|--propose only| S[append '## [staged]' block to _meta/backlog-staging.md]
    S -->|dedup by normalized title vs board + staging| S
    S --> H[operator runs 'add-backlog' , the HUMAN gate]
    H -->|accept| B[BACKLOG.md row , written by add-backlog, NOT by this tool]
    H -->|reject| R[mark '## [rejected]', never filed]
```

- The tool's ONLY write is an append to the gitignored staging buffer (`_meta/backlog-staging.md`,
  overridable via `CC_BACKLOG_STAGING`). It NEVER writes a board `BACKLOG.md` (that is
  `add-backlog`'s job, gated on the human). It NEVER mutates a ledger.
- The staged block is byte-format-identical to what `tools/cc-backlog/bin/cc-backlog` writes and
  what `tools/cc-backlog/bin/add-backlog` parses:
  `## [staged] <title>` + `- Intent:` + `- Approach:` + `- Tags: #u-* #f-*` + `- Home:` +
  `- Source:` + trailing blank line. So the operator reviews anomaly proposals through the SAME
  `add-backlog` command they already use , no second review surface.
- **Dedup / idempotency:** reuse cc-backlog's normalization (lowercase alphanumeric words) against
  BOTH the board's Item titles AND already-staged titles. Detector titles are STABLE and
  count-free (live numbers live in Intent/Approach, which do not affect dedup), so re-running
  `--propose` stages nothing new, and an anomaly already promoted (on the board) or rejected
  (still title-visible in staging) never re-stages.
- Stable titles: `Feedback: unpaid understanding-debt over threshold` /
  `Feedback: token-cost spike vs rolling median` / `Feedback: gate/proof misfire-rate over threshold`.

### ADR link(s)

No new ADR: additive component inside the already-decided architecture (ROADMAP DuckDB-as-lens +
agent-callable CLI + feedback-to-work-intake). The one design choice with any weight , stage into
the EXISTING cc-backlog buffer rather than a new convention , is the ROADMAP's own "reuse, do not
invent a second board convention" made concrete; it is reversible (delete the `anomalies` command).

### Boundaries & failure modes

In bounds: read the lens, decide fired/not-fired, append a proposal to the staging buffer. Out of
bounds: writing any board, promoting a row, mutating any ledger, a second data path.

## Technical Design

### Interfaces (I/O contract)

- **Consumes:** `materialize.query(sql)` and `materialize.show(name)` (SG-02, unchanged), the ONLY
  read path. `anomalies.py` imports `materialize`; it does NOT open DuckDB itself or read a raw
  ledger file.
- **`anomalies.DEFAULTS: dict[str,float]`** , the five threshold keys above.
- **`anomalies.Anomaly`** (dataclass): `key`, `title` (stable, count-free), `intent`, `approach`,
  `tags` (e.g. `#u-mid #f-mid`), `home` (`ops-toolkit`), `metric` (the observed value, for report).
- **`anomalies.detect(thresholds: dict) -> list[Anomaly]`** , runs the three detectors over the
  lens; returns the fired ones. Pure read; writes nothing.
- **`anomalies.stage_proposals(anomalies, staging_path, backlog_path) -> tuple[list, list]`** ,
  returns `(staged, skipped_as_duplicate)`. Appends a `## [staged]` block per non-duplicate
  anomaly to `staging_path`. Reads `backlog_path` + `staging_path` for the dedup title set. Never
  writes `backlog_path`.
- **`anomalies.render_block(a: Anomaly, date: str) -> str`** , the cc-backlog-format block.
- **Invariants:** `detect` performs zero writes. `stage_proposals` writes ONLY `staging_path`
  (never the board, never a ledger). Given the same lens state + thresholds, `detect` is
  deterministic. Re-running `stage_proposals` is idempotent (dedup).

### CLI changes

New subcommand on the existing `ledger` Typer app:

```
ledger anomalies [--threshold KEY=VALUE]... [--propose] [--json/--table]
```

- default (no `--propose`): detect + REPORT the fired anomalies as structured output (json/table).
  Read-only; nothing is written. Rows: `key`, `title`, `metric`, `intent`.
- `--propose`: additionally STAGE a proposal (append to the staging buffer) for each fired,
  non-duplicate anomaly, then report `{key, title, action: staged|duplicate}`.
- `--threshold KEY=VALUE` (repeatable): override a default in `DEFAULTS`. An unknown key or a
  non-numeric value exits non-zero with a clear error.
- Staging + board paths resolve from `CC_BACKLOG_STAGING` / `CC_BACKLOG_BACKLOG` (cc-backlog's own
  env vars) so tests point at fixtures and the tool reuses the real buffer in production.

### Data model changes

None; no new lens table, no schema change. New pure module `src/ledger_observatory/anomalies.py`.

## Task Breakdown

### Phase 1: Foundation

- [ ] T1: `src/ledger_observatory/anomalies.py` , `DEFAULTS`, `Anomaly`, the three detectors
  (`_detect_debt`/`_detect_cost_spike`/`_detect_misfire`), `detect(thresholds)`. Each detector
  reads ONLY via `materialize.query`. Acceptance: `detect` importable; returns `[]` on an
  empty/noise-floor lens; each detector fires only over its threshold with its min-sample floor
  respected.

### Phase 2: Core

- [ ] T2: `render_block` + `stage_proposals` (append `## [staged]` blocks; dedup by normalized
  title vs board+staging; write ONLY the staging path). Acceptance: a fired anomaly appends one
  block; a re-run appends nothing; the board file is never opened for writing.
- [ ] T3: `ledger anomalies` CLI subcommand (`--threshold`, `--propose`, `--json/--table`) in
  `cli.py`, wired to `anomalies.detect`/`stage_proposals`. Acceptance: `ledger anomalies` reports;
  `--propose` stages; `--threshold` tunes; bad key/value exits non-zero.
- [ ] T4: `tests/test-feedback.sh` , the run-table below (threshold correctness both sides for all
  three detectors, the false-positive noise-floor NC, proposal-not-autofile, dedup idempotency,
  the tune flag, read-only-over-ledgers NC). Acceptance: green, exit 0.

### Phase 3: Polish

- [ ] T5: index the SG-04 feature in `tools/ledger-observatory/docs/proof-of-done.md` + a
  per-feature `docs/verification/feedback-loop/feedback-loop.md` (design/log + COVERAGE-DELTA),
  without overwriting the 01/02/03 canonical rows.

## After state

- `uv run ledger anomalies` reports any fired anomalies over the current lens (read-only). (Today:
  no such command; anomalies are invisible.)
- `uv run ledger anomalies --propose` stages a `## [staged]` proposal per fired, non-duplicate
  anomaly into `_meta/backlog-staging.md`, which `add-backlog` then reviews. It writes NO board.
- A noise-floor lens state proposes NOTHING (the false-positive NC).
- After a `--propose` run, every board `BACKLOG.md` is byte-identical (proposal-not-autofile) and
  every source ledger is byte-identical (read-only over the ledgers).
- `bash tests/test-feedback.sh` is green.

## Acceptance Criteria (global)

| # | Criterion (measurable) | Verify |
|---|---|---|
| AC1 | an over-threshold fixture FIRES the detector and `--propose` stages a `## [staged]` block | T4/F-debt-over, F-cost-spike, F-misfire-over |
| AC2 | threshold correctness BOTH sides for ALL 3 detectors: an at-boundary/just-under fixture does NOT fire, incl. the min-sample floor-minus-one | T4/F-debt-under, F-cost-nospike, F-cost-boundary, F-cost-floor, F-misfire-boundary, F-misfire-floor |
| AC3 | FALSE-POSITIVE NEGATIVE CONTROL: a noise-floor lens state proposes NOTHING (zero `## [staged]` blocks added) | T4/F-nc-noise |
| AC4 | PROPOSAL-NOT-AUTOFILE: after `--propose`, the board `BACKLOG.md` is byte-identical (sha256), AND the staged block is consumable by `add-backlog list` | T4/F-proposal-not-autofile |
| AC5 | dedup/idempotency: running `--propose` twice stages the anomaly ONCE (normalized-title dedup vs board+staging) | T4/F-dedup |
| AC6 | the one tune flag works: `--threshold debt_max=100` suppresses a would-fire debt anomaly; a lowered multiplier makes a mild rise fire | T4/F-threshold-flag |
| AC7 | read-only over the ledgers: after detect+propose, every SOURCE ledger is byte-identical | T4/F-readonly-nc |
| AC8 | detection reads via the SG-02 path only (`anomalies.py` imports `materialize`, never opens DuckDB or a raw ledger itself) | T4/F-one-path (static grep) |
| AC9 | COVERAGE-DELTA recorded (covered + uncovered named) | T5 |
| AC10 | SG-04 indexed in the multi-feature proof without overwriting 01/02/03 canonical content | T5 |

## Verification

```bash
cd ~/workspace/<owner>/ops-toolkit/tools/ledger-observatory && uv sync
bash tests/test-feedback.sh
```

## Test plan

`tests/test-feedback.sh`, mirroring SG-02/03's fixture-driven, hand-verified-value style. Fixtures:
a kit pipe-log corpus + a tide sqlite (known `gates_ovr` sums, misroute counts, cost series), plus
a fixture staging file (`CC_BACKLOG_STAGING`) and a fixture board (`CC_BACKLOG_BACKLOG`). No live
source read; no source or board mutated by the tool.

| Case | Category | Asserts (hand-verified) | AC |
|---|---|---|---|
| F-debt-over | threshold over | kit fixture with `SUM(gates_ovr)=6` (>5): `anomalies` reports the `debt` key; `--propose` adds a `## [staged] Feedback: unpaid understanding-debt over threshold` block | AC1 |
| F-debt-under | threshold under | kit fixture with `SUM(gates_ovr)=5` (at boundary, not `>`): `debt` does NOT fire, no block staged | AC2 |
| F-cost-spike | threshold over | tide fixture: 5 prior calls ~0.10 + latest 0.90 (9x): `cost_spike` fires + stages | AC1 |
| F-cost-nospike | threshold under | tide fixture: 6 calls all ~0.10 (latest not >3x median): does NOT fire | AC2 |
| F-cost-boundary | threshold AT boundary | tide fixture: 5 prior ~0.10 + latest exactly 0.30 (= median x 3.0): does NOT fire (`latest <= med*mult`) | AC2 |
| F-cost-floor | min-sample floor-minus-one | tide fixture: exactly 5 calls incl. one huge (== `cost_window`, one below the `window+1` floor): does NOT fire | AC2 |
| F-misfire-over | threshold over | kit fixture: 4 runs, 2 misrouted (rate 0.5 > 0.25, runs>=4): `misfire` fires + stages | AC1 |
| F-misfire-boundary | threshold AT boundary | kit fixture: 4 runs, 1 misrouted (rate exactly 0.25, runs>=4): does NOT fire (`rate <= max`) | AC2 |
| F-misfire-floor | min-sample floor-minus-one | kit fixture: 3 runs all misrouted (rate 1.0 but runs=3, one below `misfire_min_runs=4`): does NOT fire | AC2 |
| F-nc-noise | FALSE-POSITIVE NC | noise-floor fixture: `gates_ovr` sum <=5, flat costs, 0 misroutes over >=4 runs: `--propose` fires nothing, staging file gains ZERO `## [staged]` blocks | AC3 |
| F-proposal-not-autofile | propose-not-autofile | over-threshold fixture: sha256 the board BEFORE `--propose`, run, sha256 AFTER => identical; AND the staged block appears in the staging file AND `add-backlog list` lists it | AC4 |
| F-dedup | idempotency | run `--propose` twice on the debt-over fixture: exactly ONE `## [staged]` debt block in the staging file | AC5 |
| F-threshold-flag | tune flag | `--threshold debt_max=100` on the sum=6 fixture => debt does NOT fire; `--threshold cost_multiplier=1.1` on a mild rise => cost_spike fires | AC6 |
| F-readonly-nc | read-only NC | sha256 every source ledger (kit logs + tide db) before/after detect+propose => byte-identical | AC7 |
| F-one-path | one data path | `grep` asserts `anomalies.py` imports `materialize` and does NOT import `duckdb` / open a raw ledger path | AC8 |

COVERAGE-DELTA: covered , threshold correctness on BOTH sides for all three detectors (over fires;
at-boundary, no-spike, and both min-sample floors do not), the false-positive noise-floor NC
(proposes nothing), proposal-not-autofile (board byte-identical + the staged proposal consumable
by the real `add-backlog` human gate), dedup idempotency, the one `--threshold` tune flag, and the
read-only-over-ledgers NC + the static one-data-path check. Uncovered , TRUE trend detection for
misfire "climbing" (rate-vs-prior-window needs a rate-history store that does not exist yet;
scaffolded as rate-over-threshold, noted); the dedicated understanding-DEBT and TOKEN ledgers as
their own lens tables (future kit sub-goals; detectors read the overrides / tide-cost signals
present in the lens today); the live `add-backlog` PROMOTE->board write (that is the human gate,
out of this tool's scope, exercised only via `add-backlog list` here); real-data threshold
TIGHTENING (open-fork 3: the defaults are scaffolds, tuned after data accrues).

## Edge Cases

- Empty lens (no kit runs, no tide calls) , every detector returns no fire; `--propose` stages
  nothing (this IS part of the noise-floor NC).
- Fewer prior calls than `cost_window` / fewer runs than `misfire_min_runs` , the min-sample floor
  suppresses the fire (a single early expensive call or a 1-of-1 misroute must not fire).
- The anomaly is already on the board (promoted earlier) or already staged , dedup skips it (no
  duplicate row, idempotent re-run).
- A `--threshold` with an unknown key or non-numeric value , exit non-zero, clear error, nothing
  staged.
- The staging file does not exist yet , created with the cc-backlog header before the first block.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| lens db missing (fresh host) | `materialize`'s existing lazy-rebuild-on-missing (SG-02) | inherited, no new behavior |
| a threshold set so loose it fires on noise | the false-positive NC (F-nc-noise) goes RED | the NC is the guard; defaults ship with min-sample floors; `--threshold` is the escape hatch |
| the tool accidentally writes the board | F-proposal-not-autofile (sha256) goes RED | `stage_proposals` opens only the staging path for write; the board is opened read-only for dedup |

## Out of Scope

- The `ledger` read/query/rebuild/render logic (SG-02/03, shipped).
- The `add-backlog` PROMOTE step and any board `BACKLOG.md` write (the human gate; this tool only
  STAGES a proposal).
- Auto-filing rows (forbidden by the goal file; propose only).
- A second data path / re-reading raw ledgers (detect via SG-02 only).
- True trend/time-series detection (misfire "climbing" is scaffolded as rate-over-threshold).
- The tool README/no-orphan wiring polish (SG-05).

## Decision Log

- DEC-001: stage into the EXISTING cc-backlog buffer (`_meta/backlog-staging.md`) in its exact
  block format, consumed by the existing `add-backlog` human-gate, rather than a new convention.
  Implements the ROADMAP "reuse, do not invent a second board convention". Chosen over invoking
  the `work-intake` skill the goal file names, because `work-intake` writes `_meta/BACKLOG.md`
  DIRECTLY (no staging primitive) and so would auto-file (see Approaches #2). The shared contract
  is the staging FILE FORMAT + the `add-backlog` CONSUMER, not shared code: `cc-backlog` is a
  stdlib `bin/` script (no importable package under the per-tool isolation convention), so
  `anomalies.py` REIMPLEMENTS the tiny `_norm()` + block format locally (drift risk logged in
  impl-notes; the format is asserted byte-identical by the reuse of `add-backlog list` in
  F-proposal-not-autofile). Implements: T2.
- DEC-002: the tool's ONLY write is the gitignored staging buffer; it opens the board read-only
  (dedup) and never writes it. This is the propose-not-autofile guarantee, proven structurally
  (F-proposal-not-autofile sha256). Implements: T2.
- DEC-003: thresholds are defensible-default SCAFFOLDS with min-sample floors + a single
  `--threshold` tune flag (open-fork 3 resolved: scaffold now, tighten after real data). The two
  min-sample floors (`cost_window`, `misfire_min_runs`) ARE the false-positive guards.
- DEC-004: the `debt` detector reads `kit_runs.gates_ovr` (overrides = waved gates) as the
  unpaid-debt signal present in the SG-02 lens today; forward-compatible with a dedicated
  debt-ledger table. Delta from the goal file's "debt ledger" wording, logged in impl-notes.
- **Build:** `anomalies.py` imports `materialize` only (one read path); it does not import
  `duckdb` or open a raw ledger. Implements: T1, asserted by F-one-path.

## Review

- **spec-validate (kit:brief-reviewer, adversarial, 2026-07-04, headless):** VERDICT VALIDATED.
  Per-lens: design-record PASS (signal-mapping table cross-checked against `materialize.py` DDL,
  mermaid flowchart, decision log all real); false-positive NC genuinely load-bearing (F-nc-noise
  uses a non-empty near-boundary fixture, not an empty lens); propose-not-autofile PASS
  (structurally: `stage_proposals` opens the board read-only, writes only staging; sha256 +
  `add-backlog list` assertions); one-data-path PASS (imports `materialize` only, no `duckdb`);
  reuse fidelity of the staging format byte/logic-identical to cc-backlog. Two MAJOR findings
  folded before build: (1) the goal file names `work-intake` but this reuses `cc-backlog`;
  reconciled in Approaches #2 + DEC-001 (`work-intake` writes the board directly, so it cannot be
  the automated propose primitive; cc-backlog's staging buffer is). (2) AC2 claimed all-3-detector
  at-boundary coverage but only `debt` had a true boundary case; added F-cost-boundary (latest ==
  median x 3.0), F-cost-floor (== `cost_window`, floor-minus-one), F-misfire-boundary (rate ==
  0.25 exactly), F-misfire-floor (runs == 3, floor-minus-one). MINOR folded: DEC-001 now states
  `_norm` is reimplemented locally (shared contract = format + consumer, not code). Noted as
  tradeoffs (Open questions): a rejected proposal is suppressed permanently even if the metric
  later worsens; promoted rows land under add-backlog's `### Conversation intake (cc-backlog)`
  section header (provenance preserved in the row's Source field).

## Open questions

- KNOWN TRADEOFF (not blocking): dedup by stable title suppresses an anomaly key permanently once
  its title appears ANYWHERE in the board or staging, via BOTH paths, an explicit REJECT and a
  PROMOTE that later gets archived / moved to "Recently closed" (the `_existing_titles` regex
  matches any `| ID-NNN | <title> |` row wherever it sits). So debt rejected (or promoted then
  archived) at 6 will not re-propose even if it later climbs to 40. Acceptable for v1 (the
  alternative, re-nagging a consciously-handled item, is the board-spam the whole loop guards
  against); a future "re-fire when the metric worsens by Nx since last handled" is a candidate
  refinement. (Surfaced by the code-review lens as covering both the reject and the
  promote-then-recur path.)
- COSMETIC (not blocking): `add-backlog` files every promoted candidate under a fixed
  `### Conversation intake (cc-backlog)` section, so a ledger-observatory-sourced row lands under a
  "(cc-backlog)" heading. Provenance is preserved in the row's `Source: ledger-observatory
  anomalies <date>` note; renaming the shared section is out of scope (it is cc-backlog's).
