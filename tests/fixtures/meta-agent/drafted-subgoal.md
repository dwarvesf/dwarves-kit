<!-- DRAFT , review before use. Drafted by meta-agent. Not installed. -->
# Sub-goal 03: Exponential-backoff retry for the API client

**Merge policy:** auto (machine-verifiable Done: a passing retry test suite + a clean run, no taste or money call)
**Time budget:** 1-3 hours of loop work
**Proof:** run-table (test command + exit + stdout) + negative control (a forced non-retryable 4xx that fails fast, proving the retry is selective)
**Depends on:** none
Model: sonnet
Effort: medium
**Branch:** feat/api-client-03-retry
**PR base:** main

## Outcome

The API client transparently retries transient failures (HTTP 429 and 5xx) with exponential backoff and jitter, so a brief upstream blip no longer fails the whole run. Non-retryable responses (other 4xx) still fail immediately, and a bounded attempt cap prevents an infinite loop.

## Quality bar

Retry logic lives in one place in the client, not scattered at call sites. Backoff respects a `Retry-After` header when present, falls back to exponential `base * 2^attempt` plus jitter otherwise, caps total attempts, and surfaces the final error (with attempt count) when the cap is hit. No bare `sleep` in a tight loop; no retry on 4xx other than 429.

## How to close the loop

Run the retry-specific tests and capture the table:

- `<test-runner> path/to/test_retry.*` , covers: 429 then 200 succeeds; 503 x2 then 200 succeeds; persistent 500 exhausts the cap and raises with the attempt count; a 400 fails on the first try with NO retry (the negative control).
- Grep the client to confirm single-site retry: `grep -rn "backoff\|retry" <client-module>` shows the wrapper, not per-call copies.
- Capture the run-table (command + exit code + real stdout) into the PR body. Capture the 400-fails-fast case as the named negative control row.

**Done =** the four retry tests pass (429-recovers, 5xx-recovers, cap-exhausts-and-raises, 400-fails-fast-no-retry) in one recorded run, AND the 400 negative-control row shows exactly one attempt, both rows present in the captured run-table.

## Handoff on completion

When this sub-goal is done, before exiting:

1. Flip this sub-goal's ROADMAP.md box to `[x]` and record its PR #. The orchestrator advances only on the flipped box, never on a chat claim.
2. Overwrite the HOT `HANDOFF.md` with the next sub-goal, its exact FIRST action (a concrete accomplishment with evidence, not "continue"), and read-pointers as `file:line`.
3. Append durable invariants + dead-ends to the WARM `DECISIONS.md` ledger (e.g. "jitter is full-jitter, not equal-jitter, decided to avoid thundering herd", "Retry-After takes precedence over computed backoff").
4. Report findings IN these records, not in response text, then EXIT IMMEDIATELY. Do not keep working past Done.

Working rhythm: a one-line progress note every 3-5 tool calls so a watching human can intervene.

## Scope edges

**In:** the API client's request wrapper, its backoff/jitter helper, and the retry test file.
**Out:** call-site signatures (the retry is transparent; callers do not change), unrelated client methods, logging infrastructure beyond the final-error attempt count.
**Not:** a circuit breaker, a global rate limiter, request hedging, or a config UI for retry knobs. Constants (base delay, max attempts) live in code, not a new settings surface.

## Where to look

The HTTP client module (the single place outgoing requests are issued), its existing error-handling path, and the client's test directory. The transient-vs-permanent decision belongs next to where status codes are already inspected.

## PR body

Add exponential-backoff retry to the API client so transient 429/5xx responses no longer fail the run.

- Retries 429 and 5xx with exponential backoff + jitter, honoring `Retry-After`; bounded attempt cap; other 4xx fail fast.
- Verify: `<test-runner> path/to/test_retry.*` (429-recovers, 5xx-recovers, cap-exhausts, 400-fails-fast); run-table in this PR includes the 400 negative-control row.
- Roadmap: see ROADMAP.md sub-goal 03.

## Notes
