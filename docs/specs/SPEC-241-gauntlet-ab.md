# Spec: Gauntlet A/B, bounded search-select over artifact variants

Generated: 2026-09-01
Status: VALIDATED
Lane: full
References: `commands/gauntlet.md` (the engine whose rooms/probes/records this reuses); `tests/gauntlet/cleanroom/run.sh` `GAUNTLET_SRC_TAR` slot (the variant mechanism, already shipped); `tests/gauntlet/deploy/gauntlet-campaign` (the driver idiom this mirrors); `lib/gauntlet/stats.sh` (SPEC-240, the cost tiebreak); `skills/loop-engineering/SKILL.md` bounded search-select shape + `docs/research/2026-07-31-karpathy-autoresearch-loop.md` (lineage); `_meta/BACKLOG.md` ID-496.

**Scope:** a driver over the existing gauntlet engine plus ONE engine passthrough (design-critique blocker: `run-remote.sh` now ships the caller's `GAUNTLET_SRC_TAR` as the artifact tarball instead of re-archiving HEAD; the harness copy still ships HEAD). No new store, no model judge. The metric is the row's own deterministic checker.

## Problem

The gauntlet's revise step answers "is this artifact good enough" but not "which of two artifact versions is better". When a revision is contested (two structures of an onboarding doc, two runbook layouts), the operator picks by taste. The cheap NW probe (~$0.02/round) makes an empirical pick affordable: run the same card against both variants, count checker passes.

## Solution

### Approaches considered

1. **Thin driver `tests/gauntlet/deploy/gauntlet-ab`** looping variants x rounds through the existing runner via `GAUNTLET_SRC_TAR` (chosen).
2. A new engine/command `/kit:gauntlet-ab`: rejected, the loop-engineering skill routes search-select to a wrapper over existing machinery, never a second engine.
3. Score by findings K from model scoring: rejected, campaign precedent scores rows by deterministic checker; a model judge would need the corpus bar (PHILOSOPHY "AutoResearch optimization").

### Chosen approach + why

`gauntlet-ab <ref-A> <ref-B> <persona> <row> [rounds-per-variant]` (default 2 rounds/variant): for each variant, `git archive <ref>` builds the rule-7 tarball (plain tar: GNU tar cannot auto-detect compression on the remote ship pipe), exported as `GAUNTLET_SRC_TAR`; each round runs the runner into `docs/verification/gauntlet/<date>-ab-<slug>/<A|B>/round-N/` and is scored by the row's own checker into a per-round `ab-verdict.txt` (the single source of truth and the resume key; the round DIR is pre-created by run-remote and proves nothing). Round classes: GREEN / RED count toward the tally; BLOCKED (checker exit 3, card evidence not variant evidence) and HARNESS (non-zero harness rc, infrastructure not artifact) are excluded, shown in the table, and any HARNESS round makes the driver exit non-zero. Verdict honesty: a winner requires a SWEEP (margin >= rounds-per-variant); a thinner lead is `AB-WEAK` (a tally, not a finding); an exact tie falls to the mean-probe-token tiebreak (cheaper variant wins), else `AB-TIE`. Fixed budget, no revision between rounds, losers discarded whole (all three search-select preconditions hold: deterministic metric, ~$0.02/9-min rounds, no learning from losers by design).

### Extensibility & boundaries

- Any (artifact, card) pair the gauntlet already supports; variants are git refs, so a doc-structure A/B is two branches.
- Boundary: no revision inside the loop. If the loser's transcript should teach a revision, that is the existing gauntlet bounded-revise loop, run after the pick.

## Picture

```
ref-A ──git archive──► tar-A ─┐
ref-B ──git archive──► tar-B ─┤   per variant, N rounds:
                              ▼
              GAUNTLET_SRC_TAR=tar-V run.sh ──► <date>-ab-<slug>/V/round-N/
                              │ checker GREEN/RED per round
                              ▼
            tally A vs B ──► AB-ROUNDS.md + [[AB-VERDICT ...]]
            (tie → mean probe tokens; still tie → AB-TIE honest halt)
```

## Technical Design

### Interfaces (I/O contract)

- `bash tests/gauntlet/deploy/gauntlet-ab <ref-A> <ref-B> <persona> <row> [N]`, env: `KIT_ROOT`, `PROBE_CMD` (same slot as the campaign), optional `GAUNTLET_AB_DIR` override for the pass container.
- Record: `docs/verification/gauntlet/$(date +%F)-ab-<row>-<shortA>-vs-<shortB>/` holding `A/round-*/`, `B/round-*/` (each the runner's standard persisted room + `ab-verdict.txt`), and `AB-ROUNDS.md` with: the variant refs + the FULL `git diff --stat refA refB` (the anti-gaming disclosure, never truncated), the per-class table (GREEN/scored, BLOCKED, HARNESS), the tally, marker `[[AB-VERDICT winner=<A|B|tie|weak> a=<g>/<n> b=<g>/<n>]]`. Per-round scrub/integrity is the runner's own (SPEC-236); the A/B adds the diffstat disclosure on top, nothing less, nothing more.
- Exit 0 on a decided verdict with all rounds scored; non-zero when any round was lost to harness failure (its room still persists per SPEC-236).

### Data model / API / UI / Infrastructure changes

None. New driver file + record grammar only.

## Task Breakdown

### Phase 1

- TASK-001: `tests/gauntlet/deploy/gauntlet-ab` driver (variant tarballs, round loop, scoring, AB-ROUNDS.md, resume by counting existing round dirs).
- TASK-002: live discriminating smoke: variant A = master, variant B = a scratch ref with a planted doorway-doc defect; N=1 each; expect A GREEN, B RED, winner=A.
- TASK-003: A/B mode section in `commands/gauntlet.md` (when to reach for it, the no-revision boundary, the anti-gaming disclosure rule).

## After state

- One command answers "which variant do probes succeed on" with a committed record.
- The verdict marker is greppable by `lib/gauntlet/stats.sh`-class projections later.
- A planted-defect variant demonstrably loses. At N=1 this is a plumbing smoke: it proves the tarball slot propagates the variant and the scoring path discriminates, not a statistical claim about the sampler.

## Acceptance Criteria (global)

1. Live run: A=master vs B=planted-defect ref (adopt path removed) on the doorway row, N=1 each, proves VARIANT PROPAGATION by room contents (A's persisted room carries `lib/adopt.sh`, B's verifiably lacks it) and end-to-end scoring. The expected B-RED did NOT materialize: the probe rebuilt the deleted script from the kit's own docs, a genuine finding (a single-file deletion is a RECOVERABLE defect; A/B separation needs variants that differ in what the docs can teach, not in what a probe can reconstruct). Tally discrimination is proven deterministically instead: a seeded GREEN-vs-RED verdict pair → `[[AB-VERDICT winner=A a=1/1 b=0/1]]`.
2. AB-ROUNDS.md carries the variant refs and the inter-variant diffstat (anti-gaming disclosure).
3. Interrupted run resumes on the verdict file: a round dir WITHOUT `ab-verdict.txt` (the shape a killed round leaves, since run-remote pre-creates the dir) is re-run; a scored round is never re-run.
4. Negative control: corrupt/absent checker for the row → the driver fails loud naming the checker, no verdict emitted.
5. Rule-7 integrity holds per round: the tarball is committed state of the REF (git archive), never the working tree.

## Verification

```
bash tests/gauntlet/deploy/gauntlet-ab <master-sha> <defect-ref> user J1 1   # AC-1,2,5
# re-invoke after deleting B/ → AC-3; point at a row with no checker → AC-4
```

## Survival set (loop-engineering Step 2b)

| Scenario | Answer |
|---|---|
| convergence | AC-1: decided winner, tally recorded |
| non-convergence | AB-TIE honest halt: "no separation at N rounds; raise N or the variants do not move the metric" |
| bad input | unknown ref / missing card / missing checker → teach-and-refuse naming the input, exit non-zero, nothing staged |
| interrupted | per-round rooms persist (SPEC-236); resume keys on `ab-verdict.txt` per round (a pre-created empty dir from a killed round is re-run, never counted) |
| gamed metric | cheapest gaming: author variant B to embed checker answers (teach-to-the-test) → counter: AB-ROUNDS.md must disclose the inter-variant diffstat, rule-7 answer-key exclusion applies per round, and the winner's record carries the same integrity sweep as a campaign row |

## Out of Scope

Revision between rounds (that is the gauntlet's own loop), model-judged scoring, more than two variants, wiring into stats.sh (later, the marker is designed for it).

## Decision Log

- Driver over engine: loop-engineering routing (search-select wraps, never a second engine).
- Deterministic checker as metric: campaign precedent; sidesteps the model-judge corpus bar.
- Tiebreak on probe tokens: the cheaper-to-satisfy artifact is the better onboarding surface, per the gauntlet's own economics framing.

## Open questions

None blocking. Default N=2 per variant is a starting budget; ID-494's stats corpus will calibrate it.
