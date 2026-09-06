---
description: "The session-scoped landing step after ship: flips board rows, merges the operator's own green PRs one at a time, checks deploys, tidies branches and worktrees, writes the activity line, calls /kit:retro when a shipped PR merged, and prints the skim-first report."
---

Self-intro (AGENTS.md "Self-intro" convention): open your first reply with exactly one banner line, `[kit:wrap] Land the session after ship: board rows, merges, deploy check, tidy, activity line, retro.`, then proceed.

You are the session's landing step. The operator just shipped, or is ending the session, and nothing in the kit lands that session on its own: board rows stay unflipped, the operator's own green PRs stay unmerged, a merged-but-undeployed PR goes unnoticed, branches and worktrees pile up, and `/kit:retro` never runs. Your job is one pass over every repo the session touched, closing out each of the eight steps below in order.

## When this runs

- After `/kit:ship` completes, for the repo that just shipped.
- At the end of a session, before the operator closes the terminal.
- Whenever the operator asks to land, wrap up, or close out the session.
- Never mid-build: a spec still mid-execute has nothing to land yet.

## Prerequisites

- Each named repo (or the current repo, when none is named) is a git repository. A non-repo argument prints a skip line and the rest proceed.
- `gh` is optional. When it is absent or unauthenticated, every branch that is not a plain ancestor of the default branch verdicts `unknown: LEAVE` and `bin/wrap merge` refuses with exit 1; the command still runs the other seven steps and reports the degraded state, it never stops for this reason alone.

## Process

Bracket the phase for timing (SPEC-129) before starting: `bash lib/gate/gate-ledger.sh outcome <rid> wrap start`.

Run the steps below once per repo the session touched (the current repo when the operator names none). Positional repo arguments; wrap never discovers touched repos on its own (Out of Scope).

### Step 0: concurrent-writer check

Foreign activity in a repo's checkout means either signal is present: a worktree reflog entry newer than the session start, or an `index.lock` file older than 5 seconds (a younger lock is ordinary git traffic, proven by a passing `git status`). Run `bin/wrap scan <repo>` for the checkout, ahead/behind count, dirty files, worktrees, branch verdicts, and the operator's own open PRs.

- `bin/wrap scan <repo>` is report only; it never writes.
- On foreign activity: STOP, report what was found, and leave that repo alone for the rest of the pass. Do not touch a dirty file this session did not write.
- The check runs again, repo by repo, immediately before steps 3, 5, and 6 (the three steps that write). A repo that goes foreign between checks drops out of the remaining steps for that repo only.

### Step 1: board rows

For every backlog row whose source of truth this session closed, flip it: `bin/board set <ID> shipped|parked|dropped`. A row this session merely touched, without closing its source of truth, stays where it is.

### Step 2: commit by name

Commit any of the operator's own outstanding work under its own name and message. This step is a command-layer judgment call, not a verb: `wrap` owns no commit write. Skip it when nothing of the operator's own is outstanding.

### Step 3: merge the operator's own PRs

Re-run the step 0 check first. Then, once per PR: `bin/wrap merge --apply <repo>`. It merges exactly one own, green PR whose base is the default branch and reports every skip reason for the rest.

- `wrap merge` never runs twice for the same PR in one call; call it again for the next PR.
- When the session's open PRs form a chain, follow SPEC-065 order: retarget every dependent onto its grandparent's target first, then merge parent-first, oldest ancestor first.
- Never merge a PR the operator did not open.

### Step 4: deploy check

A merged PR is not a deployed one. For a repo whose deploy is a `workflow_dispatch`, dispatch it and confirm `headSha == merge SHA` before the report claims `DEPLOYED`. A repo with no dispatch-shaped deploy has nothing to check here; say so plainly rather than guessing at a deploy that does not exist.

- The command checks a deploy; it never dispatches one on its own initiative (Out of Scope). Dispatching happens only when the operator asked for this repo's deploy as part of landing the session.

### Step 5: branches, worktrees, pull

Re-run the step 0 check first. Then: `bin/wrap scan <repo>` again to see the current branch verdicts, `bin/wrap apply <repo>` as a dry run, read every `SKIP` line, then `bin/wrap apply --apply [--worktrees] <repo>` to execute.

- `bin/wrap apply` without `--apply` changes nothing; always read its dry-run SKIP lines before adding `--apply`.
- Pull on the default branch is `--ff-only`; off the default branch, `apply` fetches the default branch into itself instead and reports a refusal as `FAILED`, never forced.
- A worktree behind a squash-merged PR that the operator opened via `EnterWorktree` gets `ExitWorktree keep`, never a raw `git worktree remove` and never a discard, unless the operator confirms removal in this session. A plain secondary worktree still routes through `wrap apply --worktrees` and skips when dirty, detached, or held by the checked-out branch.
- Never remove a dirty or foreign worktree, under `--worktrees` or otherwise.
- Never force-push and never rewrite history to make a delete or a pull succeed.

### Step 6: activity line

Re-run the step 0 check first. Then: `bin/wrap log "<slug>: <one sentence>"`. With no `wrap.activity_log` key in the kit-root `kit.toml`, it prints the line and says where it did not land; that is a clean result, not a failure.

### Step 7: reflect

Resolve the kit log dir (`bash lib/telemetry/kit-log-dir.sh` resolves it) and grep the run ledgers under it for a `| GATE | ship | ran | shipping pr=#<n>` line naming any PR number merged in step 3. Any hit means run `/kit:retro` now, before the report. No hit means no spec cycle shipped this session; skip retro and say so in the report's FYI line.

### Step 8: report

Print the skim-first block below. It is the single reply for this command; there is no separate per-step report.

```
## Wrap: <session slug, 3 to 6 words>

✅ **Needs you:** NOTHING
   -- or --
🔴 **Needs you:**
a. DECIDE | RUN | REVIEW | UNBLOCK <what>. <why it sits with the operator>. <the one command or the decision>.
b. ...

**What happened**
- **<workstream>**: <the problem as the operator saw it>. <root cause in one clause>. <what changed>. <how it was proven>.

**Shipped**
- **<repo>**: #<pr> (<sha>) DEPLOYED <run or fleet line> | #<pr> 🟡 MERGED, NOT DEPLOYED | #<pr> OPEN

**Left alone:** <repo>: <files / worktrees / branches>, <whose>, PULL BLOCKED; <repo>: ...
**FYI:** <what changes for the operator from now on> | <a state the operator will meet next time> | NOTHING
```

- `Needs you` leads and is always present, even as `NOTHING`. It is a lettered action list; it sits at the top, ahead of every other section, because this report is read from the top and the items are the whole point.
- Exactly two emoji, no others: `✅` or `🔴` leads `Needs you` (green only when it says `NOTHING`), and `🟡` marks a `MERGED, NOT DEPLOYED` PR, the one `Shipped` state that still needs a hand. Nothing on section headers, lettered items, or in prose.
- Status words stay UPPERCASE tokens, always the same ones: `NOTHING`, `DEPLOYED`, `MERGED, NOT DEPLOYED`, `OPEN`, `PULL BLOCKED`, and a leading verb on each `Needs you` item from `DECIDE`, `RUN`, `REVIEW`, `UNBLOCK`. Prose stays lowercase.
- `What happened` is one bullet per workstream, two to four sentences: the problem as the operator saw it, the root cause, what changed, how it was proven. A ten-minute session earns one bullet; a long one earns five or six.
- `Shipped` is one line per repo: PR number, merge SHA, deploy state.
- `Left alone` names another session's dirty files, worktrees, and branches with the owner, so the operator knows a repo is not fully clean and why.
- `FYI` closes the message: what is not the operator's to act on but changes something they will meet next time, or `NOTHING`.
- An overlay (a consumer's own routing, distill, or knowledge-capture step) appends its own lines after `FYI`; the kit's grammar stops there.
- No table unless the session touched four or more repos. No restating what each step did.

Record the run (SPEC-139), one line: `bash lib/gate/gate-ledger.sh record <rid> wrap ran "<summary>"`. Close the timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> wrap end caught=<true if a repo hit step 0's foreign-activity STOP, else false>`.

## What this command does NOT do

- Never force-pushes.
- Never rewrites history.
- Never merges a PR it did not open.
- Never touches a dirty file.
- Never removes a dirty or foreign worktree.
- Never dispatches a deploy on its own initiative; it checks one the operator already dispatched or asked it to dispatch as part of this pass.
