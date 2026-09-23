# Retro: recall --tail (SPEC-309)

Date: 2026-09-23
Sprint: 2026-09-23 (one session)

Answers below were drafted from session evidence, not from an operator interview.

## Metrics
- Tasks planned: 1 (SPEC-309), completed: 1, deferred: 0
- Commits: 7 (`326359c` spec, `199de21` spec revision, `324009b` feat, `6e0c396` docs, `230e3a6` review fixes, `b78b812` proof + registry, `9668522` changelog)
- Files changed: 15 (+1067/-26)
- Key commits: `324009b` feat(session): recall --tail shows one session's recent turns; `230e3a6` fix(session): harden recall --tail after review

## What worked
- Precedent find caught the duplicate-shaped work before it started: the first framing was a new `session tail` verb, and precedent moved it to a `--tail` flag on the existing `session-recall`, reusing its helpers instead of forking a second tool.
- `run-all --changed` caught a stray spec id left in a code comment and a stale `docs/FEATURES.md` row, both before review.
- The lead's own real run against live transcripts (313 project dirs) caught the 27 KB no-match error message before the review team ever saw it.
- Origin was a live near-miss, not a speculative feature: a stale handoff nearly caused a duplicate battery, land, and deploy, and the lead had to hand-run `jq` over a peer transcript to see what it was doing. That concrete pain shaped the spec's actual use case (last-turn time + last-write age) instead of a generic "show me a session" ask.

## What hurt
- Validate returned NEEDS REVISION with 2 critical findings: worktree peers unresolvable by default, and subagent mtime ignored. Both are exactly the kind of gap a session-inspection tool cannot afford, and both slipped past the initial spec draft.
- Design critique came back REVISE with 10 findings before any code existed.
- Review team returned FIX THEN SHIP with 12 findings; the top one was real breakage, not polish: slash-command turns opening with `<command-message>` (not `<command-name>` directly) were silently dropped, losing 20 of 41 real slash commands in a live transcript. The spec's own text-matching logic had only been checked against fixtures shaped like the happy path.

## Action items
- [ ] Any future turn-classifying or text-extraction logic (slash commands, tool-call shapes, redaction patterns) gets run against a handful of real, un-curated transcripts before design-critique sign-off, not only hand-built fixtures -- owner: @tieubao -- deadline: 2026-09-30
- [ ] When a spec's Validate pass flags a "resolution defaults wrong for the common case" critical (worktree peers, cross-session identity), add a fixture covering that exact case to the test plan before REVIEW, not after -- owner: @tieubao -- deadline: 2026-09-30

## Kit feedback
- No doc-impact gaps: the diff's companion docs (`docs/CHANGELOG.md`, `docs/FEATURES.md`, `docs/verification/`, `docs/implementation-notes/`) were all updated in-branch.
- No completeness-log or lane-telemetry misfires tied to this cycle; the lane-telemetry report's misfire list has no `recall-session-tail`/`session-tail` entries.
- No undocumented non-obvious decision found: every reversible-with-cost call (home, lane, secret-pattern scope, chunk-boundary decode) is already in the spec's Decision Log or `docs/implementation-notes/SPEC-309-recall-session-tail.md`; no new ADR needed.
