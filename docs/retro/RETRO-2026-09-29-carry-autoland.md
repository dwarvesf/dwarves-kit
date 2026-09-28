# Retro: wrap apply lands its own carry PRs (SPEC-322)
Date: 2026-09-29
Sprint: 2026-09-26, one session; merged the same day, knob on the same day

The lead drafted these answers from the session record. They were not collected one question at a time, and the operator can correct them.

## Metrics
- Tasks planned: 6, completed: 6, deferred: 0
- PRs: dwarves-kit #782 (9 files, +676/-12, merged 2338cdff), dotfiles #579 (turned `wrap.autoland_carry` on)
- Tests: `test-wrap.sh` 1243 to 1264, 56 new autoland checks; negctl PASS on the knob gate
- Validation rounds: 3 (NEEDS REVISION, NEEDS REVISION, APPROVED), one fresh-context Opus reviewer resumed each round
- Live: 15 carry PRs merged on ops-toolkit since 2026-09-26. The 4 hand-opened ones (#3419, #3422, #3467, #3468) all predate the knob; the other 11 carry the autoland PR body.

## What worked
- Reusing `cmd_merge --pr` in a subshell meant the carry path reached every gate the own-PR merge already had: the re-merge on CONFLICTING, the pinned squash and the tree verify. It needed no second merge path.
- The adversarial reviewer found two holes the author's own tests could not reach. Opening the PR makes any branch "own", so the own-PR check no longer blocked foreign content. And a push during the check wait would have landed unchecked. Each became a test that fails without the fix.
- The handoff pinned the anchors, the landmines (CONFLICTING right after create; do not test against the shared checkout) and the knob-default decision. The session started building without re-deriving any of them.

## What hurt
- The first spec draft trusted authorship as the safety check. It took round 1 to see that `gh pr create` manufactures authorship. Content validation (`_carry_branch_ours`) and oid pinning came after.
- Three bash traps cost a rerun of the three-minute suite each:
  - `${var/%pat/rep}` anchors at the end, so a `%CARRY_TIP%` pattern silently never matched.
  - `awk 'FNR == NR'` misreads the second file when the first is empty.
  - A test helper hard-set `KIT_WRAP_CARRY_CHECKS_SECS=0`, which masked the caller's override, so the settle test passed without testing anything.
- The lead recorded `Validate ran APPROVED` in the gate ledger before round 3 had returned. Round 3 then approved, but the record ran ahead of its evidence.
- Three hook false positives, each costing one retry:
  - secret-guard read the word "set" in heredoc prose as an env dump.
  - branch-guard blocked a fixture script whose only push targeted a local bare repo.
  - sleep-guard blocked a 60s wait on a background job.

## Action items
- [ ] Spec guidance for flows that open a PR and then merge "own" PRs: authorship is created by the flow itself, so the gate must check content and pin the checked oid. Fold into the fail-closed invariant item from RETRO-2026-09-28 in `commands/spec.md` -- owner: @tieubao -- deadline: 2026-10-05
- [ ] gh test stub: answer `pr create` with a per-call number (a counter file, like the `view` counter), so a flow that opens two PRs can tell them apart and the autoland squash-fallback supersede path gets a test -- owner: @tieubao -- deadline: 2026-10-12

## Lane telemetry disposition
- `carry-pr-autoland` shows no misfire and no shipped-incomplete line. Nothing to dispose.

## Kit feedback
- `wrap start` plus `wrap land` made the cross-repo knob flip (dotfiles #579) one commit and one command.
- `negctl.sh` ran the negative control first try, but it cannot share a worktree with a concurrent test run: the reviewer's own suite run overlapped it and could have read the mutated file. Keep reviewers read-only on a different checkout during a negctl.
