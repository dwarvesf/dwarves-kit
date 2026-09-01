# SPEC-072: Classifier anchor recall fixes (2 live misfires)

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery hard-gate)
Type: bug-fix / behavioral
Board: ID-064, ID-057

## Problem

Two live classifier misfires, both repro'd at intake:

1. **ID-057** (task-type): the bare `\bcli\b` anchor in data-tool steals feature
   work ON a CLI: `add a --version flag to the demo CLI` -> `data-tool` (found by
   the SPEC-067 golden run). Building a CLI is data-tool work; adding a flag to one
   is spec-feature work.
2. **ID-064** (lane): markdown-only bootstrap work falls to the `normal` default:
   `bootstrap a learning track folder with README, notes and reading list
   (markdown only)` -> `normal` (live probe, ops-toolkit economics-track session).
   Doc-bootstrap with no code belongs in `tiny`.

## Decision (SPEC-060 narrow-anchor method)

1. **data-tool anchor narrowed**: bare `\bcli\b` is removed; data-tool fires on
   MAKING a CLI (`build/write/create/wrap/port ... cli`, `cli (tool|wrapper|
   client)`), not on touching one. Feature-work-on-a-CLI falls through to
   spec-feature.
2. **tiny gains doc-bootstrap anchors**: `markdown[ -]only` and
   `bootstrap ... (readme|notes|reading list|learning track)` phrasings classify
   tiny. Real-phrasing truth-table rows + negative pins (a server bootstrap or a
   code scaffold must NOT flip to tiny).

## Acceptance criteria

- AC1: `add a --version flag to the demo CLI` -> spec-feature; `build a CLI to
  pull inverter data` stays data-tool; `port the exporter to a cli` stays
  data-tool.
- AC2: the ID-064 live phrasing -> tiny; `bootstrap the server user on the mini`
  stays NOT-tiny; `scaffold the agent skeleton in go` stays NOT-tiny.
- AC3: the full SPEC-057/060 truth tables stay green (no recall regression).

## Test plan

Failing-first truth-table rows in tests/test-hooks.sh: 2 RED on the pre-fix tree
(the two live phrasings), plus 4 negative pins that are green before AND after.
Negative control: reverting either anchor edit flips its row RED.

## Verification

- Failing-first: 2 RED on the pre-fix tree (both live phrasings), fixes -> GREEN.
- Suites: hooks 359/359, meta 432/432, e2e 20/20.
- Negative controls, both measured live: 3b doc-bootstrap block disabled -> 1 RED,
  restored green; verb arm removed -> 1 RED (after the NC itself exposed the arm as
  UNPINNED , the first removal produced 0 RED because the original positives also
  matched via pull/port anchors; a verb-arm-only pin was added), restored green.

## Review

Date: 2026-06-11. Multi-lens (3 lenses: regex correctness 7/10, precedence 5/10,
truth-table 7/10). The precedence lens caught the wave's nastiest finding:

- HIGH: the two new tiny anchors sat at precedence 2, PREEMPTING hard-gates , a
  README bootstrap about auth tokens or gate machinery classified tiny/inert (the
  worst class downgrade). Fixed: anchors moved to a new 3b check AFTER the
  hard-gate pass, with 2 hard-gate-wins pins.
- MEDIUM: `make` verb stole `make the cli faster` -> dropped from the verb set,
  pinned; the standalone `cli (tool|wrapper|client)` noun arm stole
  `implement --version in the CLI tool` -> dropped, pinned.
- MEDIUM: the two not_contains negatives gained companion positives (vacuous-pass
  risk on classifier crash); a bare-cli guard pin added.
- Known accepted gaps (documented, unpinned): `bootstrap readme for the new
  daemon` still tiny (daemon is not a hard-gate subject); type/lane mismatch on
  `markdown-only docs for the deploy` (type=migration via the deploy anchor,
  pre-existing ordering, lane wins for gate routing).

Post-fix: hooks 359/359. Verdict: SHIP.
