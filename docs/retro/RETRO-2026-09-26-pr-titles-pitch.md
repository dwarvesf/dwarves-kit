# Retro: step-10 PR titles and the pitch test's dirty tree (SPEC-323, SPEC-324)

Date: 2026-09-26
Sprint: 2026-09-26 (the wrap pass after SPEC-320)

Answers below were drafted from session evidence, not from an operator interview.

## Metrics
- Specs shipped: 2 (SPEC-323 #783, SPEC-324 #784); both normal lane, both validated by a fresh subagent under SPEC-320's new flow
- SPEC-324 was the first live run of the step-10 split: the worker stopped at VALIDATE PENDING, a fresh validator ran, and SendMessage resumed the worker to build

## What worked
- The fixed `spec-next.sh reserve` keyed claims by repository path and handed out 323 and 324 with no collision.
- Fresh validation caught real gaps both times: the full-lane draft's first commit is the spec, so `--fill-first` would title it wrong; and the tracked pitch sample was kept live on purpose, a reason the author missed.
- The new `chk_no` pin caught the author's own prose naming the banned flag.

## What hurt
- The old `--fill` pin matched `--fill-first` as a substring, so it could never have caught the change it existed to guard.
- The ship-gate refused a commit whose message quoted a PR-create command, and refused `--dry-run`, so a flag combination went unprobed.
- `negctl.sh` reported FAIL when the red test run itself wrote a tracked file: its restore set covers only files the mutate command changes.
- A worker named the FEATURES regeneration commit as the feature commit; the lead took the title from the real one.

## Action items
- [x] Step-10 PRs title from the feature commit (#783)
- [x] The pitch test no longer dirties the tree (#784)
- [ ] `wrap land` titles its squash from the feature commit, not the last one -- owner: @tieubao -- deadline: 2026-10-03
- [ ] The ship-gate reads the command, not quoted text inside a commit message -- owner: @tieubao -- deadline: 2026-10-03
- [ ] `negctl.sh` restores tracked files the red run writes, or refuses such a mutation by name -- owner: @tieubao -- deadline: 2026-10-10

## Kit feedback
- A substring pin on a flag is toothless against a longer flag with the same prefix; pin the full token.
