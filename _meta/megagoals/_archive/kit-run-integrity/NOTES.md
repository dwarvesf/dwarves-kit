# NOTES , kit-run-integrity

## Active blockers

- [none] Gate-zero resolved by the pointer + ROADMAP Assumptions: new gates (03/04) are ADVISORY by default (no ADR required). A BLOCK needs Han's bless , a worker stops for it ONLY if its /spec concludes a block is genuinely required. No other blocker on entry.

## Proposed additions

- 2026-07-04: (advisory->block question) 03 + 04 ship advisory. Once the ledger has accrued real `caught=` data from 01, the advisor at TIER-4 should re-ask whether coverage-delta and/or mutation-smoke have earned a BLOCK promotion (the localterm-override datum in the benchmark is the argument that the leak is at the override/advisory boundary). Surface this to Han, do not self-promote.
- 2026-07-04: 05's generated proof-table is the first CONSUMER of 01's `caught=` markers , the same "reverse the write-only drop" move the effectiveness-audit flagged for the gate run-ledger ("CEREMONY as built"). If the proof-table generator proves useful, the ledger-observatory feedback loop (ops-toolkit) is the natural cross-repo consumer of the same markers; dedup at work-intake rather than double-building.

## Reconciliation debt (resolve before/at TIER-4)

- ~~**05↔01 marker mismatch**~~ RESOLVED PR #160 merged c8f56cc (SPEC-133): proof-table-gen.py now parses 01's real two-line `OUTCOME start/end … dur_s` marker (event=parts[3], epoch-delta fallback), CAUGHT+DURATION populates from real data, negctl revert→RED, 05-suite no-regression. Original gap for record:
- **05↔01 marker mismatch (RESOLVED, see above).** 05 (proof-table-gen, merged #157) ASSUMED 01's marker = single-line `OUTCOME | <phase> | caught= start=<ISO> end=<ISO> dur_ms=`. 01's ACTUAL marker (#158) = TWO lines: `OUTCOME | <phase> | start | at=<epoch>` and `OUTCOME | <phase> | end | at=<epoch> caught=<bool> dur_s=<N>`. So 05's CAUGHT/DURATION column will silently stay empty (graceful-absent path) against REAL 01 data. FIX: update `lib/proof-table-gen.py` to pair 01's start/end OUTCOME lines by phase, read `caught` from the end line, compute duration from `dur_s`/epochs. This is the TIER-4 no-orphan check's concrete output (05 must actually surface 01's marker). Do it as a small reconciliation commit after 01+04 merge.
- **01+04 both edit `lib/gate-ledger.sh`** (01 adds `OUTCOME` verb, 04 adds `MUTATION` verb). Different surfaces, but a git merge conflict is expected in the verb/help region , resolve by keeping both additive verbs.

## TIER-4 findings (2026-07-04)

**Integration + no-orphan: CLEAN, zero blocking.** 5/6 surfaces wired to live callers (02→orchestrate.sh:1103/747 wave-dispatch, 01→ship-gate.sh:168-183, 03→review-team.md:24, 04→verify.md:56); 133-reader byte-matches 01's marker; 05 proof-table-gen = INVOCABLE-DOCS-PENDING (operator-run, auto-fire cross-link scoped to 06 by SPEC-132, NOT an orphan). Objective measurable/collision-safe/honestly-proven all ok. meta 667/667 + all surface suites green. FOR_SG06: (a) cross-link `lib/proof-table-gen.sh <rid>` into AGENTS.md + WORKFLOW.md at the proof-of-done/ship moment; (b) surface the advisory gates (03/04) + OUTCOME telemetry in operator-facing WORKFLOW.

**Advisor critique (route the actionable ones into 06's contract):**
- C1 **Enforcement asymmetry**: 01 is hook-enforced (ship-gate emits unconditionally); 03/04 are only PROSE steps inside command markdown (review-team.md:20-25, verify.md:47-56) , an agent can skip them with zero trace (check()/descent() ignore the additive markers). 06's no-orphan check must DISTINGUISH hook-enforced vs prose-invoked-optional, not certify 03/04 as "wired" on the weakest reading.
- C4 **coverage-delta is a diff-line HEURISTIC** (COVERAGE_DELTA_RUNNER hook exists+tested but unset); 06 must NAME it a heuristic wherever it surfaces (no real %-coverage delta today).
- C5 **03/04 invisible to ledger status surfaces** (WORKFLOW.md/required()/plan()/progress()/descent() have zero awareness) , no dashboard signal if they didn't run.
- C2 `caught=` is ship-boundary-only (outcome() sole call site = ship-gate, phase=ship); not per-gate. Consistent with shipped design ("a gate") but limits per-gate measurement , see over-suggests.
- C3 the 05-before-01 assumed-marker seam (resolved by SPEC-133) is the textbook cross-sub-goal hazard; recorded for future consumers of 03/04 markers.

**Security review: HAS ISSUES → SPEC-134 remediation PR before 06.**
- **HIGH, path traversal / arbitrary file write, `lib/proof-table-gen.py:229,233-241`.** Unsanitized `rid` builds both read (`runs/<rid>.log`) and default write (`docs/runs/<rid>.md`) paths; the guard only blocks the literal basename `proof-of-done.md`, so an absolute rid (`/etc/…`) or `../../` rid escapes `docs/runs/` (os.path.join-with-absolute gotcha; makedirs even creates the tree). PoC-confirmed. Not auto-wired today but 06 widens the surface, and orchestrate.sh:826-831 already treats goal-derived slugs as attacker-reachable. FIX: sanitize `rid` like gate-ledger `runid()` (`tr '/ ' '--' | tr -cd '[:alnum:]._-'`) before ANY path use, in BOTH paths; realpath-confine `out_path` under `docs/runs/` even for an explicit out-path arg; reject outside.
- **MEDIUM, `mutation()` comment/code mismatch, `lib/gate-ledger.sh:534-546`.** Comment claims it neuters embedded `=`; code only does `tr '\n\r' ' ' | tr ' ' '_'`. Not exploitable today (no MUTATION reader) but misleads. FIX: `tr '=' ':'` on free-text values like `debt()`.
- LOW: mutation-smoke.sh mutates through symlinks (add `[ ! -L "$file" ]` guard); spec-next `$REPO` field unsanitized (local-only, defer).

## Proposed additions (TIER-4)

- **Advisory→BLOCK promotion (for Han, advisor's headline question).** Should 03 (coverage-delta) and/or 04 (mutation-smoke) earn a BLOCK once real `caught=` data accrues? Advisor RECOMMENDS **not yet**: the benchmark's localterm datum is about overriding an *existing block*, an analogy not direct evidence for silently-ignored advisories; and there's no per-gate `caught=` accrual path for 03/04 today (ship-only). Land per-gate telemetry (below) + measure a false-positive rate over N cycles, THEN revisit with numbers. Promoting blind risks the same impact-vs-noise tax the benchmark flagged for slop-cleaner.
- Extend `outcome()`'s emit to the spec + review phase boundaries (proven additive verb) so `caught=` is genuinely PER-GATE, not ship-only (prereq for any future block-promotion analysis).
- Have coverage-delta + mutation-smoke ALSO emit via `outcome caught=` (beside their own GATE/MUTATION lines) so block-promotion analysis has like-for-like data across gates (avoids another SPEC-133-style reconciliation).
- Add a cheap advisory-presence note to progress()/descent() or proof-table-gen ("coverage-delta/mutation-smoke marker absent this run") , closes C1/C5 without promoting to a block.
- Graduated nag-counter: N consecutive flags on one file → auto-file a `_meta/BACKLOG.md` row, reusing the `debt()` tap/defer/wave ledger pattern , escalates attention without touching the push blocker.
- Dogfood 02's atomic `spec-next.sh reserve` on the NEXT mega-goal's numbering (this run's 128-133 predates the fix; the conductor DID use `reserve` for the wave block 129-133, so partially dogfooded already).

## Event log

2026-07-04 · COMPLETE · 8 PRs to dwarvesf/dwarves-kit: #155(02) #157(05) #156(03) #159(04) #158(01) #160(133-reconcile) #161(134-security) all MERGED f07fb6b..a9a2e55; #162(06) OPEN+HELD for Han (CI green both platforms, doc-verifier 22/22). TIER-4 CLEAN: integration/no-orphan CLEAN, security gate found+remediated a HIGH path-traversal + a MED, advisor routed advisory->block to Han. 13 dispatches, ~2.85M subagent tokens, opus(design/security/verify)+sonnet(execution). RUN_REPORT.md written. Recoveries during the run: 01 missing-proof resume + proof push-delay re-fetch; 02 + 134 CI portability fixes; 64 phantom dev reservations truncated. Co-located to _archive/. STOP: success = 01-05 merged + 06 held + TIER-4 clean = MET.

2026-07-04 · scaffold+conduct · kit-run-integrity mega-goal created THIS run. The `/goal` pointer assumed a pre-existing scaffold that did not exist; the conductor authored it (ROADMAP + NOTES + POINTER + goals/01-06) grounded in the binding sources (2026-07-02 process-benchmark §2/§5 + process-effectiveness-audit Verdict-per-layer "Gate run-ledger = CEREMONY as built" + ledger-observatory NOTES Proposed-additions "reuse the additive marker, do not invent a new convention") and the pointer's own hard constraints, then proceeded per OPERATE.md SUBAGENT-DELEGATE. 6 sub-goals; merge order 02-first (race-enabler) -> {01,03,04,05} parallel -> TIER-4 -> 06 held. Work repo dwarvesf/dwarves-kit. Deviation logged: scaffold authored in-run rather than read (the single precondition gap); all 6 contracts derive from the pointer + research, not invented scope. Belt-and-suspenders: conductor pre-assigns the wave's SPEC block by hand (dispatch is via the Agent tool, not orchestrate.sh's wavefront path that 02 fixes , independent surfaces).
