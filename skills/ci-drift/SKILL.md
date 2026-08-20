---
name: ci-drift
description: Use for the whole-estate CI audit, "audit the CI", "are the runners clean", "check the release pipeline", "ci drift", "stale workflows / secrets / runners", or a scheduled CI-audit cadence run. Enumerates every workflow + GitHub-side CI state (enabled/disabled, secrets, vars, runners, releases, environment policy), verdicts each against the live repo with evidence, fixes drift on a branch, gates through a PR. An audit-loop instance (docs/patterns/audit-loop.md). NOT for one failing run (that is /kit:debug), NOT for doc prose (doc-drift).
disable-model-invocation: false
---

# CI drift

## Overview

Audit every workflow and its GitHub-side state against the live repo and ship the fixes as a
PR. This is the ci-drift instance of `docs/patterns/audit-loop.md`: enumerate, verdict with
evidence, apply on a branch, gate through a PR the operator approves. It catches what a single
failing run cannot: a workflow silently disabled for days, an orphan secret/var nobody removed,
a dispatch choice with no caller, a release check that trusts a sha alone.

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | every `.github/workflows/*.yml` + GitHub-side state: `gh api repos/<r>/actions/workflows` (enabled state), `gh run list -w <f> -L 1` (last run), `gh secret list` / `gh variable list` + per-environment secrets/vars via `gh api repos/<r>/environments`, `gh api repos/<r>/actions/runners`, `gh release list`, each environment's `deployment_branch_policy`, plus any cross-repo dispatcher the operator names |
| Contract | every workflow is enabled or deliberately retired; every `secrets.X`/`vars.X` reference resolves, and the inverse (no orphan secret/var); every `runs-on` label has an online runner and no runner is untargeted; every `workflow_dispatch` input has a caller or a documented reason; no `paths:` filter names a deleted dir; release minting is prefix-scoped per workflow and has a retention step; production environments gate on the default branch only |
| Evidence class | Tier 1: `gh api` + grep, mechanical. Tier 2: a read-only scanner reads a workflow's comments/steps against the scripts it calls |
| Apply mechanics | fixes on a branch + PR; GitHub-side toggles (enable a workflow, delete an orphan var) applied directly but listed in the PR body; deletions of releases/runners never auto-applied |

## Process

1. **Branch first.** All edits ride an isolated branch. Auditing on master is the failure this
   skill exists to prevent.

2. **Enumerate.** List every `.github/workflows/*.yml` plus the GitHub-side state calls above.
   Write the list down before judging anything. The list is the queue; a resumed or scheduled
   run picks up where the last one stopped.

3. **Tier 1, mechanical pass, zero model cost, every workflow.** For each workflow, check:
   - enabled state (`disabled_manually` / `disabled_inactivity` is a finding, not silence),
   - every `secrets.X` / `vars.X` token resolves against `gh secret list` / `gh variable list`
     (repo + per-environment), and the inverse: any listed secret/var with no referencing token,
   - every `runs-on` label has a matching online row in `actions/runners`,
   - every `workflow_dispatch` `inputs:` entry has a caller (grep other workflows/scripts) or a
     comment naming why it exists un-called,
   - every `paths:` filter glob resolves to a live directory,
   - release workflows: the tag/name prefix is scoped to that workflow alone, and a retention
     step (or documented unbounded-keep reason) exists,
   - production environments: `deployment_branch_policy` restricts to the default branch only.
   A Tier 1 failure is a finding with evidence attached, severity FIX (or REMOVE when the whole
   workflow's referent is gone).

4. **Tier 2, judgment pass, model-read, only where it earns its cost.** Dispatch the shared
   read-only scanner `kit:audit-scanner` (preferred: its tools roster physically cannot write,
   so an unattended cadence run keeps the propose/apply split mechanical). Dispatch only for
   workflows Tier 1 flagged, plus any cross-repo dispatcher the operator named: does the
   workflow's comments/steps still match the scripts it calls? It quotes both sides for any
   mismatch and returns findings; every fix is applied HERE, on the branch, never by the
   scanner.

5. **Verdict each item** with the audit-loop grammar: OK / FIX / REMOVE / UNSURE / DANGER. A
   verdict with no checkable evidence downgrades to UNSURE. UNSURE items are never auto-fixed;
   list them in the PR body. DANGER (a workflow that would deploy or run against current policy
   in a way that actively breaks something) gets quoted, then fixed or disabled.

6. **Apply.** Fix workflow YAML in place on the branch. Apply GitHub-side toggles (re-enable a
   workflow, delete a confirmed-orphan secret/var) directly, but list every one in the PR body
   for the operator to see. Never auto-delete a release or a runner; those go in the PR body as
   proposed actions only.

7. **Verify.** Re-run the Tier 1 pass on every touched item: it must come back clean. Run
   `bash tests/test-meta.sh`: green (pre-existing failures only), or the run is not done.

8. **Ship.** Commit, push, open a PR whose body lists every FIX/REMOVE/GitHub-side-toggle with
   its evidence and every UNSURE for the operator. If nothing needed changing, create no branch
   and report CLEAN with the enumeration list.

## Field record

The 2026-08-20 foundation-workers/foundation-apps run found: a reminder workflow
`disabled_manually` for 9 days, an orphan environment variable, a dead `workflow_dispatch`
choice with no caller, a release check trusting a sha alone, and no retention step.

## Red flags

- Editing workflows without the branch: stop, branch, start over.
- "Obviously stale" with no quoted `gh api` evidence.
- Dispatching Tier 2 for every workflow when Tier 1 cleared most of them.
- Auto-deleting a release or a runner: always proposed in the PR body, never auto-applied.
