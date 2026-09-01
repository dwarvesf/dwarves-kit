# Logging and observability rules

Distills the OWASP Logging Cheat Sheet and the observability section of Microsoft's Engineering Fundamentals Playbook. Complements `notification-design.md`, which covers alerting; this file covers what and how to log in the first place.

## What to log
- Log events, not just errors: an operation's start and end, state transitions, anything an on-call version of you would need to reconstruct what happened without re-running the code.
- Every log line carries a correlation ID (a request/trace ID) so related lines across a flow can be tied together. For a one-shot CLI or cron job, a per-run ID (timestamp+pid) stamped on every line IS the correlation ID; skip distributed request tracing until there are actually multiple services to tie together.
- Never log secrets, credentials, or full PII. Redact or hash sensitive fields before they reach a log line (per the OWASP Logging Cheat Sheet).

## Levels
- `error`: the operation failed and needs attention. `warn`: degraded but recovered. `info`: normal operational events worth keeping. `debug`: detail only useful while actively debugging, off by default in production.
- A log line's level should match what action it demands, not how interesting it felt to write.

## Structure
- Structured (JSON or key-value) logs over free-text prose, so they are queryable later. A human-readable summary field is fine alongside the structured fields, not instead of them.

## Sources
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
- [Microsoft Engineering Fundamentals Playbook, Observability](https://microsoft.github.io/code-with-engineering-playbook/observability/)

Verified: 2026-07-29.
