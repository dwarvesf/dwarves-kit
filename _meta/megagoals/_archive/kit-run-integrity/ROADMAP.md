# Mega-goal: kit-run-integrity

**Destination:** dwarves-kit's autonomous run layer becomes MEASURABLE + COLLISION-SAFE + HONESTLY-PROVEN. Six kit-side follow-ups from the 2026-07-02/03 process benchmark land as additive, mostly-advisory kit changes: (1) gate runs emit an OUTCOME (`caught=` + `START`/`END` timing) so the gate layer is measurable, not just a ran/skipped tally; (2) the wavefront SPEC-number race is closed so a parallel wave cannot collide; (3) an advisory coverage-delta gate flags an under-tested diff; (4) an advisory mutation smoke flags a suite that does not actually bite; (5) the proof-of-done table is GENERATED from the ledger, never hand-authored; (6) the docs wire it all together with a no-orphan check. The through-line: today the gate/proof machinery records that it RAN but not whether it CAUGHT anything or how long it took (effectiveness-audit: "Gate run-ledger = CEREMONY as built"), and coverage is opt-in (benchmark §2). This closes the measurement + honesty gap without swapping the core loop.

**Quality bar:** ADDITIVE and ADVISORY by default. 01 reuses the existing `gate-ledger.sh` additive-marker convention (the same `ISO8601 | MARKER | k=v` line that TOKENS/SPEC-110 and DEBT/ADR-0031 already ride) , do NOT invent a new marker convention. 02 reuses `spec-next.sh` (move WHO reserves the number and WHEN, not a rewrite of the scanner). 03 + 04 are ADVISORY gates (they warn, never block) unless /spec concludes a block is required AND Han blesses it (gate-zero). 05 GENERATES the proof table (a generator over the ledger, never a hand-authored artifact the generator overwrites). Every gate/emit proves a LIVE invocation path , TIER-4's no-orphan check treats a defined-but-never-dispatched gate/emit as blocking. Over-test 03 + 04: each owes a COVERAGE-DELTA row AND a FALSE-POSITIVE negative control (03: a well-tested diff does NOT trip; 04: a biting suite is NOT flagged).

**Work repo:** `dwarves-kit` (self-hosts the kit lifecycle; read AGENTS.md + WORKFLOW.md first). Scaffold + records live here in ops-toolkit `_meta/megagoals/kit-run-integrity/`.

**Stacking tool:** gh (02 merges to master first; 01/03/04/05 branch off master-with-02; 06 last)

**Merge mode:** auto-bottom-up (02 merges first as the wave-enabler; 01/03/04/05 auto-merge as gates pass; 06 held)

**Merge autonomy:** gated-final (the FINAL PR , 06 docs-wiring , is Han's click; 01-05 auto-merge as gates pass on green CI)

**Run mode:** SUBAGENT-DELEGATE (6 sub-goals > 4; the `/goal` loop is a THIN CONDUCTOR that dispatches each ready sub-goal as a background worktree subagent via the Agent tool, model from its `Model:` field, and absorbs one terse line , per OPERATE.md + the plan-for-mega-goal run-mode option). PRs to `dwarvesf/dwarves-kit`.

**Terminus:** build + merge 01-05 + the held final PR (06).

**Started:** 2026-07-04

## Provenance

`ops-toolkit/research/2026-07-02-process-benchmark.md` (impact-vs-noise verdicts; §2 coverage gap, §5 hook/measurement tax) + `research/2026-07-02-process-effectiveness-audit.md` (§ Verdict-per-layer: "Gate run-ledger = CEREMONY as built , 1 surviving record, blanket overrides"; §5/8 miner evidence that the gate CATCHES are real but UNMEASURED) + the ledger-observatory NOTES `## Proposed additions` (the additive `ISO8601 | VERB | k=v` marker is THE canonical schema; reuse it, do not invent a third/fourth convention; the feedback loop gives the kit ledgers a CONSUMER) are the intent. This mega-goal EXECUTES the kit-side follow-ups; it does not re-decide them. Companion: `research/2026-07-03-megagoal-execution-hygiene.md` (delegate run-mode, model routing planning->opus, kill-resilience) governs HOW this run executes.

## Sub-goals

- [x] 02-wavefront-spec-race , close the concurrent `spec-next.sh next` race: a parallel wave that each calls `next` before any branch/spec exists all get the SAME number (spec-next scans branches + specs + commits, but the reservation happens too LATE). REUSE spec-next.sh; move WHO reserves + WHEN (atomic reservation at wavefront dispatch in `orchestrate.sh`, not each worker racing `next` at spec-time). Design-bearing (`## Design`). FIRST (enables the parallel wave). , `auto` , PR #155 merged f07fb6b (SPEC-128; portable mkdir-mutex + stat -c/-f portability fix; CI green both platforms)
- [ ] 01-gate-outcome-emit , gate runs emit an OUTCOME on the EXISTING additive-marker convention: `caught=<true|false>` (did the gate catch a defect , non-clean exit / findings) + a `START`/`END` timing bracket (gate duration). REUSE `gate-ledger.sh` (a new additive marker beside TOKENS + DEBT; readers that key on `$2=="GATE"` ignore it). Makes the gate layer MEASURABLE. Design-ish (marker shape + catch-detection). , `auto` , PR #158 merged 76ce29a (SPEC-129; additive `| OUTCOME |` marker two-line `<phase> | start\|end | at=<epoch> caught=<bool> dur_s=<N>`; proof added on resume w/ real negctl; gate-ledger OUTCOME+MUTATION union resolved; RECONCILE 05's reader at TIER-4)
- [x] 03-coverage-delta-gate , an ADVISORY gate: for a behavioral diff, does it move test coverage the right way? A well-tested diff does NOT trip; an under-tested diff is FLAGGED (warn, never block). OVER-TEST (coverage-delta row + false-positive NC). Design-bearing (`## Design`; how delta is computed, advisory contract). , `auto` , PR #156 merged f240c95 (SPEC-130; lib/coverage-delta.sh, hook at Review phase off the push blocker; 17/17 incl. false-positive NC; test.yml conflict resolved)
- [ ] 04-mutation-smoke , an ADVISORY smoke: mutate a line in the changed code , does the suite BITE (fail)? A biting suite is NOT flagged; a non-biting suite IS flagged. Cheap smoke, not full mutation testing. OVER-TEST (coverage-delta row + false-positive NC: a biting suite is NOT flagged). Design-bearing (`## Design`; mutation strategy, bite detection, advisory contract). , `auto` , PR #159 merged 3371680 (SPEC-131; additive `| MUTATION |` verb, hook at /kit:verify step 6b warn-only, MUTATION_SMOKE_MAX=5, proof at docs/verification/mutation-smoke/; NB 01 will conflict on lib/gate-ledger.sh)
- [x] 05-generated-proof-table , GENERATE the proof-of-done confirmation table from the gate/run ledger (never hand-author). Reads 01's `caught=`/timing markers when present, degrades gracefully when absent (additive-tolerant). A generator + a marker-gate that a proof table's run-table is generated, not typed. , `auto` , PR #157 merged 83ace8d (SPEC-132; lib/proof-table-gen.{sh,py}, writes docs/runs/, hard-refuses proof-of-done.md; ASSUMED 01 marker `OUTCOME|<phase>|caught=|start=|end=|dur_ms=`, RECONCILE vs 01 at TIER-4)
- [ ] 06-docs-wiring , wire 01-05 into AGENTS.md / WORKFLOW.md / CLAUDE.md / the relevant ADR + READMEs, + a no-orphan wiring check (every new gate/emit proves a live invocation path). Docs-last (reflect the final wired state). HELD for Han. , `auto` , **PR #162 OPEN + HELD for Han's click** (SPEC-135; AGENTS/WORKFLOW/ADR-0024 wired for 01/02/05 + an honest "Advisory measurement gates" section for 03/04 naming the enforcement asymmetry + coverage-delta-is-a-heuristic; new test-kri-wiring.sh 31 assertions + executed negctl; doc-verifier 22/22; box stays UNCHECKED until Han merges)

## Dependencies

- 02 depends on nothing. It is FIRST and merges before the parallel wave (it closes the race that wave would hit).
- 01, 03, 04, 05 depend on 02 (they branch off master-with-02 so their own parallel `/spec` calls cannot collide). Belt-and-suspenders: the conductor ALSO pre-assigns a contiguous SPEC block to the wave (the pointer's fallback, applied unconditionally because this run dispatches via the Agent tool, not orchestrate.sh's wavefront path that 02 fixes).
- 05 has a soft DATA dependency on 01 (it surfaces 01's `caught=` column) but no code dependency , it reads whatever markers exist and degrades gracefully, so it builds in parallel with 01; TIER-4's no-orphan check confirms 05 actually surfaces 01's marker.
- 06 depends on ALL of 01-05 (docs-last: reflect the final wired state, per the kit-face lesson). Branches off master after 01-05 merge.
- Execution order: 02 -> {01, 03, 04, 05} parallel -> TIER-4 -> 06 (held). Stack: 02 off `master`; 01/03/04/05 off master@post-02-merge; 06 off master@post-05-merge, LAST.

## The measurable/collision-safe/honest triad (BINDING)

```
COLLISION-SAFE            MEASURABLE                   HONESTLY-PROVEN
  02 spec-race             01 gate-outcome emit          03 coverage-delta (advisory)
   reserve the number       caught= + START/END           an under-tested diff is flagged
   atomically at dispatch    on gate-ledger's                 vs a well-tested one (NC)
   (reuse spec-next,          additive marker            04 mutation smoke (advisory)
    move WHO/WHEN)             (beside TOKENS/DEBT)         a non-biting suite is flagged
        │                          │                          vs a biting one (NC)
        │                          └──────────┐            05 generated proof-table
        └── enables the parallel wave ───►    ▼                reads 01's caught= column,
                                         06 docs-wiring          GENERATES the run-table
                                         + no-orphan check         (never hand-authored)
```

- ADDITIVE: 01 extends `gate-ledger.sh`'s marker set; it does not change what `check()/override()/_rows()` read. 05 reads the ledger; it does not become a second source of truth.
- ADVISORY: 03 + 04 WARN. A BLOCK needs /spec to conclude a block is required AND Han's bless (gate-zero). Default is warn-only.
- REUSE: 01 reuses gate-ledger's additive marker; 02 reuses spec-next's scanner (moves the reservation, not the scan). No new convention invented anywhere.

## Assumptions (2026-07-04; the pointer + benchmark resolved the shape; per-sub-goal /spec re-frames) , BINDING

- **New gates (03/04) are ADVISORY by default.** No ADR needed for advisory. A BLOCK needs Han's bless , a worker stops for it ONLY if its /spec concludes a block is genuinely required. Default warn-only.
- **01 reuses the EXISTING additive-marker convention** (`gate-ledger.sh`, the `ISO8601 | MARKER | k=v` line TOKENS + DEBT already ride). It does NOT invent a new marker file or convention. Readers that key on `$2` ignore the new marker (the additive property the kit already relies on).
- **02 reuses `spec-next.sh`** , the scanner (specs + branches + commits) stays; the fix moves WHO reserves the number and WHEN (an atomic reservation at wavefront dispatch), it is NOT a rewrite of the scan.
- **05 GENERATES the proof table** from the ledger. The generator never overwrites a hand-authored canonical (per SPEC-016: a generator writes under `docs/runs/`, never the canonical `proof-of-done.md`). It is additive-tolerant of 01's markers.
- **Over-test 03 + 04** , each owes a COVERAGE-DELTA row AND a FALSE-POSITIVE negative control (03: a well-tested diff does NOT trip; 04: a biting suite is NOT flagged). Via `/kit:test-plan`.
- **Cross-cutting WIRING GATE (kit-face c6fbd99 lesson):** every gate/emit proves a live invocation path; TIER-4 runs a no-orphan check (a defined-but-never-dispatched gate/emit = blocking).
- **This run dispatches via the Agent tool (worktree subagents), not orchestrate.sh.** So the conductor PRE-ASSIGNS the wave's SPEC block by hand (the pointer's fallback, applied unconditionally) even though 02 fixes the orchestrate.sh wavefront path , the two are independent surfaces.

## Open forks (surface, non-blocking; /spec defaults)

1. **02 reservation mechanism:** an atomic file-lock reservation ledger (`flock` + a `spec-reservations` file) vs the conductor pre-assigning numbers vs both. /spec defaults to an atomic reservation in orchestrate.sh's wavefront path (fixes the general case) + the conductor pre-assign for THIS run (the belt). Both, they are different surfaces.
2. **01 catch-detection signal:** what counts as "caught"? A non-clean gate exit, findings emitted, or an explicit verb from the gate. /spec defaults to: `caught=true` when the gate's own recorded state is a non-pass (a block / findings / non-zero), `caught=false` on a clean pass; the timing bracket is unconditional.
3. **03 coverage tool:** language-agnostic diff-line heuristic (changed non-test lines vs added/changed test lines) vs a real coverage runner (pytest-cov / go test -cover / c8). /spec defaults to the diff-line heuristic for the advisory (portable across the kit's polyglot targets), with a hook to a real runner where one is configured. Advisory, so a heuristic is acceptable.
4. **04 mutation scope:** which mutations, how many, over what. /spec defaults to a cheap smoke (a small fixed set of mutation operators on the changed hunks only, first-mutation-survives = flag), not a full mutation-testing sweep. Bounded runtime.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
