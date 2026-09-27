# Retro: wrap absorbed-content merge proof (SPEC-331)
Date: 2026-09-28
Sprint: 2026-09-27 to 2026-09-28, one session

Answers below were drafted by the lead from the session record, not collected one question at a time; the operator ended a seven-hour session and can correct them.

## Metrics
- Tasks planned: 2, completed: 2, deferred: 0 (the loose ref resolution in the older proofs was cut from SPEC-331 and shipped the same session as #794)
- PRs: #793 (absorbed proof, 8 files, +515/-8), #794 (pinned proof refs, 4 files, +387/-17), #795 (negctl pointer)
- Revisions of `_absorbed` before merge: 6; validation rounds: 5, every one NEEDS REVISION
- Tests: `test-wrap.sh` 1403 to 1486
- Real flow: 2 of 6 archived ops-toolkit agent branches read ABSORBED; the installed kit read all 6 as LEAVE

## What worked
- Fresh-context adversarial validators on Opus. Each round reproduced a concrete fail-open in a scratch repo: merge drivers faking a trial merge, SIGPIPE 141 under pipefail, a here-string temp file, a vanished `<(...)` operand, locale truncation on a backslash before an invalid byte. None of the five would have surfaced from the author's own tests.
- "Red on the prior revision" as the bar for every new test. Two fixtures that passed on both revisions turned out to test nothing (an APFS-refused file name silently never committed; an ASCII-only fixture never left bash's fast path), and the bar exposed both.
- Archiving to `origin/archive/*` before removing any worktree by hand, so the 17-worktree cleanup was reversible and later fed the real-flow proof.

## What hurt
- The first build shipped a trial-merge proof in about ten minutes; the eventual answer (tree identity, pure-bash comparison, ASCII-forced lists) took five rounds. The spec named the mechanism before anyone attacked it; the design gate was skipped as "obvious".
- Each I/O-based comparison had its own fail-open shape, and the author fixed them one at a time instead of asking once what the comparison must never do (read any failure as "no overlap").
- A review of the follow-up found a regression the worker introduced (`update-ref -d` following a symref), and the lead's own quick fix for the last finding briefly reintroduced the SIGPIPE shape and then dropped the last list line. Hand fixes late in a long session were the least reliable step.
- zsh as the interactive shell broke several ad-hoc commands (`$b:r` modifiers, no word splitting, noclobber, rejected non-UTF-8 names), each costing a retry.
- The lane classifier flagged the word "audit" (event-bridge's `BRIDGE_AUDIT` log) as audit-security and sized a one-line doc pointer as full.

## Action items
- [ ] State the fail-closed invariant up front for any proof that authorizes a delete: "every failure between the reads and the verdict must read as NOT proven". Add it to `commands/spec.md`'s guidance for kit-machinery specs -- owner: @tieubao -- deadline: 2026-10-05
- [ ] Classifier: stop matching "audit" inside an identifier or an "audit log" phrase, and pin the event-bridge wording as a truth-table row -- owner: @tieubao -- deadline: 2026-10-05
- [ ] Bare `origin/${def}` remains in the stray-commit, pull, merge, land, rebase and start paths; decide whether any of those gates a write that a colliding ref could misdirect -- owner: @tieubao -- deadline: 2026-10-12

## Lane telemetry disposition
- `wrap-absorbed-proof` (full) reads shipped-incomplete: validate closed by `override` after five NEEDS REVISION rounds, never an APPROVED. Accepted noise: every in-scope critical was fixed and pinned by a test red on the prior revision; the override records that call.
- The classifier "audit" misfire goes to action item 2.

## Kit feedback
- `negctl.sh` already covered the prior-revision check; the session hand-rolled it five times until #795 added the pointer.
- `wrap land` + `deploy-wait` + `wrap start` made the multi-PR loop cheap; no friction there.
