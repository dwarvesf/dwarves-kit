# SPEC-200: signal pipelines, one shape

Status: Draft · 2026-07-14 · Owner: Han

## Problem

The kit has **19 pipelines shaped like collect -> analyze -> report -> propose**
(full inventory in the Appendix). They read different sources (run ledger, CC
transcripts, boards, git, the filesystem) at different depths (awk, DuckDB,
heuristics, LLM), and that variety is legitimate. What is not legitimate is that
each one invented its own vocabulary, its own artifact naming, its own env-var
family, and, in two cases, its own proposal shape. They are all ETL. Nothing
says so, so nothing keeps them aligned, and every new pipeline forks the
convention again (`session-audit`, added this week, invented a third proposal
currency before this audit caught it).

The kit is about to go public. A new operator meets five different verbs for
"generate a dated status document", three env-var families addressing the same
two files, and a `session report` that does something entirely different from
`session observe report`. Fragmentation that a solo author tolerates becomes a
support burden the moment other people adopt it.

Verified evidence (each re-checked by hand, not taken from a report):

| # | Finding | Evidence |
|---|---|---|
| 1 | `_meta/backlog-staging.md` is addressed by TWO env families: `CC_BACKLOG_STAGING` (stats) and `BACKLOG_STAGE_STAGING` (board, learn, hooks, session-audit). `_meta/BACKLOG.md` by THREE (`+BACKLOG_FILE`). The `CC_*` prefix is explicitly banned by the kit's own naming invariant and was already renamed once (`docs/verification/kit-foldin-hooks.md`); `lib/stats` entered the kit later and reintroduced it. | `rg -n "CC_BACKLOG" lib/stats/src/stats/anomalies.py` -> lines 13, 631, 635, 647, 731 |
| 2 | `session report` (a vps-mon heartbeat POST) and `session observe report` (a terminal usage table) are different tools sharing a verb one level apart in the same collapsed CLI. ADR-0034's collision audit only checked top-level `bin/<name>`, not verbs. | `session.sh report --help` -> `usage: session-report [--url ...]`; `session.sh observe report --help` -> `usage: session-observe ...` |
| 3 | `queue.sh` does not source `kit-log-dir.sh` (SPEC-097's single resolver) and defaults its journal straight into `~/.claude/dwarves-kit/logs`, the exact reinstall blast zone SPEC-097 exists to escape. | `rg -c kit-log-dir lib/queue/queue.sh` -> no match; `queue.sh:71` |
| 4 | Three unrelated dated-artifact conventions for one concept: `audit-YYYY-MM-DD.md`, `intel-YYYY-MM-DD.md`, `RETRO-[date].md`. No shared helper. | the three writers |
| 5 | Two proposers never reach the staging buffer the Learn gate reads: `session intel synthesis`/`repeat` (bullet prose inside its digest) and `/kit:retro` action items (checkbox list in RETRO-*.md). README claims "every automated leg ends at a staging file". | `session-intel:202-217`, `commands/retro.md:102-104`, `README.md:76-78` |

## Solution

Name the class, then enforce four invariants on it. **Signal pipeline** = any
tool that reads a signal source, analyzes it, and emits a report and/or a
proposal. The five legs (ADR-0034) stay the loop; this spec is the shape of the
things that ride the Observe and Learn legs.

Taxonomy (source x depth), so a new pipeline knows where it belongs instead of
inventing a name:

| | deterministic | LLM |
|---|---|---|
| **run ledger** (process) | `lane-telemetry`, `stats`, `mega report/review`, `proof-table-gen` | `learn propose` |
| **transcripts** (usage) | `session observe`, `session intel` | `session semantic`, `session audit` |
| **boards / repos** | `board mirror`, `verif-counts` | `cc-improve curate`, skill-curator |

### The four invariants

**I1. One proposal currency.** Every proposer ends at `_meta/backlog-staging.md`
as a `## [staged]` block rendered by `lib/learn/staging-format.py` (ADR-0034
decision 1), deduped against every staging state + the board, promoted by
`board promote`. No tool prints its own row shape, and no tool writes a board
directly. Two offenders today (finding 5): `session intel` and `/kit:retro`.
Proposal-only prose inside a digest does not count as a proposal; it is a lead
that nobody will ever action.

**I2. One env-var family per resource, function-named.** A resource has ONE
canonical env name; the kit's existing invariant (function-named, never
host-agent-prefixed, `docs/verification/session-cli-rename.md`) settles the
form. `BACKLOG_STAGE_STAGING` / `BACKLOG_STAGE_BACKLOG` win (4 consumers vs 1;
already the enforced name). `CC_BACKLOG_*` becomes a deprecated alias that
warns; `BACKLOG_FILE` (board's own render engine) stays, documented as the
board-render knob, not a staging knob. Enforcement is a lint, not a review
habit, because finding 1 and the `CC_SI_*` holdout are the same failure twice:
renamed once, in one PR, not mechanically.

**I3. One durable root.** Every pipeline that persists anything resolves its
path through `lib/telemetry/kit-log-dir.sh` (SPEC-097). `queue.sh` joins the
named consumer list (finding 3). Dated artifacts follow ONE pattern,
`<kind>-YYYY-MM-DD.md`, emitted by a shared helper, so `RETRO-[date].md`
normalizes to `retro-YYYY-MM-DD.md` (with the old name symlinked for one
release).

**I4. One verb per meaning.** The closed verb vocabulary for signal pipelines:

| verb | means | today's offenders |
|---|---|---|
| `run` | do the pipeline's whole job, write its artifact | (ok: intel, audit) |
| `show` | print an analysis to the terminal, write nothing | `stats query/render`, `lane-telemetry report`, `session observe report` all mean this under different names |
| `propose` | stage proposals into the staging buffer | `stats anomalies --propose` (a flag), `session audit triage` (a synonym) |
| `promote` | the human gate: staging -> board | (ok: `board promote`) |
| `trace` | one run's full story | (ok) |

`report` is retired as a verb (it means both "print a table" and "POST a
heartbeat" today, finding 2): `session report` becomes `session heartbeat`,
`session observe report` becomes `session observe show`. `triage` becomes
`propose` (one word per meaning, ADR-0034 decision 2).

### Migration (back-compat, no flag day)

Every rename ships as: new name canonical, old name an alias that works and
prints a one-line deprecation to stderr, removed one release later. Nothing
breaks on upgrade; the deprecation line is what drives the cleanup.

## Tasks

| # | Task | Owner | Gate |
|---|---|---|---|
| T1 | `stats` reads `BACKLOG_STAGE_*` first; `CC_BACKLOG_*` deprecated alias + stderr warn. Registry rows updated. | stats | test: both names resolve; alias warns |
| T2 | Env-name lint: a test that fails on any new `CC_*`-prefixed env in `lib/` (catches finding 1 and the `CC_SI_*` holdout mechanically) | gate | negative control: adding `CC_FOO` fails the suite |
| T3 | `queue.sh` sources `kit-log-dir.sh`; journal lands under the durable root | queue | test: `KIT_LEDGER_DIR` moves the journal |
| T4 | `session report` -> `session heartbeat`; `session observe report` -> `session observe show`; aliases warn | session | test: both spellings work, alias warns |
| T5 | `session audit triage` -> `session audit propose` (alias warns) | session | smoke |
| T6 | `session intel` synthesis/repeat proposals stage as `## [staged]` blocks instead of digest prose | session | test: proposals land in staging, deduped |
| T7 | `/kit:retro` action items stage as blocks (the retro doc keeps its prose; the ACTIONS also stage) | commands | test |
| T8 | Shared dated-artifact helper; `RETRO-[date].md` -> `retro-YYYY-MM-DD.md` | gate | test |
| T9 | This taxonomy + the four invariants land in `docs/architecture.md` + the module-registry preamble, so the NEXT pipeline follows them | docs | doc-verifier |

Order: T1-T3 first (they are the ones that silently misconfigure a public
adopter), T4-T5 next (surface names, cheap), T6-T7 (real behavior change,
needs care), T8-T9 last.

## Non-goals

- **Merging the pipelines.** They read different sources at different costs;
  three weekly digests is a real smell, but the fix is I1/I4 (one currency, one
  vocabulary), not one mega-tool. Fold `session audit`'s report into `session
  intel` as a SOURCE only if the operator later finds two files annoying.
- **A shared ETL framework/base class.** The pipelines are bash, python, DuckDB
  and LLM calls; a common abstraction would be a cage. The contract is the
  invariants, not an inheritance tree.
- **Renaming `stats`, `learn`, `board`.** Module names are settled (ADR-0034).

## Verification

Each task carries its own test above. The spec-level check is a lint suite:
env-prefix lint (T2), a verb-vocabulary lint over `lib/*/bin/*` help text (T4),
and a proposal-currency test asserting every proposer writes staging blocks and
nothing else (I1).

## Appendix: the 19 pipelines

lane-telemetry · learn propose · learn drain · learn debt · stats · mega report
· mega review · skill-curator reviewer · cc-improve curate · board mirror /
writeback · session observe · session report · session semantic · session intel
· session audit · proof-table-gen · verif-counts · /kit:retro · /kit:kit-health

Full source/transform/output/proposal/cadence table: `docs/verification/signal-pipeline-inventory.md`.
