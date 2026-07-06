# Verification: SPEC-143 stale-adr-inversion

Real dispatch, not a hand-simulated transcript: each run below is a genuine
`kit:code-reviewer` (architecture lens) subagent invocation via the Task tool, reading
real files on disk. The fixture and both prompts are reproducible from this file.

## Fixture

```
$FIXTURE/
├── cache.go                              # matches its ADR (by-design case)
├── retry.go                              # drifted from its ADR (drift case)
└── docs/decisions/
    ├── ADR-0099-cache-ttl.md             # "MUST expire entries after 300 seconds"
    └── ADR-0100-retry-budget.md          # "MUST retry at most 3 times"
```

`cache.go`:
```go
package cache

import "time"

// TTL controls how long a cached response is served before refetch.
// Per ADR-0099, this must be 300 seconds.
const TTL = 300 * time.Second

func IsExpired(cachedAt time.Time) bool {
	return time.Since(cachedAt) > TTL
}
```
`TTL = 300 * time.Second` matches ADR-0099 line 7 ("MUST expire entries after 300
seconds") exactly -- the seeded BY-DESIGN case.

`retry.go`:
```go
package retry

// MaxAttempts bounds outbound retries before giving up.
const MaxAttempts = 5

func ShouldRetry(attempt int) bool {
	return attempt < MaxAttempts
}
```
`MaxAttempts = 5` contradicts ADR-0100 line 7 ("MUST retry at most 3 times") -- the
seeded DRIFT case. No comment in the code discloses the drift (an earlier fixture draft
had a self-labeled "DRIFT" comment; removed so neither run gets a free hint).

## Run 1: WITH the stale-ADR rule (the rule text now injected into `commands/review-team.md`'s Architecture-lens dispatch prompt, byte-identical to `agents/advisor.md`:37 and `commands/review.md`:26)

Dispatched via `Agent(subagent_type: "kit:code-reviewer")` with the exact Architecture
lens prompt from `commands/review-team.md` (post-SPEC-143), pointed at the fixture.

Result (verbatim from the agent):
```
1. PASS (by-design): cache.go -- TTL = 300 * time.Second matches
   ADR-0099-cache-ttl.md:7 ("MUST expire entries after 300 seconds"). No finding.

2. stale-adr: docs/decisions/ADR-0100-retry-budget.md:7 claims "retry at most 3
   times", retry.go:4 does `MaxAttempts = 5`
   File: retry.go:4
   What: The retry budget has drifted from 3 (ADR-0100) to 5 attempts, widening
   worst-case latency under a flapping dependency beyond what the ADR bounds.
   Fix: Either update MaxAttempts to 3 to match ADR-0100, or if 5 is now the
   intended value, revise ADR-0100 to reflect the new decision.
```

**Outcome: the drift case is REPORTED as a `stale-adr:`-prefixed finding naming the
doc line (`ADR-0100-retry-budget.md:7`) and the code line (`retry.go:4`); the by-design
case is explicitly PASS/no-finding.** Exactly the two-sided behavior the rule specifies.

## Run 2: WITHOUT the rule (negative control -- baseline Architecture-lens prompt, no stale-ADR text)

Same fixture, same agent type, same two ADRs handed as "Architecture context", but the
dispatch prompt omits the stale-ADR inversion paragraph (i.e. `commands/review-team.md`
as it existed before this SPEC).

Result (verbatim from the agent):
```
Both files are minimal, deep modules for their size... No dead code, no unreachable
branches, no new abstractions, no coupling...

## Issues found
None.

Note: I did not cross-check the numeric constants (TTL = 300s, MaxAttempts = 5)
against the ADR text as a distinct step, per the instructions for this run. I did
notice the cache.go comment cites ADR-0099 inline, but did not open the ADR files to
verify the value matches.
```

**Outcome: with the rule absent, the reviewer does not open the ADRs at all and reports
zero findings -- the same drifted `retry.go` that Run 1 catches is invisible.** This is
the negative control: revert the rule (drop the injected paragraph) and the true
positive goes RED (unreported). Restoring the rule (Run 1) turns it back GREEN.

## Reproduce

```bash
# 1. Recreate the fixture files above under $FIXTURE (any temp dir).
# 2. Dispatch kit:code-reviewer with the Architecture-lens prompt text from
#    commands/review-team.md (with the rule) -> expect the stale-adr: finding.
# 3. Dispatch the same agent with the rule paragraph removed -> expect silence.
```

## Verdict

PASS. The rule as injected produces the two-sided behavior required by SPEC-143's
acceptance criteria 2 and 3: a seeded code-vs-ADR contradiction is reported with a
`stale-adr:`-prefixed finding-key naming both lines; a seeded by-design match is not
flagged. The negative control (rule removed) shows the drift going undetected,
confirming the rule -- not incidental reviewer thoroughness -- is what closes the gap.
