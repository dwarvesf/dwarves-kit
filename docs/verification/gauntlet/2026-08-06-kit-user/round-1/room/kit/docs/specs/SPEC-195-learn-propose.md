# SPEC-195: learn propose (ledger -> cited, deduped, adversarially-checked backlog proposals)

Status: VALIDATED (spec-validate run 2026-07-12; findings folded: dedup-before-adversarial
ordering, empty-figure grounding, rid fallback, figure sanitization, degrade behavior,
COVERAGE-DELTA, guard-stays-stronger config amendment)
Lane: normal
Backlog: harness-loop sub-goal 05 (`_meta/megagoals/harness-loop/goals/05-retro-cycle.md`), the mega's keystone
Branch: feat/loop-05-retro-cycle
Relates-to: ADR-0034 (taxonomy: `learn` subsystem, decisions 1/2/5/6), SPEC-182 (stats
plane, the read engine this consumes), SPEC-184 (`bin/learn` stable entry), SPEC-144
(anchored-dedup lesson, `docs/implementation-notes/spec-144-review-findings-memory.md`),
SPEC-188 (reserved-keys guard, amended here), SPEC-110 (`TOKENS` marker),
`docs/research/2026-07-05-auto-improvement-loop-design.md` (the architecture, verbatim)

## Problem

The harness collects a lot of ledger telemetry (gate outcomes, proof records, run
durations, deviations, anomalies, memory staleness, session events). Today that data is
READ for display (`stats` lenses, `RUN_REPORT`) and for one deterministic proposer
(`stats anomalies --propose`, fixed thresholds). What is missing is the cross-run
INTERPRETATION layer the 2026-07-05 design calls for: a retro one level up from
`/kit:retro` (which reads ONE run) that reads MANY megas, asks "what pattern is the data
telling us to fix?", and emits candidate backlog rows a human triages.

`learn propose` is that layer. It is `propose`-only (ADR-0034 decision 2/5): its ONLY
legal sink is the staging file; it never writes a board, never rewrites a ledger, never
edits kit/skill/CLAUDE.md. The discipline IS the feature. An ungrounded "maybe improve X"
reaching the staging file is a P0 defect; a rejected proposal reappearing next week kills
the loop's credibility permanently.

## Design

Three stages, each cheap, mirroring the research doc's diagram (ledger -> stats aggregate
-> LLM interpretation -> backlog).

### Stage 1: Aggregate (deterministic, no LLM)

Run the `stats` lenses over a WINDOW (`--days N`, default 30; `--megas N` alternative) and
build a **signal table**. Each signal is `{id, lens, figure, rids, detail}` where `id` is a
stable label (`S1`, `S2`, ...), `lens` names the source, `figure` is the observed number,
`rids` is the window's covered run-ids, `detail` is the raw lens row. Pure projection.

Signal sources (each lens failing independently contributes zero signals, never aborts the
aggregate -- this is what makes the honest-empty NC hold):

- `bin/stats anomalies --json` -> one signal per fired anomaly (`figure` = its `metric`).
- `bin/stats gate-yield --json` -> per-gate override/skip figures above a floor.
- `bin/stats deviation-rate --json`, `review-yield --json`, `defect-correlation --json`
  -> their headline figures.
- `bin/stats memory-sweep --json` -> the staleness/dead-path counters SURFACED as cited
  signals (e.g. "12 memory notes reference dead paths, 4 stale >180d"). Memory REPAIR
  stays OUT (ID-100 owns context-lifecycle); this is the weekly tripwire only.
- **Starvation counters (surfaced, never processed):** `bin/learn debt list` count; the
  learned-ledger queued count + oldest-entry age (via `STATS_LEARNED_MD`, skip-safe when
  unset kit-side).

Window rids come from a read-only `bin/stats query` over `kit_gates`/`kit_runs`; on any
failure, rids degrade to the empty list and the aggregate still emits (honest-empty).

### Stage 2: Interpret (ONE `claude -p` sonnet pass, grounded)

One pass turns signals into hypotheses. The prompt gets ONLY the signal table + the board
and staging content (for dedup awareness), nothing else. Output: a JSON array of
`{title, intent, approach, u, f, home, signal}` where `signal` is the id of the ONE
aggregate signal the hypothesis rests on. The LLM call is isolated behind
`LEARN_PROPOSE_INTERPRETER` (default `claude -p --model sonnet --setting-sources project`),
mirroring `backlog-stage.py`'s `BACKLOG_STAGE_EXTRACTOR` seam, so the dedup/stage/adversarial
logic is testable without a live model.

**Anti-fabrication invariant (the P0 guard):** the citation printed in a staged block is
REBUILT from `aggregate[signal].{lens, figure, rids}`, never taken from the model's prose.
The model chooses WHICH signal a proposal rests on; it cannot inject a fabricated figure,
because the figure is looked up by id from the deterministic aggregate.

This pass emits its token cost via the existing `TOKENS` marker
(`gate-ledger.sh tokens <rid> in=N out=N`), so the weekly cycle's spend is observable in
`stats`.

### Stage 3: Adversarial check + deterministic staged write

Per hypothesis, in order (the two cheap deterministic anchors run BEFORE the per-hypothesis
LLM pass, so a duplicate never burns a model call -- minimal, observable spend):

1. **Deterministic grounding check.** The cited `signal` id MUST exist in the aggregate
   AND its `figure` MUST be non-empty. A hypothesis with a missing/unknown signal ref, OR
   one citing a present-but-empty-figure signal, is DROPPED here (both are "not evidence").
   This is the anchor that makes the adversarial-check NC robust (a planted proposal citing
   a fabricated or empty signal is dropped without depending on LLM judgment).
2. **Dedup HARD (anchored).** The proposal's normalized-title key is tested for EXACT
   membership in a set built from open board rows AND staged AND `[expired]` AND
   `[rejected]`/`[promoted]` blocks. Exact-set membership is the anchored form (per the
   SPEC-144 lesson): a short key is never wrongly matched as the suffix of a longer
   rejected one, because no substring/containment test is ever used (`existing_keys()`
   builds a discrete `set()`, never a text-blob scan). Duplicate -> DROPPED.
3. **Adversarial refute pass** (claim-verifier pattern, refute-if-uncertain). A `claude -p`
   pass, isolated behind `LEARN_PROPOSE_VERIFIER` (default
   `claude -p --model sonnet --setting-sources project`), is handed the surviving proposal +
   its real (aggregate-sourced) signal and asked to REFUTE if the proposal is not a supported
   inference from that signal, is overstated, or cannot be verified. Default to `REFUTED` on
   any doubt (fail-closed); an empty/garbled/errored verdict is also treated as REFUTED.
   `REFUTED` -> DROPPED. Emits a `TOKENS` marker.
4. **Staged write.** Survivors are appended as `## [staged] <title>` blocks in the exact
   byte-format `board promote` / `learn drain` parse (`## [staged]` header, `- Intent:`,
   `- Approach:`, `- Tags:`, `- Source:`, optional `- Home:`, trailing blank line). The
   citation rides the `- Source:` line: `learn propose <date> | lens=<lens> figure="<figure>"
   rids=<r1,r2>` -- ONE line: `figure` is normalized single-line (`|`, `\n`, `\r` -> space)
   before interpolation so a multi-line lens figure can never split the block or truncate the
   `rids=` tail. Carried into the board Notes column on promote, so every staged (and every
   promoted) row cites lens + figure + rids.

**Degrade behavior (honest-empty everywhere).** Each of the three subprocess seams degrades
safely: a failing stats lens contributes zero signals (Stage 1); a crashing/timing-out/
malformed interpreter yields zero hypotheses (Stage 2); a failing verifier fails closed
(drop). Any of them empty -> 0 candidates, staging untouched, exit 0.

**Rid for the TOKENS markers.** `gate-ledger.sh rid` exits non-zero on `master`/detached HEAD
(SPEC-070), and `gate-ledger.sh tokens` refuses an empty rid. So `learn propose` resolves its
rid as `LEARN_PROPOSE_RID` env -> `gate rid` (when it succeeds) -> a branch-independent
`learn-propose-<date>` slug, so TOKENS always lands (incl. the weekly cadence, which runs
before any goal branch exists). A test exercises the fallback.

### Shared staging-block format (lands here per the shared-fixture rule)

SG-05/SG-06 share ONE definition of the staged-block edges. As the first of the two to
merge, THIS spec lands `lib/learn/staging_format.py`: `render_block(candidate)` (byte-identical
to `hooks/backlog-stage.py:render_candidate` / `anomalies.py:render_block`), `parse_blocks(text)`
(next-`## [`-header-delimited, matching `add-backlog.parse_staging`), `norm(title)`, and
`existing_keys(staging, backlog)`. `learn drain` (SG-06) consumes the same helper. A fixture
+ round-trip test pins the block edges.

### Config + lint

`[features] auto_improvement` flips `[design]` -> `[impl]` in `kit.toml` (the
auto-improvement machinery is now built). It stays a status marker with the value defaulting
`false` (the manual `bin/learn propose` command is always available; the automatic WEEKLY
cadence is opt-in and gated consumer-side by SG-10, never kit-side -- PHILOSOPHY: no kit-side
auto-loop). No kit-side `kit_config_get features.auto_improvement` read is added. The SPEC-188
lint amendment is minimal and keeps the guard STRONGER: `auto_improvement` STAYS in the
no-live-path set (that assertion now enforces a live invariant -- an `[impl]` flag that must
never be read kit-side -- not merely a not-built one), and ONLY its status-tag assertion
flips `[design]` -> `[impl]`. `learning_ledger` stays `[consumer]`, `team.*` stays inert
`[design]`.

### The recurring vehicle

The drafted kit-retro contract moves into this mega (ADR-0034 decision 6) as a goal TEMPLATE
under `_meta/megagoals/harness-loop/goals/kit-retro.md` (< 4000 chars): the three steps
(READ ledger/queries/NOTES -> DISTILL via `learn propose` -> STAGE cited candidates), a state
line (`last retro: <date>`), and the `RUNNER_DONE` / `RUNNER_GATED:` markers so it drains as a
normal queue row. The weekly consumer LaunchAgent (SG-10) instantiates it as `kit-retro-YYYY-WW`
(the date-suffix IS the recurrence; zero queue-engine changes).

## Scope

**In:** `lib/learn/propose.py` (3 stages + surfacing counters), `lib/learn/staging_format.py`
(shared helper), the `learn.sh` `propose)` arm (the one file touched outside the literal
`propose*` glob -- it is the propose verb's dispatch wiring, within the fence's spirit), the
kit-retro goal template, the kit.toml features flip + SPEC-188 lint amendment
(`tests/test-reserved-config-guard.sh`; the goal's `tests/test-config-reserved-keys*` glob
names the same file), `tests/test-learn-propose.sh`, SPEC-195.

**Out:** the LaunchAgent plist (SG-10), `board promote` / `add-backlog` changes (SG-06 owns
`learn drain` + `[expired]`), Hermes cards.

**Not:** auto-promotion in ANY form; editing kit/skills/CLAUDE.md from the cycle; a second
ledger; per-run retro changes (`/kit:retro` untouched); memory repair (ID-100 owns it).

## Acceptance criteria

1. `bin/learn propose` runs the three stages and, given signals + a mocked interpreter,
   writes only grounded, non-refuted, non-duplicate survivors to the staging file as
   byte-format `## [staged]` blocks whose `- Source:` line cites lens + figure + rids.
2. **Honest-empty:** an empty window (no signals) stages 0 candidates, leaves the staging
   file untouched, prints a "0 candidates" line, and exits 0.
3. **Idempotency:** an immediate re-run against the same window stages nothing new (dedup
   against the just-written staged blocks).
4. **Adversarial-check drop:** a hypothesis citing a fabricated/unknown signal is dropped by
   the deterministic grounding check; a hypothesis the verifier REFUTES is dropped. Neither
   reaches staging.
5. **Anchored dedup (SPEC-144 Run-3 mirror):** a new proposal whose normalized key is a
   SUFFIX of a longer already-`[rejected]` key is NOT wrongly deduped; an exact-key
   duplicate IS deduped.
6. Both LLM passes emit `TOKENS` markers to the run ledger.
7. `kit.toml` `auto_improvement` is `[impl]`; `tests/test-reserved-config-guard.sh` is green
   with the amendment (the flag STAYS in the no-live-path guard, enforcing "never read
   kit-side"); `team.*` stays inert.
8. The kit-retro goal template exists, `wc -m < 4000`, and carries the three steps + state
   line + `RUNNER_DONE`/`RUNNER_GATED:` markers.
9. TOKENS lands even when `gate rid` fails (master/detached): the rid falls back to a date
   slug.
10. Full suite green (`bash tests/test-hooks.sh`, `bash tests/test-meta.sh`, the new
   `tests/test-learn-propose.sh`, the amended `tests/test-reserved-config-guard.sh`).

## Test plan

| Category | Case | How |
|---|---|---|
| Happy path | grounded hypothesis -> staged block with cited Source | mocked interpreter returns a hypothesis citing S1; assert block written + Source cites lens/figure/rids |
| Honest-empty | empty aggregate -> 0 candidates, file untouched, exit 0 | run with no ledger data; assert staging unchanged + exit 0 |
| Idempotency | re-run stages nothing new | run twice with same mocked interpreter; assert second run adds 0 blocks |
| Grounding drop | hypothesis cites unknown signal id -> dropped | mocked interpreter cites S99; assert not staged |
| Empty-figure grounding | hypothesis cites a present-but-empty-figure signal -> dropped | inject a signal with `figure:""`; assert dropped ungrounded |
| Adversarial drop | verifier REFUTES a grounded hypothesis -> dropped; garbled verdict fails closed | mocked verifier returns REFUTED / a non-verdict; assert not staged |
| Anchored dedup | suffix-key not deduped; exact-key deduped | seed staging with a `[rejected]` long-key block; assert a suffix-key proposal survives, an exact-key proposal drops |
| Figure sanitization | a multi-line / pipe-laden figure stays one Source line | inject `figure:"a\nb \| c"`; assert one block, rids not truncated, round-trips |
| Subprocess degrade | a crashing interpreter -> honest-empty, exit 0 | interpreter exits 1; assert 0 candidates + exit 0 |
| Rid fallback | TOKENS land when `gate rid` fails | break the gate path; assert `_rid()` returns the date slug |
| Format round-trip | render_block -> parse_blocks recovers fields | staging_format unit round-trip |
| add-backlog compat | a staged block parses under `add-backlog.parse_staging` | render a block, run the (unmodified) parser, assert one staged row |
| TOKENS | both passes emit a `TOKENS` line | assert two `| TOKENS |` lines in the run log |
| Lint | amended reserved-config guard green | `bash tests/test-reserved-config-guard.sh` |

## Verification

```bash
bash tests/test-learn-propose.sh
bash tests/test-reserved-config-guard.sh
bash tests/test-hooks.sh
bash tests/test-meta.sh
# LIVE run against the real XDG ledgers (proof-of-done):
bin/learn propose --days 30
```

The proof-of-done (`docs/verification/loop-05-retro-cycle.md`) carries: a run-table; ONE
recorded LIVE run of `bin/learn propose --days 30` with the staged diff captured (every block
citing lens + figure + rids); the honest-empty / idempotency / adversarial-check NCs; a
**COVERAGE-DELTA** row (over-test: this SG adds the `learn propose` behavior surface -- the
3-stage pipeline + the shared `staging_format` helper + the config flip; prior coverage of
those = 0); and a fresh-context `kit:recheck-verifier` re-execution of the LIVE-run command.

Done = live run + all NCs + amended lint green + goal template < 4000 chars + COVERAGE-DELTA
row + a fresh-context recheck-verifier PASS, all captured in the proof-of-done.
