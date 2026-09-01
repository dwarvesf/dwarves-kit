---
name: gate-ledger-keys-by-spec-slug
description: The ship-gate reads gate-ledger entries keyed by the SPEC SLUG (branch slug), never the board ID; the spec also needs a Lane header or the gate cannot resolve required gates.
metadata:
  type: project
---

Record phase gates with the spec slug as the rid: `gate-ledger.sh record <spec-slug> <phase> ran "..."`. Entries recorded under a board ID (`ID-NNN`) are invisible to the ship-gate and the push blocks with MISSING-GATE. The gate derives the slug from the branch name and looks up `docs/specs/SPEC-NNN-<slug>.md`, which must carry a `Lane:` header line or the gate refuses before even checking entries. Phase names it expects are the lowercase canon (`spec`, `build`, `ship`), not the capitalized bracket names used for timing outcomes.

**Why:** one push blocked twice in a row for these two reasons on a branch whose gates had all genuinely run.

**How to apply:** record under both keys if telemetry wants the board ID, but the slug record is the one that gates. Add `Lane:` right after `Status:` when drafting a spec. Related: [[kit-ship-gate-push-mechanics]] in ops-toolkit memory.
