---
description: "The full independent-verification battery for a finished branch: a fresh-context acceptance verifier that RE-EXECUTES the verification commands against a stated baseline, a multi-lens review, and the kit:advisor extra lens, dispatched in parallel at prescribed model tiers, findings merged into one verdict, fixes applied by the lead."
---

You are running the verification battery on a finished build (a branch, a PR, or the
active spec's diff). The build's own orchestration already ran; your job is the
INDEPENDENT right arm: fresh-context agents that did not write the code, re-executing
and re-reading it. Never "review" inline in the session that wrote the code and call
it the battery.

## Scope and triggers

The multi-lens review runs single-pass minimum, with domain lenses on escalation. This battery exists because independent arms catch DISJOINT defect classes: on one measured diff the panel, the reviewer, the verifier, and a late security lens each found a defect the other three missed.


Bracket the phase for timing before dispatching any arm: `bash lib/gate/gate-ledger.sh outcome <rid> battery start` (rid = the branch slug, the same key the ship-gate reads; the ledger counts `battery` as the review gate). For a foreign target the ledger writes under the run dir of the cwd repo, not the target repo. Run the two `gate-ledger.sh` calls from the target repo's primary checkout root in a subshell (`(cd <repo> && bash ...)`), or accept the record landing under the session repo.

## Target (optional argument)

Resolve the target FIRST, before the bracket and before any dispatch.

| Argument | Resolves to |
|---|---|
| none | the cwd repo, its current branch, compare ref `origin/<default branch>` |
| a worktree or repo path | that checkout's branch, its repo's default branch as compare ref |
| `owner/repo#N` or a PR URL | `gh pr view N -R owner/repo --json headRefName,baseRefName,headRefOid`; compare ref is the PR base |

Read a repo's default branch from `git -C <path> symbolic-ref --short refs/remotes/origin/HEAD`.

For a PR target, find a local checkout of that repo under `~/workspace/<owner>/<repo>`, or any `git worktree list` entry already on the head branch. If no worktree holds the head branch, stop and tell the lead to create one at `<repo>/.claude/worktrees/<slug>` on that branch before dispatching. Never branch-switch a primary checkout.

Print the resolved target as a `## Target` block: path, branch, compare ref, PR number when one exists.

## When this runs

- The operator says "run the battery" / "overtest this" / "full check before merge".
- At the end of any normal/full-lane cycle where /kit:execute's pipeline ran but no
  fresh-context review/verify did.
- NOT for tiny-lane one-line changes (verify inline or skip with a stated reason),
  and NOT a replacement for the ship-gate (this battery FEEDS it: record its legs in
  the gate ledger under the branch slug).

## The three legs

| Leg | Agent | Model tier | Job |
|---|---|---|---|
| 1. Acceptance verify | kit:acceptance-verifier (or kit:task-verifier for a single task) | mid, or the spec's tier when it carries `Model: opus` | re-execute the spec/branch verification commands VERBATIM in fresh context; check every AC against the actual files |
| 2. Review | kit:code-reviewer single-pass; escalate domain lenses per the table below | Sonnet (mid) on the normal lane, high (Opus-class) on the full lane | static-read judgment: what re-execution cannot see |
| 3. Advisor | kit:advisor (critique mode) | mid | the uniform extra lens; additive, never replaces leg 2 |

Dispatch legs 1 and 2 IN PARALLEL (one message, multiple Task calls). Leg 3 rides
leg 2's dispatch unless the diff is large. Every leg is read-only; the LEAD applies
fixes.

## Lens escalation

Add specialized lenses when the diff touches their domain; each is its own agent:

| Diff touches | Lens | Tier |
|---|---|---|
| secrets, keys, symlinks, subprocess, network, containers, persist paths | kit:security-reviewer | high |
| a public interface / request-response shape | kit:api-reviewer | mid |
| UI | kit:frontend-reviewer | mid |
| deploy, CI, IaC, launchd | kit:infra-reviewer | mid |
| hot paths, N+1, allocations | kit:performance-reviewer | mid |
| input handling, a trust boundary, a state machine, or a stated numeric/format contract, WITH tests | kit:break-it | high |

The measured lesson behind the escalation rule: a diff that qualified for the
security lens shipped without it, and the lens later found a HIGH (a key-persist
path into a public repo) that the panel, the reviewer, AND the verifier had all
missed, because each looked from a different frame and none from the threat model.
Skipping a qualifying lens is a decision; record it, do not default into it.

## Probe rung (kit:break-it), before the mutation rung

**kit:break-it is the one escalation lens that does NOT ride leg 2's parallel dispatch.** Every
other row in the table above goes out in the same message as legs 1 and 2. This one needs leg
1's verdict first, because a red suite makes the probe meaningless, so it is a SECOND dispatch
after leg 1 returns green. Leg 1 green is the trigger; the table row is the domain filter.

A green suite proves the tests ran, never that they constrain the code. Three rungs answer
that in order:

1. **Coverage** -- leg 1 above returns green.
2. **Probe** -- `kit:break-it`, the escalation lens in the table above, dispatched only after leg 1
   returns green. It hunts one concrete input or call sequence the suite does not constrain,
   and returns `PROBE: <N>` or `NO-PROBE`.
3. **Mutation** -- `lib/gate/mutation-smoke.sh`, owned by `/kit:verify` Step 6b. Battery never
   invokes it: one engine, one call site.

A `PROBE` finding STOPS the ladder. The suite has a proven hole, so the mutation rung is not
spent on code already known to be under-constrained; the lead adds the test or accepts, and
mutation-smoke runs on the next pass. `NO-PROBE` is what clears rung 3 to run.

The order is stated here, not enforced. `/kit:verify` can run before this battery, inverting
probe and mutation; report that inversion in one line and re-run nothing.

## Non-negotiable prompt ingredients (every leg)

1. The resolved `## Target` block verbatim: path, branch, compare ref, PR number
   when one exists. Thread it into EVERY leg; no leg infers the target from its
   own cwd.
2. The BASELINE: the pre-existing failure set, stated numerically ("suite has 9
   known failures; FAIL only on NEW failures"). A battery without a baseline
   converts known debt into false alarms. The lead states it. For a foreign
   target, read it from the PR body's proof section or the repo's known-failures
   note.
3. Verifier: "execute the commands verbatim; report actual output"; name any
   fixture it must build.
4. Reviewers: the lens list, findings by severity with file:line quotes, a verdict
   grammar (SHIP / FIX THEN SHIP / DO NOT SHIP), a line cap, default-skeptical
   framing ("try to refute").
5. Read-only instruction: report, never edit.

## Brief skeletons

Fill the `<...>` slots; every skeleton carries the five ingredients above (Target block, baseline, read-only), so they are not restated per leg. A line marked `(if X)` drops out when X does not apply.

Leg 1, verifier (kit:acceptance-verifier):

```
<## Target block verbatim>
Baseline: <N known failures, named>; FAIL only on NEW failures.
Spec section: <path>#<## Verification or the AC list>
Job: re-run the proof's commands VERBATIM in fresh context and quote actual output. Then run ONE
independent real-data check the proof did not (a recorded input, a live read, a different path
to the same claim) and say what it was.
(if port or old-vs-new parity) Run parity on REAL recorded data in STRICT mode: broad
"explained" classes disabled, every difference counted as a difference. Report the strict count.
Fixtures to build: <list or none>. Scratchpad: write any commit message or temp file to a fresh
`mktemp`, never a fixed name shared with other workers.
Verdict: VERDICT: PASS | FAIL:fixable | FAIL:escalate, plus the Verification record block.
Cap: <300> words. Read-only.
```

Leg 2, reviewer (kit:code-reviewer, or a lens from the escalation table):

```
<## Target block verbatim>
Baseline: <N known failures, named>.
Spec section: <path>#<the ACs and non-goals the diff must honor>
Lens: <security | architecture | test-coverage | ...>. Try to refute: find what re-execution
cannot see. Findings by severity, each with a file:line quote.
(if a parity or proof instrument exists) Also review the instrument: does the classifier,
allowlist, or "explained" class over-explain, passing a deliberately wrong output? Name the
class and the input that would slip through.
(if re-review after a fix round) Scope to `git diff <first-review-head>..HEAD` plus your own
prior probe script <path>; re-run that script, do not re-review untouched files.
Verdict: SHIP | FIX THEN SHIP | DO NOT SHIP.
Cap: <400> words. Read-only.
```

Leg 3, the extra lens (kit:advisor, critique mode):

```
<## Target block verbatim>
Baseline: <N known failures, named>.
Spec section: <path>#<the goal or problem statement>
Job: the uniform extra lens over the whole work, additive to leg 2. Surface only what the
other legs' lenses would not: wrong goal, missing case, scope drift, a claim the proof does
not support. Do not repeat leg 2's findings; skip what leg 2 already holds.
Verdict: ADVISORY: clean | ADVISORY: N finding(s), numbered, each with file:line.
Cap: <250> words. Read-only.
```

Break-it (kit:break-it, dispatched only after leg 1 returns green):

```
<## Target block verbatim>
Baseline: <N known failures, named>; leg 1 returned green at <head sha>.
Spec section: <path>#<the input, state-machine, or numeric/format contract under test>
Job: find ONE concrete input or call sequence the green suite does not constrain, one that
changes behavior without failing any test. Run it against the code, quote the output.
(if re-probe after a fix round) Scope to `git diff <first-probe-head>..HEAD` plus your own
prior probe script <path>.
Verdict: PROBE: <N> with the input and the unconstrained line, or NO-PROBE naming what was tried.
Cap: <250> words. Read-only; never write the test.
```

## After the legs return

1. Merge findings, de-duplicate, severity-order.
2. Apply every fix the lead agrees with; re-run the SPECIFIC failed check per fix,
   not the whole battery.
3. A verifier-caught gap means an AC or test was too weak: strengthen the check in
   the same pass, not only the code.
   - Decide per kit:break-it finding: add the test that pins the probe, or accept the
     finding and record WHY in the report. A `NO-PROBE` verdict is a result, not
     silence; say so in the report so the lead does not read it as laziness.
4. Write the spec's `## Review` section (replace-not-stack) and record the legs in
   the gate ledger under the BRANCH SLUG: `bash lib/gate/gate-ledger.sh record <rid> battery ran "<verdict> arms=<n> caught=<n>"`
   (the slug, never a board ID, is what the ship-gate reads). Then close the
   timing bracket: `bash lib/gate/gate-ledger.sh outcome <rid> battery end caught=<true if any arm found a defect, else false>`.
5. Name what each arm caught in the report. Disagreement between arms is the
   signal this battery exists to produce.
