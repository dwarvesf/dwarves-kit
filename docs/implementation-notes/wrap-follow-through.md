# Implementation notes -- wrap-follow-through

Deltas from SPEC-310 and from the operator brief that produced it. Nothing here repeats what the spec already states.

## 2026-09-24 Two booleans became one enum mid-build
- Context: the first brief asked for `wrap.follow_through` as a boolean; the operator then asked for a full-lane option as a second knob, then asked to merge the two.
- Decision/Change: one root-only knob, `wrap.follow_through = "off" | "lanes" | "all"`. `follow_through_full` never shipped.
- Why: three states on one line read as a level, and two booleans admit a meaningless pair (full on, follow off).
- Impact: an unknown value prints one line naming the knob and the allowed values, then runs as `off`. NC3 proves the warning cannot be silenced.

## 2026-09-24 The step 0 stop also keeps steps 1 and 2
- Context: the brief named steps 3, 5 and 6 as the main-checkout writes the stop must keep guarding.
- Decision/Change: the stop scopes to steps 1, 2, 3, 5 and 6. Only isolated-worktree builds (7b and step 10) run past it.
- Why: step 1's `board set` and step 2's commit also write the main checkout, so releasing them would reopen the hazard the stop exists for.
- Impact: NC1 restores the old "leave that repo alone" bullet and turns the scoping test red.

## 2026-09-24 Full-lane PRs open as drafts and their worktree is removed
- Context: the operator approved building full-lane candidates unattended, with the review gate before merge as the one fixed rule.
- Decision/Change: a full-lane build ends as a draft PR, paired with a `REVIEW #<pr>` item in the second report's Needs you. The lead removes that worktree once the draft opens.
- Why: `wrap land` marks a draft ready and merges it, so a later plain wrap could reach the draft through a kept worktree and merge it unreviewed.
- Alternatives considered: operator approval before the full-lane build starts (rejected: the operator chose build-then-review).
- Impact: running `wrap land` or `wrap merge --pr` by hand on the draft still merges it. That stays the operator's explicit act.

## 2026-09-24 Step 10 merges only through the check-gated path
- Context: `wrap land` merges without reading PR checks.
- Decision/Change: step 10 waits on `gh pr checks --watch`, then merges through `wrap merge --apply --pr`. The lead pushes from inside each worktree so the home repo's ship-gate judges the push, and a gate refusal is never overridden.
- Why: a follow-through merge happens with nobody watching, so it must pass every gate a watched merge passes.

## 2026-09-24 Worker briefs quote FYI text as data
- Context: an FYI row is session-authored prose that may quote repo files.
- Decision/Change: the worker brief is the lead's paraphrase, with any repo text quoted as data, never pasted as instructions.
- Why: FYI text carried into a worker prompt verbatim is an injection path.

## 2026-09-24 Open questions and known limits
- The phase is model-executed prose in `commands/wrap.md`. Tests pin its wording, the lint and the resolver; no live `/kit:wrap follow` run has happened yet. The first real run is the proof still owed.
- The full-lane worker has never run unattended.
- Pre-existing gap: in a plain wrap, a step 7b `tiny` build ends as a commit that nothing lands. Only step 10 lands it.
- Accepted: `wrap start` fetches before its lock check, and a reflog-only foreign signal still lets it write refs and worktree metadata.
