# Retro: subagent-panes (SPEC-234, ID-486)

One-cycle retro for the read-only jsonl-tail panes feature (ops-toolkit ID-272 pickup).

## What worked

- The validate lenses earned their cost BEFORE build: the advisor falsified two spec
  claims by experiment (bare `jq` dies on a malformed input line; the conductor cannot
  name transcript paths at dispatch), either of which would have shipped an unreachable
  or self-killing feature that unit tests could have gone green on.
- The scout-first shape (read-only map of orchestrate.sh + SPEC-119/121 + NOTES.md
  before any design) caught that the backlog row's own framing was wrong twice over:
  "item 9" was already shipped as SPEC-121, and orchestrate.sh has no subagent dispatch
  loop to hook.
- Worker honesty held under pressure: the implementer proved the spec's literal `viz`
  gsub broken in jq 1.8.2 and replaced it with a behavior-identical codepoint filter,
  logging the deviation instead of shipping the spec-faithful-but-insecure text.

## What did not

- The proof doc over-claimed a green regression suite; the fresh recheck-verifier
  caught `test-orchestrate-wavefront.sh` as pre-existing timing-flaky (rc=1 on 3/3
  fresh runs, reproducing on the pre-change commit). Recorded run-tables must not
  smooth over a flaky suite as "all rc 0".
- The spec itself briefly contained literal control bytes while describing a
  control-byte strip; fixture rules (generate with printf escapes, never paste bytes)
  belong in the test template, and now do.

## Action items

- Pre-existing, not this cycle's to fix, now on the record: `test-orchestrate.sh` (2
  failing assertions) and `test-orchestrate-wavefront.sh` (3 intermittent timing
  assertions) are red/flaky on master; worth their own board row if they stay that way.
