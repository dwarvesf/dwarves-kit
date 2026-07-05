# ADR 0007: wrapper-side secret-drop (defense in depth)

**Date:** 2026-06-19
**Status:** accepted

## Context

A transcript can contain a printed credential (an API key echoed in a command, a token in a log
line). If the reviewer copies it into a draft SKILL.md, the secret lands on disk in
`skill-proposals/`. SPEC-103 put the secret guard in two places: the reviewer PROMPT ("never copy a
secret") and the promote-time checklist. Neither is testable against a mocked model, and the prompt
guard has the same unenforceability problem as ADR-0001.

## Decision

Add a THIRD, trusted-wrapper guard: before staging a draft, `reviewer-run.sh` runs
`contains_secret(body)` (`lib/common.sh`, a high-precision regex set: `sk-ant-`, `sk-...`, AWS
`AKIA`, GitHub `ghp_`/`github_pat_`, Slack `xox[bpras]-`, Google `AIza`, JWT, PEM private keys). If it
matches, the draft is DROPPED (logged, ledger note `dropped-secret`, no file written). The promote
gate scans again on the way into `skills/`. So a secret is caught by the wrapper even if the prompt
guard fails, and "no draft carries a secret" is a hard, testable guarantee.

## Alternatives considered

- **Prompt-only (the spec's original).** Rejected: untestable, unenforceable.
- **Redact-in-place** (strip the secret, keep the draft). Rejected: risks shipping a half-redacted
  secret or a draft that no longer makes sense; dropping the whole draft is safer.

## Trade-offs

The regex is high-precision, so a novel credential format could slip past the wrapper (the prompt
guard + promote scan are the backstops, and `skill-proposals/` is gitignored/unsynced so a slip is
local + transient). A false positive drops a legitimate draft (rare; the operator re-triggers).
Accepted: under-stage beats leak.

## Open questions

Whether to widen the regex set toward a general entropy check is deferred; high-precision avoids
dropping legitimate drafts that merely contain long hex strings.
