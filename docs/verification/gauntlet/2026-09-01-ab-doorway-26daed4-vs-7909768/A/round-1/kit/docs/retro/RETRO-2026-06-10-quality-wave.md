# Retro: the north-star arc + quality wave

Date: 2026-06-10
Cycle: SPEC-054..069 (16 specs, PRs #31..#48, ~3 days compressed into one)
Data: first retro backed by telemetry instead of memory (Step 1d sweep below).

## Metrics

- 29 commits / 12 PRs merged in the final 24h; 6 specs in the quality wave alone.
- Telemetry: 32 runs, 9 tracked (8 shipped), 1 lane-misroute (spec-062, caught by its own
  detector), 3 boardless (the pre-discipline history), 0 overrides, 9 skips all reasoned.
- Review: 6 adversarial rounds, ~25 findings, 6 HIGH, ALL blocked before merge. Average
  pre-fix verdict ~6.5/10; post-fix 100% SHIP.
- Suites: 316 hooks + 426 meta + 20 e2e, green on master; install pinned (sha=0469c65).

## What worked (keep as standard)

1. **Real phrasing beats invented phrasing.** The SPEC-060 pattern (every live misfire
   becomes a truth-table row + negative pin) fixed in one PR what invented test phrases
   had rubber-stamped. Standard from now on: classifier changes ship with live-probe rows.
2. **Reviews that hurt are reviews that work.** The 5/10 FIX-FIRST verdicts each blocked
   2 HIGH bugs pre-merge (a quoted-ref bypass, a user-file destroyer). Multi-lens proved
   its premium on SPEC-069: three lenses, three disjoint failure classes in one pass.
3. **Detect, don't remember.** Every process failure this arc was a PROSE rule losing to
   context decay (boardless wave, the spec-064 think gap, grill skips unrecorded). Every
   fix that stuck was a detector or a pin. This is now the reflex: a recurring "remember
   to X" is a detector waiting to be written.
4. **Dogfood-first pays immediately.** stack-merge merged its own wave (and found its
   clean-tree-counts-untracked quirk live); the golden run caught a real classifier bug
   on its FIRST execution; the boardless detector flagged its own builder's history.

## What hurt

1. **rid vs branch-slug mismatch** (worst friction): assign records gates under
   `spec-NNN` while ship-gate keys the ledger by BRANCH slug, forcing mirror records on
   every ship (5 times today) and polluting the untracked metric with mirror rids.
2. Pre-SPEC-064 hook false positives: ~7 interruptions in one day. Fixed in-kit; the
   operator's PERSONAL settings.json delete-hook still prose-matches (outside the kit;
   flagged to the operator, not actionable here).
3. Discipline visibility needed two operator reminders (board, progress display) before
   SPEC-063/069 made it mechanical.
4. Review verdicts lived only inside spec files until SPEC-061 put them in the ledger;
   no trend view existed for most of the arc.

## Action items (enqueued on the board)

- **ID-059 (P1)**: rid standardization, rid = branch slug everywhere (assign derives the
  branch slug at START; mirrors disappear; untracked metric becomes honest).
- **P2, no row needed**: run REAL work through the kit for 3-5 days (ops-toolkit daily +
  /kit:adopt dfoundation), then the NEXT retro decides persona dispatch (ID-047 design
  hints ready) from data, not taste.
- **P3**: existing debt rows ID-050 (checklist visual order) + ID-057 (cli anchor) stay
  queued; fold into idle moments, not a wave.

## Kit feedback

The lifecycle is now fully dogfooded end to end EXCEPT /kit:retro itself ran for the
first time only at this close (operator caught it). The Reflect phase needs the same
treatment Build got: the retro disposition contract (Step 1d) held, but nothing nudges a
retro after N ships; candidate detector for a later cycle, deliberately NOT built now
(wait for the 3-5 days of real data first).
