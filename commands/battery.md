---
description: "The full independent-verification battery for a finished branch: a fresh-context acceptance verifier that RE-EXECUTES the verification commands against a stated baseline, a multi-lens review (single-pass minimum, domain lenses on escalation), and the advisor extra lens, dispatched in parallel at prescribed model tiers, findings merged into one verdict, fixes applied by the lead. Exists because independent arms catch DISJOINT defect classes: on one measured diff the panel, the reviewer, the verifier, and a late security lens each found a defect the other three missed."
---

You are running the verification battery on a finished build (a branch, a PR, or the
active spec's diff). The build's own orchestration already ran; your job is the
INDEPENDENT right arm: fresh-context agents that did not write the code, re-executing
and re-reading it. Never "review" inline in the session that wrote the code and call
it the battery.


Bracket the phase for timing (SPEC-129) before dispatching any arm: `bash lib/gate/gate-ledger.sh outcome <rid> battery start` (rid = the branch slug, the same key the ship-gate reads; the ledger counts `battery` as the review gate). For a foreign target the ledger writes under the run dir of the cwd repo, not the target repo. Run the two `gate-ledger.sh` calls from the target repo's primary checkout root in a subshell (`(cd <repo> && bash ...)`), or accept the record landing under the session repo.

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
| 1. Acceptance verify | acceptance-verifier (or task-verifier for a single task) | mid, or the spec's tier when it carries `Model: opus` (SPEC-244) | re-execute the spec/branch verification commands VERBATIM in fresh context; check every AC against the actual files |
| 2. Review | code-reviewer single-pass; escalate domain lenses per the table below | high (Opus-class) | static-read judgment: what re-execution cannot see |
| 3. Advisor | advisor (critique mode) | mid | the uniform extra lens; additive, never replaces leg 2 |

Dispatch legs 1 and 2 IN PARALLEL (one message, multiple Task calls). Leg 3 rides
leg 2's dispatch unless the diff is large. Every leg is read-only; the LEAD applies
fixes.

## Lens escalation

Add specialized lenses when the diff touches their domain; each is its own agent:

| Diff touches | Lens | Tier |
|---|---|---|
| secrets, keys, symlinks, subprocess, network, containers, persist paths | security-reviewer | high |
| a public interface / request-response shape | api-reviewer | mid |
| UI | frontend-reviewer | mid |
| deploy, CI, IaC, launchd | infra-reviewer | mid |
| hot paths, N+1, allocations | performance-reviewer | mid |

The measured lesson behind the escalation rule: a diff that qualified for the
security lens shipped without it, and the lens later found a HIGH (a key-persist
path into a public repo) that the panel, the reviewer, AND the verifier had all
missed, because each looked from a different frame and none from the threat model.
Skipping a qualifying lens is a decision; record it, do not default into it.

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

## After the legs return

1. Merge findings, de-duplicate, severity-order.
2. Apply every fix the lead agrees with; re-run the SPECIFIC failed check per fix,
   not the whole battery.
3. A verifier-caught gap means an AC or test was too weak: strengthen the check in
   the same pass, not only the code.
4. Write the spec's `## Review` section (replace-not-stack) and record the legs in
   the gate ledger under the BRANCH SLUG: `bash lib/gate/gate-ledger.sh record <rid> battery ran "<verdict> arms=<n> caught=<n>"`
   (the slug, never a board ID, is what the ship-gate reads). Then close the
   timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> battery end caught=<true if any arm found a defect, else false>`.
5. Name what each arm caught in the report. Disagreement between arms is the
   signal this battery exists to produce.
