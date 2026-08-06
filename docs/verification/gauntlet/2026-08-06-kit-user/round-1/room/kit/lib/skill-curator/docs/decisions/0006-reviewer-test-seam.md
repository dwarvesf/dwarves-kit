# ADR 0006: a test seam for the `claude -p` call (`SKILL_CURATOR_REVIEWER_CMD` / `SKILL_CURATOR_CURATOR_CMD`)

**Date:** 2026-06-19
**Status:** accepted

## Context

The reviewer and curator are mostly bash logic (parse, secret-scan, stage, archive, ledger) wrapped
around one `claude -p` call. Testing that logic against a live model would be slow, non-deterministic,
quota-spending, and impossible in CI. But the logic is exactly where bugs live and where the security
guarantees (no-write, secret-drop, path-safety, never-delete) must be proven.

## Decision

Isolate the model call behind an env override: `SKILL_CURATOR_REVIEWER_CMD` (and `SKILL_CURATOR_CURATOR_CMD`). When
set, the wrapper runs that command instead of `claude -p`; it must read the prompt on stdin and emit
a `claude -p --output-format json` ENVELOPE on stdout. Tests build envelopes with `jq -n` (no hand
escaping) and point the seam at `cat <fixture>`. The default (unset) is the real `claude` invocation.
This mirrors cc-harvest's `CC_HARVEST_EXTRACTOR`. Every parse / stage / secret-drop / archive / ledger
path is then deterministic and tested with no live model (58 checks across 10 test files).

## Alternatives considered

- **Mock the `claude` binary on `PATH`.** Rejected: global, fragile, leaks across tests.
- **Live-only tests.** Rejected: slow, flaky, quota-spending, un-runnable in CI; the security paths
  would go untested.

## Trade-offs

The seam is a (tiny) production surface that a misconfigured env could repoint. Accepted: it is the
same pattern the sibling tool uses, and the test value is large. The async/timing paths still use
real detachment (sleep-mock reviewers), so the seam does not hide the non-blocking guarantee.

## Open questions

None.
