# Sub-goal 01: lib-regroup (rehomed runner-fastpath SG-09)

**Merge policy:** auto
**Time budget:** 2-4 hours of loop work
**Proof:** run-table , full kit test suite green BEFORE the move (baseline) and AFTER (identical pass count), plus a LOAD-BEARING negative control that MOVES a caller and its callee into DIFFERENT subsystems and confirms the cross-subsystem call still resolves , specifically exercise `orchestrate.sh` -> `gate-ledger.sh` (queue -> gate) and `mega-merge.sh` `source` of `kit-log-dir.sh` (goal -> telemetry, FATAL-on-miss), by actually running those engines post-move, not by removing a root shim (a root-shim-removal NC does NOT falsify the real failure mode , moved callers never consult the old flat root). COVERAGE-DELTA row: every moved file's cross-subsystem call-sites still resolve. Rung 2 (named NCs); no injection/mutation surface, so no rung 4.
**Design:** bearing (the resolution strategy is a real choice , the kit's scripts self-resolve siblings from their OWN `BASH_SOURCE`, so a naive one-shim-at-old-root regroup BREAKS every moved cross-subsystem caller; the spec MUST pick (a) a shared lib-root resolver or (b) per-subsystem shims , see the design note's corrected "Regroup , resolution strategy" block)
**Depends on:** none
Model: opus
**Branch:** refactor/kit-foldin-01-lib-regroup
**PR base:** master

## Outcome

`dwarves-kit/lib/`'s ~32 flat files are regrouped into subsystem subdirectories , `board/ queue/ gate/ classify/ spec/ goal/ telemetry/ session/` , with a resolution strategy that keeps every cross-subsystem sibling call working (the kit's scripts self-resolve callees from their own `BASH_SOURCE` dir, so this is NOT a pure `git mv` , see Design + the design note's corrected resolution block). An empty-but-real `lib/session/` exists (SG-03 drops `parse-transcript.sh` into it). A `lib/README.md` maps each subsystem to its files. The full kit suite passes identically to before the move, and the busiest cross-subsystem callers (`orchestrate.sh`, `mega-merge.sh`) actually run post-move.

## Quality bar

Zero runtime breakage. A reader opening `lib/` sees subsystems, not an alphabet soup of 32 peers. Orphans with no cluster (`adopt.sh explain.sh pitch.sh precedent.sh`) stay at `lib/` root , no `misc/` bucket invented to force them in (ponytail). The shim is the seam that makes this safe; if any call-site needs editing, the shim is wrong, not the call-site.

## How to close the loop

Use the exact subsystem map in `research/2026-07-05-cc-elevation-kit-foldin-design.md` (the `lib/` subsystem map block; note `handoff-gen` moves WITH `handoff/` into `goal/`). FIRST spec the resolution strategy (Design: bearing) , pick (a) a shared lib-root resolver every cross-subsystem call routes through, or (b) a per-(caller-subsystem, callee) shim inside each subsystem dir (`lib/queue/gate-ledger.sh -> ../gate/gate-ledger.sh`). Then:

- Baseline: run the full kit suite, capture pass count (discover the suite entry, do not assume).
- Map the actual cross-subsystem sibling calls first: `grep -rnE '\$[A-Z_]*DIR/[a-z-]+\.sh|source "\$[A-Z_]*DIR' lib/` to enumerate every self-`BASH_SOURCE` sibling call BEFORE moving anything (this is the set the resolution strategy must cover).
- `git mv` each file into its subsystem dir; apply the chosen resolution strategy so every enumerated cross-subsystem call still resolves.
- Move `handoff-gen` with `handoff/` into `goal/`.
- Create `lib/session/` (empty dir with a `.gitkeep` or stub `README.md`; SG-03 fills it).
- Write `lib/README.md` , one section per subsystem, files listed.
- Re-run the full suite: pass count MUST equal baseline.
- LOAD-BEARING NC: run `orchestrate.sh` far enough to hit its `$ORCH_DIR/gate-ledger.sh` call, and `mega-merge.sh` far enough to hit its `source "$MM_DIR/kit-log-dir.sh"` (FATAL-on-miss); confirm BOTH resolve post-move (a plain `git mv` with only a root shim FAILS this , that is the point). Record both.
- Backstop: temporarily break the chosen resolver (e.g. remove one subsystem shim / mis-set the lib-root) and confirm the dependent engine goes RED, restore, GREEN.

Kit-adopted repo: record gates via `bash lib/gate-ledger.sh` (build + review) before the push; `lane-classify` will likely call this `small`/`normal`.

**Done =** the full kit suite passes at the identical pre-move count AND `orchestrate.sh` + `mega-merge.sh` both resolve their cross-subsystem sibling calls when run post-move AND the resolver backstop goes RED-then-GREEN, all captured in `docs/proof/kit-foldin-lib-regroup.md`.

## Handoff on completion

1. Flip this ROADMAP box to `[x]`, record PR #.
2. Overwrite HANDOFF.md: next action = SG-03 may now dispatch (needs `lib/session/`); point at `lib/session/` + the design note's parser interface note.
3. Append to DECISIONS.md any subsystem-boundary judgment calls (e.g. which subsystem a genuinely-ambiguous file went to).
4. Report in the records, then EXIT.

## Scope edges

**In:** `dwarves-kit/lib/` file moves, the resolution-strategy edits (a shared lib-root resolver OR per-subsystem shims , whichever the spec picks), `lib/session/` creation, `lib/README.md`.
**Out:** any file CONTENT change beyond the minimal resolution-strategy edit (no behavior change), `hooks/`, `agents/`, `commands/`, `tools/`.
**Not:** renaming any lib file's function/verb; "improving" a script while moving it (the ONLY allowed edit is the sibling-resolution mechanism); deleting the orphans; touching `install.sh`; leaving `handoff-gen` stray (it moves with `handoff/`).

## Where to look

`dwarves-kit/lib/` (the flat files), the kit's test-suite entry point, the design note's `lib/` subsystem map.

## PR body

Regroup `lib/`'s ~32 flat files into subsystem subdirs (board/queue/gate/classify/spec/goal/telemetry/session) with a resolution strategy that keeps every cross-subsystem sibling call working (the kit self-resolves callees from `BASH_SOURCE`, so a naive root-only shim breaks moved callers); create `lib/session/` for the incoming shared parser; add `lib/README.md` nav. Rehomed from runner-fastpath SG-09.

Verify: full kit suite green at identical pre-move count; `orchestrate.sh` + `mega-merge.sh` resolve cross-subsystem calls post-move; resolver backstop RED->GREEN. Proof: `docs/proof/kit-foldin-lib-regroup.md`.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-foldin/ROADMAP.md`.

## Notes
