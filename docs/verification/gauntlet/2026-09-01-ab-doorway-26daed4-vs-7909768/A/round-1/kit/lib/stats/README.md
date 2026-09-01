## stats

The kit's **read plane**: a stateless projection over the append-only ledger (the write
plane, `lib/ledger/ledger.sh` + gate/proof/telemetry writers) and the scattered source
ledgers (the learning ledger, tide's state, tg-cleanup snapshots, the understanding-debt
and token-cost markers). One agent-callable, **read-only** observability surface, with a
feedback loop that proposes backlog rows off anomalies instead of letting them pile up
unseen.

**Persists NOTHING (SPEC-182).** Every command materializes an in-memory DuckDB lens from
the canonical files, runs the query, and discards it: delete stats' output (there is none)
and re-run and you get the same answer from the log. A projection is never a second source
of truth. This retires the earlier persistent `~/.cache/.../ledger.duckdb` cache.

**History.** Renamed from `ledger-observatory` (kit-modularity SG-02, 2026-07-05): the read
side never carries a `-ledger` name (write-side streams correctly keep it). Previously
migrated into dwarves-kit from `ops-toolkit/tools/ledger-observatory/` (goal 05K,
2026-07-05), because it reads gate-ledger telemetry (`kit_gates`, `kit_runs`) that lives in
this repo. Two adapter-default families changed shape in that move (kit-internal sources
default to this repo's own root; ops-toolkit-specific sources require an explicit env var) --
see "Source roots" below. Historical mega-goals `docs/megagoals/ledger-observatory/` and
`docs/megagoals/harness-observatory/` moved alongside it.

**DuckDB is a read-only LENS, never a second source of truth.** The FILES stay canonical;
the lens is materialized IN MEMORY per invocation (`:memory:`) and never touches disk, so
there is nothing to delete and nothing that can drift (`stats rebuild` just reports what it
would see). The tool never writes back to any source ledger (the icy-ops/asus-mesh/growatt-pull
read-only-by-contract shape). The one exception is the feedback loop's `--propose`, and even
that writes only the gitignored cc-backlog *staging* buffer, never a board, never a ledger
(see "The feedback loop" below).

### Status

| Sub-goal | Lands | State |
|---|---|---|
| 01 | schema doc + adapter contracts + conformance check | shipped, merged b4ff175e |
| 02 | the `ledger` DuckDB lens + agent-callable CLI | shipped, merged e6ff875b |
| 03 | render skill: terminal + web Artifact, single data path | shipped, merged 7f8f7e2c |
| 04 | feedback loop: `stats anomalies` + propose-not-autofile | shipped, merged a0806ff3 |
| 05 | docs finalized to reflect the wired state above | shipped |
| 06-11 | 6 more lenses on the same SG-02 read path (`kit-gates`/`gate-yield`, `defect-correlation`, `deviation-rate`, `anomalies-advisor`, `sessions-digest`/`digest`, `memory-sweep`) | shipped (see `docs/megagoals/harness-observatory/`; not yet folded into this README's CLI walkthrough below -- a pre-existing doc gap, not introduced by the move) |
| 05K | moved into dwarves-kit verbatim + adapter-default split + `stats mega-durations` (per-rid wall time) | shipped, this PR |

### The `stats` CLI (SG-02)

A read-only, agent-callable CLI. Structured output (`--json` default | `--table`):

```bash
cd lib/stats
uv sync
uv run stats rebuild                       # (re)materialize the lens from the files
uv run stats tables                        # list materialized tables + row counts
uv run stats show kit_runs --limit 5       # a named table's rows (deterministic order)
uv run stats query "SELECT k.repo, count(m.id) FROM kit_runs k \
    JOIN tide_moves m ON m.route = k.lane GROUP BY 1"   # arbitrary read-only SQL + JOINs
```

Materialized tables: `kit_runs` (the whole kit corpus, read via lane-telemetry's own
parser), `tide_moves` + `tide_tier_b_calls` (tide's `state.sqlite`), `tg_dialogs`
(tg-cleanup `*.json`, both shapes), `learned` (`learned-ledger.md`).

A write-shaped `query` is refused two ways: a statement guard rejects it before execution,
and after materialization the in-memory connection latches `enable_external_access=false`,
so no query can COPY TO / read_csv / ATTACH a file. Neither can mutate a source or touch disk.

### Per-rid wall time: `stats mega-durations` (05K)

The original ask this move folds in ("where does the 2-3h go"): per-rid wall time =
`max(end_ts) - min(start_ts)` across every `kit_gates` row that carries BOTH OUTCOME
timestamps for that rid (data-driven `GROUP BY rid`, no hardcoded gate whitelist).

```bash
uv run stats mega-durations --table
```

A row missing either timestamp is excluded and counted separately ("N rows excluded"),
honest-zero on a corpus with no timed gates at all (never a crash). As of this writing
the OUTCOME bracket emitter is wired into very few gates in the real corpus, so most
`kit_gates` rows have no timestamps yet -- `mega-durations` is ready for when more of the
kit's gates start emitting OUTCOME brackets; see the live run pasted in
`docs/proof-of-done.md` for today's actual (sparse) answer.

### Source roots (env-overridable; a missing source is skipped, never fatal)

Two families, since the 05K move into dwarves-kit (see the migration note above):
**kit-internal** sources default to THIS repo's own root (computed dynamically, never
hardcoded, so a future move never goes stale again); **ops-toolkit-specific** sources
have NO default post-move (tide/tg-cleanup/learned-ledger/cc-backlog are ops-toolkit
tools, not kit-generic ones) -- set the env var explicitly to opt in. Everything else
was already host-generic (Claude Code's own dirs, XDG state) and is unaffected.

| Env | Default | Family |
|---|---|---|
| `KIT_LEDGER_DIR` | (canonical ledger root; wins over `DWARVES_KIT_LOG_DIR`) | host-generic |
| `DWARVES_KIT_LOG_DIR` | `~/.local/state/dwarves-kit/logs` (back-compat alias of the above) | host-generic |
| `DWARVES_KIT_LIB` | this repo's own `lib/` | kit-internal |
| `STATS_GIT_REPO_DIR` | this repo's own root | kit-internal |
| `STATS_MEMORY_REPO_DIR` | this repo's own root | kit-internal |
| `STATS_TIDE_DB` | none (was `~/.local/state/tide/state.sqlite`) | ops-toolkit-specific |
| `STATS_TGCLEANUP_DIR` | none (was `tools/tg-cleanup`) | ops-toolkit-specific |
| `STATS_LEARNED_MD` | none (was `_meta/learned-ledger.md`) | ops-toolkit-specific |
| `STATS_REPOS` | none, empty list (was both ops-toolkit + dwarves-kit hardcoded; comma-separated repo ROOTS -- `rejected_findings`/`stats review-yield`, SPEC-137, see `config.rejected_findings_repos()`) | ops-toolkit-specific |
| `CC_BACKLOG_STAGING` | none (was `_meta/backlog-staging.md`; the feedback loop's ONLY write target) | ops-toolkit-specific |
| `CC_BACKLOG_BACKLOG` | none (was `_meta/BACKLOG.md`; read-only dedup source for the feedback loop) | ops-toolkit-specific |
| `STATS_SESSIONS_DIR` | `~/.claude/projects` | host-generic |
| `STATS_SECRET_GUARD_LOG` | `~/.cache/claude-secret-guard.log` | host-generic |
| `STATS_MEMORY_PROJECTS_ROOT` | `~/.claude/projects` | host-generic |

`--propose` (the feedback loop's only write path) fails with a clean CLI error, never a
silent write to the wrong place, if it has a real proposal to stage but neither
`CC_BACKLOG_STAGING` nor `OPS_TOOLKIT` is set.

A "missing source is skipped, never fatal" is honest as far as it goes but has a real gap:
see tradeoff (4) below, there is currently no operator-visible signal distinguishing
"checked and found nothing" from "never even looked."

### Render a query as terminal or a web Artifact (SG-03)

`stats render` reuses the SAME `show`/`query` read path (no second data source), then
hands the one fetched row set to one of two pure formatters:

```bash
# quick look, phone-legible bot-reply-formatting table/bars
uv run stats render kit_runs --surface terminal --limit 10

# shareable, self-contained HTML for the Artifact tool
uv run stats render kit_runs --surface artifact --title "Ledger" --out /tmp/ledger.html

# ad-hoc SQL, either surface
uv run stats render --query "SELECT repo, count(*) AS n FROM kit_runs GROUP BY 1" \
  --surface terminal
```

See `skills/stats/SKILL.md` (repo root; relocated per ADR-0034 decision 8) for the full
trigger set + surface-selection rule (quick look -> terminal; share/review -> Artifact).

### The feedback loop: `stats anomalies` (SG-04)

Detects 3 anomaly classes over the SAME SG-02 lens (one data path, no re-query of a raw
ledger): unpaid understanding-debt (`SUM(kit_runs.gates_ovr)` over a threshold), a
token-cost spike (latest `tide_tier_b_calls.cost_usd` vs. the rolling median of the prior
window), and a gate/proof misfire rate (`lane_misroute`/`type_misroute` over a threshold,
with a minimum-sample floor so a 1-of-1 run can never read as "100% misfiring").

```bash
uv run stats anomalies                              # report only, writes nothing
uv run stats anomalies --threshold debt_max=10       # tune a threshold (KEY=VALUE, repeatable)
uv run stats anomalies --propose                     # STAGE a row per fired anomaly
```

`--propose` appends a `## [staged]` block, byte-format-identical to what `tools/cc-backlog`
itself writes, to the cc-backlog **staging buffer** (`_meta/backlog-staging.md`). It never
writes `_meta/BACKLOG.md` (opened read-only, for dedup only) and never writes a source
ledger. The operator promotes a staged row via the existing `board promote` human gate (ex `add-backlog`, ADR-0034), same
as any other cc-backlog candidate; this tool has no path to a board row. Re-running
`--propose` on unchanged state is idempotent (dedup by normalized title against both the
board and the staging file), so it is safe to call repeatedly, e.g. every time the agent
checks in.

### Install the render skill

The skill's canonical source lives at the repo root, `skills/stats/SKILL.md`
(relocated from `skill/` here per ADR-0034 decision 8: at the subsystem-internal
path it never installed, because `install.sh` globs `skills/*/SKILL.md` only).
It now installs automatically on both install paths (bash installer + plugin);
no symlink step. Edit the in-repo file. `tests/test-docs-wiring.sh` verifies the
skill source is wired correctly (frontmatter carries its triggers, the body calls
the `ledger` CLI).

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
   `kit_runs`, not per-repo, while the proposal itself stages into wherever
   `CC_BACKLOG_STAGING`/`OPS_TOOLKIT` points (an explicit, ops-toolkit-specific opt-in
   post-05K) regardless of which repo the signal came from, a real attribution seam. And
   it is a seam over incomplete data: as measured on this repo's live ledger, roughly 44%
   of `kit_runs` rows (35 of 79) carry `repo = "?"`, lane-telemetry's marker for a run with
   no `repo=` field in its `START` line, so a meaningful slice of the corpus an anomaly
   sums over is not attributable to any repo at all.
4. **A missing source is skipped silently.** `stats tables`/`rebuild` report a 0-row table
   for an absent source (e.g. no tide `state.sqlite` on this host) exactly the same way they
   report a genuinely-empty-but-present source. There is no `ledger doctor`-style
   "checked, not found" vs. "checked, 0 rows" signal today (see `NOTES.md`).

### What's here

| Path | Purpose |
|---|---|
| `src/stats/{config,adapters,materialize,cli}.py` | the package: env config, the 4 readers, the DuckDB build/query, the CLI |
| `src/stats/render.py` | pure formatters (`render_terminal`/`render_artifact`), zero I/O, the SG-03 render layer |
| `src/stats/anomalies.py` | the SG-04 detectors + the propose-not-autofile stager |
| `../../skills/stats/SKILL.md` | the render skill source (repo-root skills/, relocated per ADR-0034 decision 8; see Install above) |
| `docs/ledger-event-schema.md` · `docs/adapter-contracts.md` | the SG-01 contract the views read against |
| `docs/specs/SPEC-127-etl-cli.md` · `SPEC-128-render-skill.md` · `SPEC-129-feedback-loop.md` · `SPEC-130-docs-wiring.md` | the per-sub-goal specs |
| `docs/proof-of-done.md` | the multi-feature proof index (schema, etl-cli, render-skill, feedback-loop) |
| `tests/test-ledger-cli.sh` | the over-test: rebuild, show/query both formats, a cross-ledger JOIN, delete-and-rematerialize, cross-format correctness across all 4 shapes, the read-only NC |
| `tests/test-schema-conform.sh` | the SG-01 schema conformance proof |
| `tests/test-render-skill.sh` | the SG-03 test: trigger phrases, queries-via-02 on a mocked JSON blob, both surfaces, the single-data-path NC |
| `tests/test-feedback.sh` | the SG-04 over-test: threshold correctness both sides, the false-positive NC, propose-not-autofile, dedup idempotency, read-only NC, plus the 05K no-staging-config refusal NC |
| `tests/test-docs-wiring.sh` | the SG-05 no-orphan wiring check: docs presence, skill-fires -> CLI-invoked -> work-intake-fed, and an over-claim negative control |
| `tests/test-mega-durations.sh` | the 05K over-test: golden fixture with known per-rid durations, the all-NULL/stripped NC (exit 0, honest zero), delete-and-rematerialize, read-only NC |

### Run the tests

```bash
bash lib/stats/tests/test-schema-conform.sh   # SG-01
bash lib/stats/tests/test-ledger-cli.sh       # SG-02
bash lib/stats/tests/test-render-skill.sh     # SG-03
bash lib/stats/tests/test-feedback.sh         # SG-04
bash lib/stats/tests/test-docs-wiring.sh      # SG-05
bash lib/stats/tests/test-mega-durations.sh   # 05K
```

Every `tests/test-*.sh` file in this directory is part of the suite (13 pre-existing +
this one); run them all with a simple loop:

```bash
for f in lib/stats/tests/test-*.sh; do bash "$f" || echo "FAILED: $f"; done
```
