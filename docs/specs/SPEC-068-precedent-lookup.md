# SPEC-068: Precedent lookup at intake

Status: SHIPPED
Date: 2026-06-10
Lane: normal (classified: normal)
Type: spec-feature / behavioral
Board: ID-056

## Problem

The kit WRITES knowledge constantly (specs, ADRs, retros, run-ledger reasons) but nothing
READ it back at intake: every new task started from a blank page, re-deriving context the
repo already holds. The second brain had a write head and no read head.

## Decision

`lib/precedent.sh find "<task>" [max]`: keyword-extract the description (lowercase, stop
words dropped, 8 most specific), grep the durable surfaces (docs/specs, docs/decisions,
docs/retro, docs/verification + run-ledger reasons in the log dir), rank files by
DISTINCT-keyword hits, print top-N with each file's first heading. Grep by design: no
embeddings, no index, no daemon (PHILOSOPHY: smallest viable; if grep stops being enough
that is a future spec).

Wired where intake happens: `/kit:assign` runs it before sizing (matches feed the goal
draft's Context); `/kit:grill` orientation step 4 (a question answered by a past spec is
a wasted turn; a precedent CONTRADICTING the ask is the first question).

## Acceptance criteria

- AC1: a fixture spec sharing 3 keywords with the ask is found and ranked `3x`; an
  unrelated spec is not surfaced.
- AC2: stopword-only input reports "no searchable keywords" (exit 0); bad subcommand 64.
- AC3: assign + grill carry the wiring; live smoke on the real repo surfaces real prior
  art (run during build: a classifier-tuning ask returned SPEC-053/057/062/067).

## Test plan

6 fixture tests incl. the negative control: remove the matching source file -> it drops
from the results.

## Verification

- `tests/test-hooks.sh`: 307/307 (301 + 6).
- `tests/test-meta.sh`: 425/425 (+1).
- Live smoke recorded in the PR body.

## Review

Date: 2026-06-10. Quick adversarial pass (metachar injection, subshell-local, ranking
honesty, empty surfaces probed live). Verdict: **SHIP 8/10**, 1 MEDIUM + 2 LOW:

1. MEDIUM, `max` unvalidated (0 / non-numeric crashed BSD head). Fixed: positive-integer
   guard, exit 64.
2. LOW, leading-dash tokens (--verbose) survived as noise keywords. Fixed: dash filter.
3. LOW, BSD head -0 nuance: covered by fix 1.

Cleared: regex metachars structurally neutralized by the tr tokenizer; `grep -- "$kw"`
injection-safe; ranking counts distinct keywords (grep -l + sort -u), not occurrences;
empty dirs/logs clean; wiring pins pass. Post-fix: hooks 307/307, meta 425/425.
