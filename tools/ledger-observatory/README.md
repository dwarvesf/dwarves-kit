## ledger-observatory

Turns the kit's scattered write-only ledgers (gate/proof/telemetry, the learning
ledger, tide's state, tg-cleanup snapshots, plus the planned understanding-debt and
token-cost markers) into one agent-callable, **read-only** observability surface, with a
feedback loop that proposes backlog rows off anomalies instead of letting them pile up
unseen. See the mega-goal: `docs/megagoals/ledger-observatory/ROADMAP.md`.

**DuckDB is a read-only LENS, never a second source of truth.** The FILES stay canonical;
the db is derivable + disposable, delete it and re-materialize (`ledger rebuild`), you lose
nothing. The tool never writes back to any source ledger (the icy-ops/asus-mesh/growatt-pull
read-only-by-contract shape). The one exception is the feedback loop's `--propose`, and even
that writes only the gitignored cc-backlog *staging* buffer, never a board, never a ledger
(see "The feedback loop" below).

### Status

| Sub-goal | Lands | State |
|---|---|---|
| 01 | schema doc + adapter contracts + conformance check | shipped, merged b4ff175e |
| 02 | the `ledger` DuckDB lens + agent-callable CLI | shipped, merged e6ff875b |
| 03 | render skill: terminal + web Artifact, single data path | shipped, merged 7f8f7e2c |
| 04 | feedback loop: `ledger anomalies` + propose-not-autofile | shipped, merged a0806ff3 |
| 05 | this PR: docs finalized to reflect the wired state above | in progress |

### The `ledger` CLI (SG-02)

A read-only, agent-callable CLI. Structured output (`--json` default | `--table`):

```bash
cd tools/ledger-observatory
uv sync
uv run ledger rebuild                       # (re)materialize the lens from the files
uv run ledger tables                        # list materialized tables + row counts
uv run ledger show kit_runs --limit 5       # a named table's rows (deterministic order)
uv run ledger query "SELECT k.repo, count(m.id) FROM kit_runs k \
    JOIN tide_moves m ON m.route = k.lane GROUP BY 1"   # arbitrary read-only SQL + JOINs
```

Materialized tables: `kit_runs` (the whole kit corpus, read via lane-telemetry's own
parser), `tide_moves` + `tide_tier_b_calls` (tide's `state.sqlite`), `tg_dialogs`
(tg-cleanup `*.json`, both shapes), `learned` (`learned-ledger.md`).

A write-shaped `query` is refused two ways: a statement guard rejects it before execution,
and the query connection is opened `read_only=True`. Neither can mutate a source.

### Source roots (env-overridable; a missing source is skipped, never fatal)

| Env | Default |
|---|---|
| `LEDGER_OBSERVATORY_DB` | `~/.cache/ledger-observatory/ledger.duckdb` (derivable; gitignored) |
| `DWARVES_KIT_LOG_DIR` | `~/.local/state/dwarves-kit/logs` (lane-telemetry's own) |
| `DWARVES_KIT_LIB` | `~/.claude/dwarves-kit/lib` |
| `LEDGER_OBS_TIDE_DB` | `~/.local/state/tide/state.sqlite` |
| `LEDGER_OBS_TGCLEANUP_DIR` | `tools/tg-cleanup` |
| `LEDGER_OBS_LEARNED_MD` | `_meta/learned-ledger.md` |
| `LEDGER_OBS_REPOS` | `~/workspace/tieubao/ops-toolkit,~/workspace/tieubao/dwarves-kit` (comma-separated repo ROOTS -- `rejected_findings`/`ledger review-yield`, SPEC-137; the tool's first genuinely multi-repo-in-one-materialization knob, see `config.rejected_findings_repos()`) |
| `CC_BACKLOG_STAGING` | `_meta/backlog-staging.md` (the feedback loop's ONLY write target) |
| `CC_BACKLOG_BACKLOG` | `_meta/BACKLOG.md` (read-only dedup source for the feedback loop) |

A "missing source is skipped, never fatal" is honest as far as it goes but has a real gap:
see tradeoff (4) below, there is currently no operator-visible signal distinguishing
"checked and found nothing" from "never even looked."

### Render a query as terminal or a web Artifact (SG-03)

`ledger render` reuses the SAME `show`/`query` read path (no second data source), then
hands the one fetched row set to one of two pure formatters:

```bash
# quick look, phone-legible bot-reply-formatting table/bars
uv run ledger render kit_runs --surface terminal --limit 10

# shareable, self-contained HTML for the Artifact tool
uv run ledger render kit_runs --surface artifact --title "Ledger" --out /tmp/ledger.html

# ad-hoc SQL, either surface
uv run ledger render --query "SELECT repo, count(*) AS n FROM kit_runs GROUP BY 1" \
  --surface terminal
```

See `skill/SKILL.md` for the full trigger set + surface-selection rule (quick look ->
terminal; share/review -> Artifact).

### The feedback loop: `ledger anomalies` (SG-04)

Detects 3 anomaly classes over the SAME SG-02 lens (one data path, no re-query of a raw
ledger): unpaid understanding-debt (`SUM(kit_runs.gates_ovr)` over a threshold), a
token-cost spike (latest `tide_tier_b_calls.cost_usd` vs. the rolling median of the prior
window), and a gate/proof misfire rate (`lane_misroute`/`type_misroute` over a threshold,
with a minimum-sample floor so a 1-of-1 run can never read as "100% misfiring").

```bash
uv run ledger anomalies                              # report only, writes nothing
uv run ledger anomalies --threshold debt_max=10       # tune a threshold (KEY=VALUE, repeatable)
uv run ledger anomalies --propose                     # STAGE a row per fired anomaly
```

`--propose` appends a `## [staged]` block, byte-format-identical to what `tools/cc-backlog`
itself writes, to the cc-backlog **staging buffer** (`_meta/backlog-staging.md`). It never
writes `_meta/BACKLOG.md` (opened read-only, for dedup only) and never writes a source
ledger. The operator promotes a staged row via the existing `add-backlog` human gate, same
as any other cc-backlog candidate; this tool has no path to a board row. Re-running
`--propose` on unchanged state is idempotent (dedup by normalized title against both the
board and the staging file), so it is safe to call repeatedly, e.g. every time the agent
checks in.

### Install the render skill

The skill's canonical source lives in-repo at `skill/SKILL.md` (ops-toolkit ships zero
skills directly into `~/.claude/skills/` from a tool PR). To make it fire in a Claude
Code session, symlink it in:

```bash
ln -sf "$(pwd)/skill/SKILL.md" ~/.claude/skills/ledger-observatory/SKILL.md
```

Edit the in-repo file, not the symlinked copy; the symlink keeps them identical. This
step is NOT run by any PR in this repo (out of ops-toolkit scope to touch
`~/.claude/skills/`); `tests/test-docs-wiring.sh` verifies the skill source is wired
correctly (frontmatter carries its triggers, the body calls the `ledger` CLI) but cannot
verify the symlink itself exists on any given host.

### Known tradeoffs (stated plainly, not swept under "future work")

These are accepted-for-now, not defects to hide. The proven claims above (read-only-lens,
files-canonical, delete-and-rematerialize, propose-never-autofile) are backed by the test
suites listed below; these four are not, and the docs should not pretend otherwise:

1. **The kit-run table schema is defined twice, hand-synced.** `adapters.KIT_COLUMNS` (the
   15-field order `read_kit()` parses into) and `materialize._KIT_DDL` (the DuckDB column
   types) list the same 15 fields independently. Nothing asserts they stay in lockstep; a
   column added to one and not the other silently drifts. (`NOTES.md` proposes a
   single-source-of-truth fix, not built here.)
2. **The kit-side read couples to lane-telemetry's private `_rows()` helper.** This is the
   mandated reuse (do not re-implement the pipe-log parser), but it means a field-count
   change in lane-telemetry's TSV output truncate-pads with empty strings
   (`adapters.read_kit`) rather than failing loud. A silent schema drift upstream shows up
   here as blank columns, not an error.
3. **Anomaly `home` attribution is a static per-detector guess** (`"dwarves-kit"` for
   debt/misfire, `"ops-toolkit"` for cost-spike), not derived from the actual data; the
   operator re-homes on promote. Debt and misfire sums are GLOBAL across every repo in
   `kit_runs`, not per-repo, while the proposal itself stages into ops-toolkit's own
   `_meta/backlog-staging.md` regardless of which repo the signal came from, a real
   attribution seam. And it is a seam over incomplete data: as measured on this repo's live
   ledger, roughly 44% of `kit_runs` rows (35 of 79) carry `repo = "?"`, lane-telemetry's
   marker for a run with no `repo=` field in its `START` line, so a meaningful slice of the
   corpus an anomaly sums over is not attributable to any repo at all.
4. **A missing source is skipped silently.** `ledger tables`/`rebuild` report a 0-row table
   for an absent source (e.g. no tide `state.sqlite` on this host) exactly the same way they
   report a genuinely-empty-but-present source. There is no `ledger doctor`-style
   "checked, not found" vs. "checked, 0 rows" signal today (see `NOTES.md`).

### What's here

| Path | Purpose |
|---|---|
| `src/ledger_observatory/{config,adapters,materialize,cli}.py` | the package: env config, the 4 readers, the DuckDB build/query, the CLI |
| `src/ledger_observatory/render.py` | pure formatters (`render_terminal`/`render_artifact`), zero I/O, the SG-03 render layer |
| `src/ledger_observatory/anomalies.py` | the SG-04 detectors + the propose-not-autofile stager |
| `skill/SKILL.md` | the render skill source (versioned in-repo; see Install above) |
| `docs/ledger-event-schema.md` · `docs/adapter-contracts.md` | the SG-01 contract the views read against |
| `docs/specs/SPEC-127-etl-cli.md` · `SPEC-128-render-skill.md` · `SPEC-129-feedback-loop.md` · `SPEC-130-docs-wiring.md` | the per-sub-goal specs |
| `docs/proof-of-done.md` | the multi-feature proof index (schema, etl-cli, render-skill, feedback-loop) |
| `tests/test-ledger-cli.sh` | the over-test: rebuild, show/query both formats, a cross-ledger JOIN, delete-and-rematerialize, cross-format correctness across all 4 shapes, the read-only NC |
| `tests/test-schema-conform.sh` | the SG-01 schema conformance proof |
| `tests/test-render-skill.sh` | the SG-03 test: trigger phrases, queries-via-02 on a mocked JSON blob, both surfaces, the single-data-path NC |
| `tests/test-feedback.sh` | the SG-04 over-test: threshold correctness both sides, the false-positive NC, propose-not-autofile, dedup idempotency, read-only NC |
| `tests/test-docs-wiring.sh` | the SG-05 no-orphan wiring check: docs presence, skill-fires -> CLI-invoked -> work-intake-fed, and an over-claim negative control |

### Run the tests

```bash
bash tools/ledger-observatory/tests/test-schema-conform.sh   # SG-01
bash tools/ledger-observatory/tests/test-ledger-cli.sh       # SG-02
bash tools/ledger-observatory/tests/test-render-skill.sh     # SG-03
bash tools/ledger-observatory/tests/test-feedback.sh         # SG-04
bash tools/ledger-observatory/tests/test-docs-wiring.sh      # SG-05
```
