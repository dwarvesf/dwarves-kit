# ADR 0009: two-layer JSON parse + always-exit-0 (safe-to-wire)

**Date:** 2026-06-19
**Status:** accepted

## Context

Two consequences fall out of "the model has no write" (ADR-0001): the wrapper must extract both the
COST and the model's ANSWER from the `claude -p` output, and the whole thing runs as a hook that must
never break the operator's session.

## Decision

**Two-layer parse.** `claude -p --output-format json` returns an ENVELOPE: `.total_cost_usd` +
`.usage` (logged to the ledger, the cost-observability requirement) and `.result` (the model's text).
`.result` is itself the model's JSON `{draft|null, reason}` (reviewer) or `{clusters, archive,
report}` (curator). The wrapper parses the envelope, then parses `.result`, tolerating a stray code
fence or a trailing canary line. A failure at either layer logs and produces no draft (Edge Case 2 in
the spec).

**Always exit 0.** Every reviewer/curate path returns 0 on any failure (missing `claude`, auth
expired, malformed JSON, empty transcript, lock held, write error): log a line and move on. A
self-improvement run must never block a compaction/stop or fail a session. The ledger records a
`note` (`no-output`, `bad-json`, `null-draft`, `dropped-secret`, `staged`) so a silent no-op is still
auditable.

## Alternatives considered

- **Single-layer parse** (assume `.result` is already the final shape). Rejected: loses the
  envelope's cost/usage, which is the whole cost-observability acceptance.
- **Fail loud on a bad model response** (non-zero exit). Rejected: a hook that exits non-zero risks
  perturbing the session; the design contract is that the loop is invisible unless it has something to
  stage.

## Trade-offs

A genuinely broken reviewer fails silently (you only notice via an empty `cc-improve status` or the
log). Accepted: the alternative (a self-improvement bug breaking real work) is worse. The ledger
`note` field is the audit trail that makes the silence diagnosable.

## Open questions

None.
