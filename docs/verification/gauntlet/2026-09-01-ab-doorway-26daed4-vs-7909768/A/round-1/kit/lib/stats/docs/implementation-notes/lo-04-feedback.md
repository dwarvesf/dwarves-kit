# Implementation notes: lo-04-feedback (the DELTA from the spec)

Only records where the build DECIDED something the spec/ROADMAP did not pin, deviated, or hit
a constraint. Not a mirror of the spec.

## 2026-07-04, debt signal maps to `kit_runs.gates_ovr`, not a dedicated debt ledger

- Context: the goal file names "unpaid-debt count over a threshold (debt ledger)". The
  understanding-DEBT ledger (kit understanding-gate) is PLANNED and conforms to the kit schema
  (SG-01) but is NOT yet materialized as its own table in the SG-02 lens.
- Decision: the `debt` detector reads `SUM(kit_runs.gates_ovr)` (gate OVERRIDES = consciously
  WAVED gates = unpaid understanding debt) as the debt signal present in the lens today.
- Why: the contract mandates ONE data path (detect via SG-02, never re-query a raw ledger). An
  override is the materialized "I waved the gate" signal; it is the honest available proxy.
- Alternatives: wait for the dedicated debt-ledger table (blocks this sub-goal on a future kit
  sub-goal); re-read a raw debt ledger file (forbidden second data path).
- Impact: forward-compatible. When the dedicated debt table materializes, the detector's SQL
  repoints and the threshold + proposal machinery is unchanged. Logged in SPEC-129 DEC-004 +
  signal-mapping table; named in the COVERAGE-DELTA uncovered list.

## 2026-07-04, goal file says "via work-intake"; the correct primitive is cc-backlog staging

- Context: the goal file names the `work-intake` skill as the propose-into-cockpit contract.
- Delta: `work-intake`'s Step 3 writes `_meta/BACKLOG.md` DIRECTLY (no file-level staging/gate).
  Calling it from an automated detector would AUTO-FILE the board, violating propose-not-autofile.
- Decision: honor the goal file's INTENT (propose into the cockpit, operator gates) via the repo's
  real propose-then-human-gate primitive, `cc-backlog`'s staging buffer + `add-backlog`. The worker
  brief also directs reusing the existing candidate-staging mechanism. Logged in SPEC-129
  Approaches #2 + DEC-001; surfaced by kit:brief-reviewer MAJOR-1.

## 2026-07-04, reuse cc-backlog staging, do not invent a second board convention

- Decision: proposals STAGE as `## [staged]` blocks appended to `_meta/backlog-staging.md`
  (env `CC_BACKLOG_STAGING`), byte-format-identical to `tools/cc-backlog/bin/cc-backlog`'s writer,
  consumed by the existing `add-backlog` human gate. Dedup reuses cc-backlog's `norm()` (lowercase
  alphanumeric words) against BOTH the board Item titles AND already-staged titles.
- Why: ROADMAP Quality bar + goal file: reuse the candidate-staging mechanism, do not invent a
  second board-write convention. The tool NEVER writes a board `BACKLOG.md`.
- Note: cc-backlog is a stdlib `bin/` script, not an importable package. Re-implementing the tiny
  `norm()` + block format in `anomalies.py` is deliberate: the shared CONTRACT is the staging FILE
  + the `add-backlog` consumer, not shared code. Confirmed against the cc-backlog source.
