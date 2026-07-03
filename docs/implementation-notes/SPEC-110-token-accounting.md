# Implementation notes: SPEC-110 token-accounting

Delta from the spec. References, does not restate.

## 2026-07-03 spec-validate: VALIDATED-WITH-NITS, 4 folded (design verified clean)

The two highest-stakes lenses were verified against real code by the validator: SPEC-087
default-path pin CLEAN (extraction gated on `$_ROS_SLOG`; the `else` branch at orchestrate.sh
byte-unchanged) and additive-marker safety CLEAN (every ledger reader keys on `$2=="GATE|START|
ACTION"`; a `| TOKENS |` line is invisible to check/override/descent/_rows/ship-gate). Folded:

- **rid drift (F1):** factored `_rid_for <dir> <id>` in orchestrate.sh; both `_emit_start` and the
  token hook call it, so START + TOKENS land in the SAME `<rid>.log`.
- **result-line double-count (F5):** `sum_usage` filters to `cc._is_assistant` (a `type:"result"`
  cumulative event is not an assistant entry, so it is skipped). Added fixture
  `tests/fixtures/handoff-det/usage-with-result.jsonl` as the real NC (result line with 999999
  cumulative usage; sum-usage returns the assistant-only 100/10/50/0).
- **report join (F4):** the token section is a SECOND awk (`_token_agg`) joining `$2=="TOKENS"`
  totals to lane via `_rows` rid->lane, NOT a `_rows` extension.
- **render collision (F6):** `render()` consumes a leading `--mermaid`/`mermaid` as a MODE before
  its substring-filter positional; ASCII `render [filter]` stays byte-compatible (NC pinned).

## Decisions made during implementation (not in the spec)

- **macOS BWK-awk portability (caught locally, CI runs macOS):** (1) median uses an INSERTION SORT,
  not `asort` (gawk-only). (2) `render --mermaid` passes per-lane medians as a SINGLE-LINE
  `lane=med;` map via `-v` , a multi-line string in `-v` throws "newline in string" on BWK awk.
- **mermaid node IDs sanitized** to `[a-zA-Z0-9_]` (`nid()` in the awk); a lane/type like
  `spec-feature` would otherwise emit an invalid hyphenated mermaid ID (label stays quoted/verbatim).
- **cost sanitization** allows one decimal point (`tr -cd '0-9.'`); the four token counts are
  integer-only (`tr -cd '0-9'`). A naive digits-only strip mangled `0.05`->`005`.
- **"real captured orchestrate run" = the kit's mock `CLAUDE_CMD` (`claude-dh`) through the REAL
  path** (test-orchestrate SPEC-110 block): DETERMINISTIC_HANDOFF=1 + a goal file with `**Branch:**`
  -> capture -> `_rid_for` -> `sum-usage` -> `gate-ledger tokens` -> TOKENS line with the seed sum
  (in=7200 out=480 cache_read=24000). Deterministic + reproducible; no nondeterministic/costly live
  LLM call. NC: the default no-capture path writes no TOKENS line.

## Sidechain probe (goal item 6)

`isSidechain` is present on every stream-json entry and `usage` is per-assistant-message, so
per-round / per-subagent separation IS technically possible (filter by `isSidechain` + `parentUuid`).
v1 sums all assistant usage into the RUN total (run-granularity) by design; per-round rework share is
a viable FOLLOW-UP, not impossible , filed to mega NOTES.

## Review (SHIP) , 3 LOW findings dispositioned

Multi-lens review verdict SHIP; all lenses verified against real code + an adversarial injection
run. LOW findings: (1) `cost` allowed multiple dots , comment corrected to match (display-only,
never summed), no strict-single-dot enforcement needed. (2) re-run TOKENS lines accumulate into a
run's tokens-to-done , CONSCIOUS: that is the true total incl. retries (unlike gate coverage which
dedups); left as-is. (3) a malformed non-integer usage value would crash `sum_usage` , FIXED with a
`_int()` guard (skips to 0), so a direct CLI call on a malformed stream no longer tracebacks.

## Not touched (scope)

WORKFLOW.md carries no token/usage over-claim to reconcile (its `token` mentions are the unrelated
tool-output offload lever), and it is not in 03's scope, so it is left unedited (no unrequested
change). The token telemetry is discoverable via `lane-telemetry report` / `render --mermaid`; the
docs sub-goal (02) will index it. TIER-4's no-orphan check confirms every new artifact dispatches.
