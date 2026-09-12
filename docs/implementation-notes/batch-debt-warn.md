# Implementation notes: batch-debt-warn

Delta from the backlog row that asked for the mechanism. The row named the two conditions and
left the exact trigger to the build. This file records the trigger chosen and the cuts made.

## 2026-09-13 Trigger: session merge count plus a lane START inside the merge window

Context: the row asked for a warn when the session merged 2 or more PRs while the gate ledger
showed no START since the merge base. No kit log records merges, so the count had no source.
Decision: the hook counts its own engagements. Each `gh pr merge` appends one line to the ledger
stream `merge-watch/<session_id>.log` through `lib/ledger/ledger.sh`, the existing append
substrate. The second merge of a session is the trigger. The START window opens at the
timestamp of that session's first merge, not at the PR's merge base.
Why: resolving a merge base needs the branch and base of the PR, which needs a `gh pr view`
network call inside a 5 second PreToolUse budget. The first merge of a session is a local,
free anchor with the same discriminating power. A gated batch starts a lane between merges, so
a START lands inside the window; an ungated batch writes nothing at all.
Alternatives: read the PR's merge base through `gh` (rejected, network cost in a hook); check
the run log for the merged branch's rid (rejected, the branch name is not in the command when
the operator merges by PR number).
Impact: a gated batch that dispatches every lane before merging anything can still warn. The
warn is advisory, fires once per session, and one line of context is the whole cost.
Open questions: none.

## 2026-09-13 One warn per session, not one per merge

Context: the trigger holds for merge 2, 3, 4 and so on, so a long sweep would warn repeatedly.
Decision: the hook appends a `WARNED` marker to the same stream and exits silently once the
marker exists.
Why: a repeated warn on every merge trains the operator to ignore it.
Impact: a session that fixes the debt after the warn gets no confirmation. Reading the ledger
is the confirmation.

## 2026-09-13 No merge-base check, no new env var, no new subsystem

Context: the row could have grown a debt subsystem with its own config.
Decision: the hook is 37 lines, reuses `ledger_append` and `ledger_root`, reads `session_id`
from the hook payload the way `slop-cleaner.sh` and `context-budget.sh` already do, and adds no
environment variable. It joins the existing `session` install module.
Why: the module registry governs new `KIT_*` names, and this warn needs no knob.
