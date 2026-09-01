# Spec: estate runs dashboard + visual-first proof contract
Generated: 2026-07-31
Status: DRAFT
Lane: normal
References:
- `lib/mega/mega-review.py` -- the shipped per-mega HTML sign-off dashboard (SPEC-197). Imitate its render helpers directly (`_CSS`, `_e`, `_run`) by import, and its honest-dash discipline: an absent source renders "-", never a fabricated zero.
- `lib/sync/cockpit.py` -- `repo_root_of()` maps a registered `BACKLOG.md` path to the repo root that holds `_meta/megagoals/`. Imitate the registry-driven estate walk, not a hardcoded path list.
- `lib/gate/proof-table-gen.py` -- the cross-subsystem `importlib.util.spec_from_file_location` sourcing convention `mega-review.py` itself uses. One parser, many consumers.

## Problem

Proof of what the factory shipped is markdown, scattered. A RUN_REPORT lives in one repo's `_meta/megagoals/_archive/<slug>/`, a proof-of-done lives in another repo's `tools/<x>/docs/`. Today the estate holds 17 RUN_REPORTs and 117 proof-of-done docs across the registered repos. Answering "what ran recently and did it go green" means opening N repos and reading N files. A human previews a picture in five seconds and a table in five minutes.

The pieces exist and do not compose: the per-mega sign-off dashboard (SPEC-197, shipped) covers ONE mega-goal, the bench scoreboard covers ONE bench run, and neither reads the proof docs at all.

## Solution

### Approaches considered

1. **Estate scanner into one static HTML page.** A stdlib generator walks a registry of repos, parses every run artifact into a card, renders one self-contained file. Tradeoff: parsing prose markdown is heuristic, so a card's status is a best-effort read of the document, not a ledger fact.
2. **Extend `stats` with a `runs` verb.** Semantically the Watch stage's home (ADR-0034). Tradeoff: `lib/stats/` is a uv-managed package with duckdb and typer dependencies, so a stdlib-only generator would inherit a uv requirement it does not need. Rejected on the dependency cost.
3. **Index the gate/run ledger instead of the docs.** The ledger already holds structured GATE and OUTCOME rows. Tradeoff: the ledger is machine-local and per-rid, it carries no titles, no captures, and nothing from repos that never ran a kit gate. It answers a different question. Rejected as a v1 source.

### Chosen approach + why

Approach 1. The corpus that a human wants to see is the corpus of authored reports, not the ledger. Approach 3 is a later panel, not this one. Approach 2 loses the bare-`python3` property that the shipped ancestor has.

### Extensibility & boundaries

- **Load-bearing dimension: number of run artifacts, and total capture bytes.** The page is one HTML file with base64-embedded thumbnails. At today's ~134 documents the page is small; the cost that grows is embedded image bytes, so the generator carries a per-image cap and a total budget, and degrades an over-cap capture to a plain link with an honest label. When the estate outgrows one page, the split axis is repo, not date.
- **Unit boundaries.** Four units, each testable alone: registry resolution (text to roots), artifact discovery (roots to file paths), card extraction (one file to one card), page render (cards to HTML).

### Architecture

See `## Design`.

## Design

### Approaches considered + chosen

See `## Solution` above. The design view adds one tradeoff the solution view did not: how much of `mega-review.py` can be reused.

### Diagram

ASCII, per the repo's no-mermaid rule.

```
  _meta/boards.txt                      lib/mega/mega-review.py
  (or --root DIR, repeatable)            _CSS   _e()   _run()
        |                                     |
        v                                     | import (same convention
  +-------------------+                       |  mega-review.py uses for
  | resolve_roots()   |                       |  proof-table-gen.py)
  +-------------------+                       |
        | repo roots                          |
        v                                     |
  +-------------------+                       |
  | discover()        |  <_meta/megagoals/**/RUN_REPORT.md>
  |                   |  <**/docs/proof-of-done.md>
  |                   |  <docs/verification/**/runs/*.md>
  +-------------------+                       |
        | file paths                          |
        v                                     |
  +-------------------+   reads sibling       |
  | extract_card()    |-->  PNG/GIF/MP4       |
  | title date status |   referenced by       |
  | captures receipts |   the document        |
  +-------------------+                       |
        | Card records                        |
        v                                     v
  +--------------------------------------------------+
  | render_page()   ONE self-contained index.html     |
  |  card grid, newest first, grouped by repo         |
  +--------------------------------------------------+
```

### ADR link(s)

ADR-0034 (subsystem-verb grammar) is the decision this build touches. It assigns `mega` to the Build stage and `stats` / `session` / `telemetry` / `bridge` to Watch. This spec lands a Watch-shaped verb on `mega`. That is a deliberate, recorded deviation, not an oversight: see DEC-001. No new ADR is written, because the decision is reversible (the verb can move to `stats` the day `stats` stops needing uv) and ADR-0034 decision 3 already establishes the "honest spanner" pattern for a subsystem whose verbs cross stages.

### Boundaries & failure modes

The generator only reads. It writes exactly one output file. It never writes into a scanned repo, never runs `git` against a scanned repo except through the imported `repo_root_of`, and never touches the network. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- **Inputs / consumes.** A registry file in the existing `boards.txt` format (`<name>  <path-to-BACKLOG.md>  [bridge]`, `#` comments, `~` expands). Unlike the sync cockpit, the dashboard reads EVERY row, not just `bridge == on` rows: the bridge flag opts a repo into a Hermes write path, which has nothing to do with reading its reports. Alternatively one or more `--root DIR` arguments, which bypass the registry entirely.
- **Outputs / produces.** One HTML file at `--out` (default `runs-dashboard.html` in the cwd). Exit 0 on a successfully written page, including an empty-state page. Exit non-zero only on an unwritable output path or a malformed argument.
- **Invariants.** (1) The page is self-contained: no external stylesheet, script, font, or image URL. (2) A card is never fabricated: every card corresponds to a file that exists on disk. (3) An absent field renders as an honest dash or an explicit "no captures" label, never a zero or a placeholder image. (4) The generator is idempotent: same inputs, same page except the generated-at stamp.

### Data model changes

None persisted. The `Card` record is in-memory only, matching the SPEC-182 and SPEC-197 discipline that a projection stores nothing.

### API changes

None.

### UI changes

One new rendered surface: the runs dashboard page. Light background `#fafafa`, text `#111827`, borders `#374151`, one muted accent, system sans. Dark-scheme override inherited from the imported `_CSS`.

### Infrastructure changes

None. No daemon, no scheduler, no hook. The page regenerates on demand.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: `lib/mega/runs-dashboard.py` scanner: registry and `--root` resolution, artifact discovery, card extraction (title, date, repo, status, captures, receipts) -- a card is produced for every discovered file and never for a missing one.
- [ ] TASK-002: Page render reusing `mega-review.py`'s `_CSS` and `_e` by import; capture embedding as base64 data URIs under a per-image cap and a total budget, with an honest link fallback over cap and for video.

### Phase 2: Core
- [ ] TASK-003: `mega runs` verb in `lib/mega/mega.sh` forwarding to the generator, reachable as `bin/mega runs` -- flag parsing matches the subsystem's existing style.
- [ ] TASK-004: `tests/test-runs-dashboard.sh` covering the parse path and the empty-state path -- exits 0 with all cases green.

### Phase 3: Polish
- [ ] TASK-005: Visual-first proof contract wired additively into `docs/verification/README.md`, naming the ID-395 module as the producer and keeping the transcript form honest for headless work.

## After state

- [ ] `bash bin/mega runs --out <path>` writes one self-contained HTML page carrying at least one card built from a real estate artifact. (Today: no such command exists.)
- [ ] `bash bin/mega runs --root <empty-dir> --out <path>` writes a valid empty-state page and exits 0. (Today: n/a.)
- [ ] `bash tests/test-runs-dashboard.sh` exits 0. (Today: the file does not exist.)
- [ ] `docs/verification/README.md` states the visual-first rule and names its producer. (Today: it accepts a screenshot or GIF as an alternative form, but never says a visible-surface change OWES one.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover the happy path plus the edge cases listed below
- [ ] No regressions: `bash tests/test-mega-review.sh` stays green, since this build imports that module

## Verification

```
bash bin/mega runs --root . --out /tmp/rd-real.html && grep -c 'class="card ' /tmp/rd-real.html
bash bin/mega runs --root "$(mktemp -d)" --out /tmp/rd-empty.html && grep -c 'no run artifacts' /tmp/rd-empty.html
bash tests/test-runs-dashboard.sh
bash tests/test-mega-review.sh
```

The first command is the positive control: it must print a count of at least 1. The second is the negative control: an empty root must still produce a well-formed page carrying the empty-state banner, exit 0, and zero cards.

## Test plan

Script tests in `tests/test-runs-dashboard.sh`, following the existing suite's `ok`/`no` counter shape and `mktemp -d` sandbox convention.

| # | Category | Case | Expected |
|---|---|---|---|
| 1 | Parse | A `RUN_REPORT.md` with a `# Title` heading and a date line | Card carries that exact title and that date |
| 2 | Parse | A `proof-of-done.md` with no heading | Card falls back to a path-derived title, never empty |
| 3 | Parse | Document text carries `Outcome: MET` | Card status classifies green |
| 4 | Parse | Document text carries `HELD` | Card status classifies attention, not green |
| 5 | Parse | Document references a PNG that EXISTS on disk | Capture embedded as a `data:` URI, no external URL |
| 6 | Parse | Document references a PNG that does NOT exist | No capture, no broken `<img>`, card still renders |
| 7 | Parse | Document references an `.mp4` | Rendered as a link with a video label, never base64 |
| 8 | Parse | A capture larger than the per-image cap | Link fallback with the honest over-cap label |
| 9 | Parse | Document carries `#123` and a merge SHA | Both surface as receipts on the card |
| 10 | Empty state | `--root` pointing at an empty directory | Valid page, empty-state banner, zero cards, exit 0 |
| 11 | Empty state | `--root` pointing at a path that does not exist | Same empty-state page, exit 0, no traceback |
| 12 | Registry | A registry whose rows lack the `bridge` column | Every row still scanned (bridge is not a read gate) |
| 13 | Registry | A registry row pointing at a missing `BACKLOG.md` | Skipped with a stderr note, other rows still scanned |
| 14 | Self-contained | Any rendered page | No `http://`, `https://`, or `//cdn` asset reference in a `src` or `href` stylesheet slot |

## Edge Cases

1. A repo registered twice under different names: deduplicate by resolved root, so a run is never double-carded.
2. A document with no parseable date: fall back to the file's modification date and label the card's date source honestly rather than inventing one.
3. A capture path that escapes its document's directory via `..`: resolve it, and only embed when the resolved path exists and is a regular file.
4. A registry entry whose repo is on a different filesystem or is unreadable: skip it with a stderr note, never abort the whole render.
5. A document that is a template or fixture (contains `x.gif`-style placeholder references): the missing-file rule already drops those captures, so a fixture never contributes a broken image.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Page weight balloons as captures accumulate | Output file size grows past the total embed budget | Per-image cap plus total budget; over-budget captures degrade to links with an honest label, so the page stays openable |
| A prose heuristic misreads a status | A card shows green for a run that was held | Status is labelled as a document read, and every card links to its source document so a human verifies in one click |
| A scanned repo is huge or contains a deep vendor tree | Scan takes visibly long | Discovery is restricted to the three known artifact shapes under known prefixes, never a full-tree walk |

## Out of Scope

- Producing captures. That is the ID-395 visual-proof module; this build only consumes what exists.
- Enforcing the visual-first contract in a gate or hook. This build documents the contract; enforcement is a later row.
- Bench scoreboard and fleet panels (ID-421 / ID-432). Named as future panels, not built here.
- Any daemon, watcher, scheduled job, or cache.

## Touches
- lib/mega/**
- tests/**
- docs/**

## Decision Log

- DEC-001: The verb lands as `mega runs`, not `stats runs`. Rationale: the corpus is mega-goal archives plus the proof docs they point at, which is the exact corpus `lib/mega/` already parses; the generator imports the shipped sign-off dashboard's render helpers from a sibling file rather than reaching across subsystems; and it keeps the bare-`python3` property that `mega-review.py` has, which a `lib/stats/` home would trade for a uv requirement the generator does not need. Alternatives rejected: `stats runs` (drags uv, duckdb, typer onto a stdlib generator), `session runs` (the session subsystem means Claude Code sessions, not factory runs), a new top-level subsystem (a whole `bin/` entry for one verb). Honest cost: ADR-0034 files `mega` under the Build stage, so `mega` becomes a third stage-spanner alongside `board` and `session`. Recorded here rather than papered over.
- DEC-002: The dashboard reads EVERY registry row, not only `bridge == on` rows. The bridge flag opts a repo into a Hermes WRITE path; reading a repo's own reports carries none of that risk, and filtering on it would have hidden most of the estate behind an unrelated flag.
- DEC-003: `mega-review.py` is extended by IMPORT, not by parameterization. Its render loop is built around one mega's ROADMAP sub-goal rows and the per-rid gate ledger, so it has no seam that accepts an estate of unrelated documents. What genuinely transfers is the presentation contract: `_CSS`, `_e`, `_run`, and the honest-dash discipline. Those are imported through the same `importlib` convention `mega-review.py` itself uses for `proof-table-gen.py`, so there is one stylesheet and one escaper across both surfaces, not two that drift.

## Open questions

(none)
