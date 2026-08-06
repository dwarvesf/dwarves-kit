# Spec: the render skill (terminal + web Artifact, single data path)
Generated: 2026-07-04
Status: VALIDATED
Lane: normal (lane-classify returned tiny; escalated per goal-file explicit /spec+/spec-validate mandate, see impl-notes)
Depends-on: SPEC-127 (the `ledger` CLI, shipped, PR #673, merged to main as e6ff875b)

## Problem

SG-02 shipped a working, agent-callable `ledger` CLI (`show`/`query`/`rebuild`/`tables`,
structured `--json`/`--table` output), but nothing consumes it for a human-facing answer.
The operator still cannot ask "show me the ledger state" and get a rendered reply; the
ledgers stay observable only to someone who already knows the exact CLI invocation. This
sub-goal is the human-facing lens: a skill that fires on the operator's natural-language
ask, queries the SG-02 CLI (one data path, never a second read), and renders the result as
either a quick in-terminal reply or a shareable web Artifact.

## Solution

### Approaches considered

1. **A thin `ledger render` CLI subcommand (pure formatting, zero new reads) + a SKILL.md
   that shells out to it (CHOSEN).** The CLI gains one subcommand that reuses the EXACT
   same `materialize.show`/`materialize.query` functions SG-02 already ships (no new read
   path), converts the result to the same list-of-dict shape `--json` already emits, and
   hands that one object to one of two pure formatting functions
   (`render.render_terminal` / `render.render_artifact`) living in a new `render.py` module
   that does zero I/O of its own. The SKILL.md documents when to run which surface. This
   keeps the single-data-path guarantee structural (one Python object, two formatters), not
   just a documentation promise, and keeps `render.py` trivially unit-testable with a
   mocked JSON blob (no DuckDB, no live ledgers needed in tests).
2. **The skill re-implements its own DuckDB query.** Rejected outright: the goal file's
   Scope edges explicitly forbid "a re-implementation of the ledger read"; this is exactly
   the "divergent second data source" the NC exists to catch.
3. **A persistent TUI/dashboard app the operator launches separately.** Rejected: the
   ROADMAP's binding Assumptions state the consumer is the AGENT on-demand, not a human
   TUI (the custom Go/bubbletea TUI was explicitly deleted by the operator reframe this
   mega-goal executes). The goal file's Scope edges repeat this as a NOT-case.

### Chosen: approach 1.

### Extensibility & boundaries

- Adding a third render surface later (e.g. a Discord embed via `bot-reply-formatting`'s
  §2 Discord path) means adding one more pure function in `render.py` that takes the same
  `rows: list[dict]` shape; the CLI's `--surface` enum grows by one value. No change to how
  data is fetched.
- `render.py` has one purpose (format a list-of-dict row set into a surface string) and no
  dependency on `adapters`/`materialize`/DuckDB at all; it is independently testable and
  independently reusable if a future sub-goal (04's feedback loop) wants a rendered
  digest of proposed anomaly rows.

### Architecture

See `## Design` below.

## Design

Design-bearing (a new component: the render module + CLI subcommand; a data-flow
contract, single-data-path, that a later sub-goal must not violate). This block is the
design record (ADR-0031 §1).

### Approaches considered + chosen

See `## Solution` above; approach 1, unchanged view.

### Diagram (flowchart: control flow from trigger to rendered surface)

```mermaid
flowchart LR
    A[operator asks: "show me the ledger state" / "my debt" / "telemetry" / "token cost"] --> B{SKILL.md: which surface?}
    B -->|quick look| C[uv run ledger render NAME --surface terminal]
    B -->|share / review| D[uv run ledger render NAME --surface artifact --out FILE]
    C --> E[materialize.show/query -- the ONE read path, reused from SG-02]
    D --> E
    E --> F[rows: list of dict -- the ONE data object]
    F --> G[render.render_terminal rows]
    F --> H[render.render_artifact rows]
    G --> I[stdout: bot-reply-formatting code-block table/bars -- agent pastes into its reply]
    H --> J[stdout/file: self-contained HTML]
    J --> K[agent calls the Artifact tool on the HTML file]
```

### ADR link(s)

No new ADR: this is an additive component inside an already-decided architecture (the
ROADMAP's DuckDB-as-lens + agent-callable-CLI shape, SPEC-127's Design). No irreversible
choice is made here beyond the render/CLI split, which is reversible (a formatting
function, easy to replace).

### Boundaries & failure modes

See `## Failure modes` below. In bounds: formatting an already-fetched `rows` object.
Out of bounds: fetching data, mutating any ledger, persisting anything beyond the
`--out` HTML file the operator explicitly asked for.

## Technical Design

### Interfaces (I/O contract)

- **Inputs / consumes:** `materialize.show(name, limit)` and `materialize.query(sql)`
  (SG-02, unchanged signatures, `(cols, rows: list[tuple])`), converted via the SAME
  `_jsonable` coercion `cli.py::_emit` already uses, to `rows: list[dict[str, Any]]` , the
  identical shape the CLI's `--json` output already produces on stdout. `render.py`'s two
  public functions consume exactly this shape and nothing else.
- **Outputs / produces:** `render_terminal(rows, title=None) -> str` , a
  `bot-reply-formatting`-disciplined code-block table (right-aligned numerics, a bar-fill
  column when a 0-100 numeric column is present, cell width capped at the skill's
  32-cell heuristic per `bot-reply-formatting` §5c cross-platform default).
  `render_artifact(rows, title=None) -> str` , a complete, self-contained `<!doctype
  html>...</html>` string: inline `<style>`, no external requests, a light/dark-aware
  stylesheet (`prefers-color-scheme`), a plain HTML `<table>` of the same rows. Every
  cell/title value is HTML-escaped (`html.escape`) before interpolation , the ledger rows
  are Han's own local data (low risk), but a ledger value containing `<`/`&`/`"` must not
  be able to break the table markup or inject a tag into the rendered Artifact (spec-
  validate Reviewer 1).
- **Invariants:** neither function performs I/O (no file read, no subprocess, no network);
  both are pure `rows -> str`. The CLI's `render` subcommand is the ONLY place that calls
  `materialize.show`/`query`; `render.py` never imports `materialize` or `duckdb`. Given
  the same `rows` object, `render_terminal` and `render_artifact` never diverge on which
  VALUES they show (this is what AC5/the single-data-path NC test proves).

### CLI changes

New subcommand on the existing `ledger` Typer app (`cli.py`), reusing `show`/`query`
under the hood (no new read path):

```
ledger render NAME [--query SQL] --surface {terminal,artifact} [--title TEXT] [--limit N] [--out PATH]
```

- Exactly one of `NAME` (a materialized table, per `show`) or `--query SQL` (per `query`,
  same read-only guard) selects the row source; mirrors the existing `show`/`query` split,
  adds no new fetch logic.
- `--surface terminal` prints `render_terminal(rows, title)` to stdout.
- `--surface artifact` prints `render_artifact(rows, title)` to stdout AND, if `--out PATH`
  is given, also writes it to `PATH` (so the SKILL.md's documented flow can write straight
  to a file the Artifact tool then reads).
- `--title` defaults to the table name or `"ledger query"`.

### Data model changes

None; no schema change. `render.py` is a new pure-function module,
`src/ledger_observatory/render.py`.

### SKILL.md (the human-facing lens)

Co-located at `tools/ledger-observatory/skill/SKILL.md` (ops-toolkit ships zero skills
directly into `~/.claude/skills/` from a tool PR; this in-repo file is the versioned
source). Frontmatter modeled on `~/.claude/skills/growatt-solar/SKILL.md` and
`~/.claude/skills/icy-ops/SKILL.md`:

- `name: ledger-observatory`
- `description:` a trigger-rich sentence naming the fire phrases , "show me the ledger
  state", "my debt" / "understanding debt", "telemetry", "token cost" / "how much am I
  spending on tokens", "kit runs" / "kit lane telemetry", "ledger status", "render the
  ledger" / "ledger dashboard", "share this as an artifact" (when already mid-ledger-
  conversation) , plus the read-only-by-contract + NOT-cases (NOT for editing/mutating any
  ledger; NOT the CLI itself, use SG-02's `ledger` directly for ad-hoc SQL; NOT the
  anomaly/feedback loop, SG-04; NOT a persistent TUI/app).
- Body: which command answers which question (mirrors icy-ops's table), the
  surface-selection rule (quick look mid-conversation -> `--surface terminal`; "share" /
  "send this" / "for review" -> `--surface artifact --out <tmp path>` then the Artifact
  tool), and the install pointer to the tool README.

### Install path (README, doc-only this PR)

`tools/ledger-observatory/README.md` gains an "Install the render skill" section: `ln -sf
$(pwd)/skill/SKILL.md ~/.claude/skills/ledger-observatory/SKILL.md` (symlink so the
in-repo file stays the source of truth). This PR does NOT touch `~/.claude/skills/` or any
dotfiles-managed path , documented only. SG-05's no-orphan check verifies the wiring is
real once installed.

## Task Breakdown

### Phase 1: Foundation

- [x] T1: DONE (commit e1926c2f/91f26600/cd29d60a, verified) -- `src/ledger_observatory/render.py` , `render_terminal(rows, title=None) -> str`
  and `render_artifact(rows, title=None) -> str`, pure functions, no I/O, no imports from
  `materialize`/`adapters`/`duckdb`. Acceptance: importable standalone; both raise no
  exception on an empty `rows` list (render a "(0 rows)" placeholder, not a crash);
  `render_artifact` HTML-escapes every cell/title value.

### Phase 2: Core

- [x] T2: DONE (commit e1926c2f/91f26600/cd29d60a, verified) -- `ledger render` CLI subcommand in `cli.py`, wired to `materialize.show`/`query`
  (reused, not re-implemented) + `render.py`. Acceptance: `uv run ledger render <table>
  --surface terminal` and `--surface artifact` both exit 0 against the live rebuilt db.
- [x] T3: DONE (commit e1926c2f/91f26600/cd29d60a, verified) -- `tests/test-render-skill.sh` , the 5-case run-table below, incl. the
  single-data-path NC. Acceptance: green, `bash tests/test-render-skill.sh` exit 0.
- [x] T4: DONE (commit e1926c2f/91f26600/cd29d60a, verified) -- capture a real terminal-render sample + a real Artifact HTML sample under
  `tools/ledger-observatory/docs/verification/render-skill/samples/`. Acceptance: both
  files exist, non-empty, generated by an actual `ledger render` invocation (not
  hand-typed).

### Phase 3: Polish

- [x] T5: DONE (commit e1926c2f/91f26600/cd29d60a, verified) -- `tools/ledger-observatory/skill/SKILL.md` , the full skill source per Technical
  Design above.
- [x] T6: DONE (commit e1926c2f/91f26600/cd29d60a, verified) -- README "Install the render skill" section (doc-only, no `~/.claude/skills`
  writes).
- [x] T7: DONE (commit e1926c2f/91f26600/cd29d60a, verified) -- add the SG-03 feature to `tools/ledger-observatory/docs/proof-of-done.md` (index
  entry) + `docs/verification/render-skill/` (per-feature design/log), without touching the
  01/02 canonical content.

## After state

- `uv run ledger render kit_runs --surface terminal` prints a phone-legible code-block
  table/bar reply. (Today: no such command exists; the operator would have to hand-format
  `ledger show`'s raw JSON.)
- `uv run ledger render kit_runs --surface artifact --out /tmp/ledger.html` writes a
  self-contained, CSP-safe HTML file the Artifact tool can publish as-is.
- `tools/ledger-observatory/skill/SKILL.md` exists, frontmatter carries the required
  trigger phrases, and documents the surface-selection rule + install path.
- `bash tests/test-render-skill.sh` is green, including a negative control proving both
  surfaces render from the identical `rows` object (no divergent second data path).
- A captured terminal-render sample + Artifact HTML sample exist under
  `docs/verification/render-skill/samples/`.

## Acceptance Criteria (global)

| # | Criterion (measurable) | Verify |
|---|---|---|
| AC1 | the skill's frontmatter description contains the required trigger phrases | T3/R-trigger |
| AC2 | `render.py`'s functions accept a mocked JSON list-of-dict input (no live ledger/DuckDB needed) and produce a formatted surface, proving they never re-read a source | T3/R-queries-via-02 |
| AC3 | `render_terminal` output is a `bot-reply-formatting`-shaped code-block table (fenced, right-aligned numerics where present) | T3/R-terminal |
| AC4 | `render_artifact` output is a complete, self-contained `<!doctype html>` document (no external `<script src=http...>`/`<link href=http...>`) | T3/R-artifact |
| AC5 | single-data-path NC: `render_terminal(rows)` and `render_artifact(rows)` called with the SAME `rows` object both contain the same fixture cell value verbatim | T3/R-nc |
| AC6 | a real terminal-render sample + a real Artifact HTML sample are captured on disk | T4 |
| AC7 | SG-03 is indexed in the multi-feature proof (`docs/proof-of-done.md`) without overwriting 01/02's canonical content | T7 |

## Verification

```bash
cd ~/workspace/<owner>/ops-toolkit/tools/ledger-observatory
uv run ledger rebuild
uv run ledger render kit_runs --surface terminal
uv run ledger render kit_runs --surface artifact --out /tmp/ledger-sample.html
bash tests/test-render-skill.sh
```

## Test plan

`tests/test-render-skill.sh`, mirroring SG-02's fixture-driven, hand-verified-value style
(`tests/test-ledger-cli.sh`).

| Case | Category | Asserts (hand-verified) | AC |
|---|---|---|---|
| R-trigger | trigger-fires | `grep`/parse `skill/SKILL.md`'s YAML frontmatter `description:` field for each of the required trigger phrases ("show me the ledger state", "my debt", "telemetry", "token cost") , all present | AC1 |
| R-queries-via-02 | queries-via-02 | feed a hand-written mocked `list[dict]` (matching real `ledger ... --json` shape) directly into `render.render_terminal`/`render_artifact` (no CLI, no DuckDB) , both succeed and no source file/db is touched (nothing to touch, by construction) | AC2 |
| R-terminal | terminal render | `render_terminal(fixture_rows, "T")` output is fenced (triple backtick or matches the CLI's own box-table framing), contains every fixture row's known value, no line exceeds the 32-cell heuristic width bound (or explicitly documents a wider table's necessary width) | AC3 |
| R-artifact | Artifact render | `render_artifact(fixture_rows, "T")` output starts with `<!doctype html>`, contains a `<style>` block (no external stylesheet link), contains every fixture row's known value | AC4 |
| R-nc | single-data-path NC | construct ONE `rows` object; call BOTH render functions with it; assert a specific fixture cell value (e.g. a distinctive `rid`) appears verbatim in BOTH outputs; then mutate a copy of `rows` and confirm the mutation appears in a re-render (proves the functions genuinely read from the passed object, not a cached/independent source) | AC5 |

COVERAGE-DELTA: covered , trigger-phrase presence, pure-function correctness on a mocked
JSON input (the queries-via-02 contract), both surface shapes, the single-data-path NC.
Uncovered , live Discord/Telegram rendering (the skill only ever runs inside a Claude Code
terminal reply, not an actual bot; `bot-reply-formatting`'s Discord embed anatomy is
referenced for cell-budget/bar-fill discipline only, not literally invoked); the Artifact
tool's actual publish step (that call can only be made by the live agent, not this test
harness); large-row-count performance (fixtures are small, matching SG-02's own scope).

## Edge Cases

- Empty result set (`rows == []`) , both render functions produce a "(0 rows)" placeholder,
  not an exception or blank output.
- A column value is `None`/null , rendered as an empty cell (terminal) / empty `<td>`
  (Artifact), not the literal string `"None"`.
- A column value contains `<`, `&`, or `"` (e.g. a learned-ledger item with a raw angle
  bracket) , `render_artifact` HTML-escapes it so it renders as literal text, never breaks
  the table markup or injects an element.
- A very wide table (many columns) for `--surface terminal` , the SKILL.md documents that
  a wide result should prefer `--surface artifact` (an HTML table scrolls; a phone-width
  code block cannot); `render_terminal` does not attempt to reflow, it is allowed to be
  wide, the SKILL.md's surface-selection rule is what steers the operator away from it.
- `NAME` and `--query` both given, or neither , CLI exits non-zero with a clear usage
  error (mirrors `show`'s existing name-validation pattern).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `ledger render` invoked before `ledger rebuild` (fresh host, no db) | `materialize.show`/`query`'s existing lazy-rebuild-on-missing (SG-02) already covers this; no new behavior needed | none needed, inherited |
| Skill not yet installed (`~/.claude/skills/ledger-observatory/` missing) | the skill simply never fires (Claude Code silently has no matching skill) | documented in README install section; SG-05's no-orphan check is the real gate |

## Out of Scope

- The `ledger` CLI's read/query/rebuild logic itself (SG-02, already shipped).
- The anomaly/feedback loop that proposes `work-intake` rows (SG-04).
- The full README/proof-of-done polish pass + no-orphan wiring verification (SG-05).
- Actually installing the skill into `~/.claude/skills/` or any dotfiles-managed path
  (doc-only install pointer this PR).
- A live Discord/Telegram bot integration (the skill is a Claude Code in-session render
  only; `bot-reply-formatting` is referenced for its terminal code-block discipline, not
  its Discord-embed machinery).

## Decision Log

- DEC-001: render logic lives in a new pure-function module (`render.py`) with zero I/O,
  rather than inline in the CLI command or inline in SKILL.md prose, so the single-data-path
  NC is a structural property (one object, two functions) testable without DuckDB.
  Alternatives rejected: formatting inline in `cli.py` (harder to unit-test without a live
  db); formatting instructions left entirely to SKILL.md prose for the agent to improvise
  (not deterministic, not testable, risks per-invocation drift between the two surfaces).
- DEC-002: the CLI's `render` subcommand reuses `materialize.show`/`query` verbatim (same
  functions SG-02 already ships) rather than adding a second query path. Implements: T2.
- **Build:** `render.py` has no imports from `materialize`/`adapters`/`duckdb` (structural
  read-only guarantee for the render layer, mirroring SG-02's read-only-by-contract shape
  one level up). Implements: T1.

## Review

- **spec-validate (6 lenses, 2026-07-04, headless self-run , no interactive reviewer
  available):** VERDICT VALIDATED. Blocking lens (Reviewer 6, design-record): PASS , the
  `## Design` block is non-empty, carries a mermaid flowchart, names the chosen approach.
  One advisory finding folded in before Build (Reviewer 1, security): `render_artifact` did
  not specify HTML-escaping of cell values , a ledger row containing `<`/`&`/`"` could break
  the generated table markup. Fixed: Technical Design's Interfaces + Edge Cases + T1
  acceptance now mandate `html.escape` on every interpolated value. Reviewers 2-5 (failure
  modes, assumptions, scope, solution-design/extensibility): no findings , failure modes
  table is real (2 classes, both inherited from SG-02's existing lazy-rebuild + read-only
  guard, not hand-waved); no unstated assumptions beyond what's already named; tasks are
  atomic (each <=2 files, single sentence, <=4 AC bullets); the pure-function split (DEC-001)
  is the simplest design that makes the single-data-path NC structural rather than
  documentation-only.
- **Build-time self-review (2026-07-03):** caught SKILL.md's frontmatter `description:`
  containing an unquoted colon inside the YAML plain scalar (twice), which made the
  frontmatter fail to PARSE as YAML at all , invisible to the grep-based R-trigger test
  cases (they only check substring presence, not document validity). Fixed by rewording
  to the repo's " , " separator style; added a permanent `R-trigger frontmatter parses as
  valid YAML` regression case. Detail: `docs/verification/render-skill/render-skill.md`
  "Self-review finding" + `docs/implementation-notes/lo-03-render.md`.

## Open questions

None blocking.
