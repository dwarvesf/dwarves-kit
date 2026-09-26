# Retro: wrap follow-through and fresh-context spec validation (SPEC-315 to SPEC-320)

Date: 2026-09-26
Sprint: 2026-09-26 (one session, after the sustainability-lens cycle)

Answers below were drafted from session evidence, not from an operator interview.

## Metrics
- Specs shipped: 6 (SPEC-315 negctl hint #774, SPEC-316 lens-eval #775, SPEC-318 spec-reserve keying #776, SPEC-319 Reviewer 7 quiet calibration #777, SPEC-317 land ship record #779, SPEC-320 spec auto-validate #780)
- Fresh-context passes that returned REVISE or NEEDS REVISION: 5 of 5 on the four full-lane branches (three design critiques, one code review, SPEC-320's first three validations)
- Live model spend on evals: about $1.70 across five lens-eval runs

## What worked
- Fresh-context review beat self-review every time. Three step-10 workers self-validated as APPROVED; fresh design critiques then returned REVISE on all three, including a CDPATH fail-open in `spec-next.sh` the reviewer reproduced.
- SPEC-320 took four fresh validation passes, and each one found a real defect: an alias that would have credited old self-runs, a preflight grep that matched a failed validation, and a step-10 path that built a failed spec.
- The lens-eval harness paid for itself on its first real run: it separated a scorer artifact (Passed bullets counted as findings) from a real Reviewer 7 leak, then proved the leak fixed (1/3 to 0/3).
- The ship-gate refusing the three full-lane pushes forced real design critiques instead of a quiet override.

## What hurt
- `spec-next.sh reserve` keyed claims by the worktree folder, so three concurrent workers all took SPEC-315 and the lead renumbered by hand.
- A chained `generate && git add -A && git commit` ran inside a stopped rebase and committed conflict markers into `docs/CHANGELOG.md`. It was caught before the push.
- The code review's MEDIUM finding (the preflight grep matched any `ran` line, not the latest) survived four spec validations; only reading the built code found it.
- `gh pr create --fill` titled a two-commit branch `feat/negctl hint`.
- Master sat red on `test-no-scattered-ids` after #778 left a spec id in a `lib/wrap/wrap.sh` comment; #780 carried the one-token fix.
- A lead-side probe in zsh did not word-split a loop variable and reported a false regression for a minute.

## Action items
- [x] Key spec reservations by repository, not worktree folder (#776)
- [x] Every spec gets a fresh-context validator before the build (#780)
- [ ] Never chain a commit after `git rebase`: resolve and `--continue` in one step, check for markers, then commit -- owner: @tieubao -- deadline: 2026-10-03
- [ ] Pass `--title` to every `gh pr create` for a multi-commit branch -- owner: @tieubao -- deadline: 2026-10-03
- [ ] Decide after two weeks of `Validate` outcome data whether the normal-lane cell earns `measure-twice` -- owner: @tieubao -- deadline: 2026-10-10

## Kit feedback
- Lens-eval's `*-any` signals assume a pre-lens base; against a base that already carries the lens they fail by construction. The case file should pin the base per signal, or the README should say so.
- `commands/wrap.md` step 10 now depends on SendMessage to resume a worker; the fresh-builder fallback is untested in a live session.
