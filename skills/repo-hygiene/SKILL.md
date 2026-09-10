---
name: repo-hygiene
description: Use for the whole-repo decay audit, "run the repo-hygiene loop", "what has rotted in this repo", "audit repo hygiene", "find the stale files", "is anything mis-shelved", "dọn repo", or a scheduled repo-hygiene cadence run. Enumerates files inside a git repo that have decayed (unreferenced docs, stale staging drops, records parked in a control surface, logs past their documented budget, large cold gitignored dirs), verdicts each with evidence inline, co-locates mis-shelved records on a branch, and gates through a PR. An audit-loop instance (docs/patterns/audit-loop.md). NOT for the machine surface outside a git repo (abandoned home-folder tool dirs, package caches: that is ops-toolkit tools/disk-reclaim, which owns read-first machine cleanup), NOT for doc claims drifting from code (that is kit:doc-drift), NOT for board rows (kit:backlog-reconcile), NOT for one file you already know is stale (just move it).
disable-model-invocation: false
---

# Repo hygiene

## Overview

Audit one git repo for files that have decayed and ship the result as a PR. This is the
repo-hygiene instance of `docs/patterns/audit-loop.md`. It is the first instance whose item
set is the repo's own FILES rather than their claims: `doc-drift` asks whether a doc still
tells the truth, this asks whether the file should still be sitting where it is.

Two constraints shape everything below, both learned running this pass by hand:

- **Every finding carries its evidence inline.** Verification, not detection, was about 90
  percent of the manual pass's cost. A findings list without evidence only moves that cost.
- **The loop SURFACES, it never deletes.** Route versus trash needed a human call four times
  in one pass, and twice the human chose against the recommendation. The only fix this
  instance applies is a MOVE, and even a move gates through the PR.

## Scope boundary

This instance is REPO-SCOPED. The machine surface, an abandoned tool directory in a home
folder, a package cache, a downloads pile, anything outside a git checkout, belongs to
`ops-toolkit tools/disk-reclaim`, which already owns read-first machine cleanup with its own
safe set. If the ask is "my disk is full", it is the wrong loop. If the ask is "what has
rotted inside this repo", it is this one.

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | five detector classes over ONE git repo, enumerated by `bash lib/repohygiene/repohygiene.sh scan --repo <dir>`: an unreferenced non-code file past an age threshold, a staging drop past 30 days, a record parked in a central control directory whose owner is one tool or experiment, an append-only log past the budget the repo itself documents, and a gitignored directory that is large and cold |
| Contract | a file earns its place: something references it, or it is young, or it sits with its owner, or it is inside its own stated budget. A gitignored directory has no contract at all here, only a size and a date |
| Evidence class | Tier 1: the scanner's own output, one line per finding, each carrying the proof inline (the exact path-boundary grep and its zero-hit result, an age in days against its threshold, a duplicate's path plus its sha256, an owner plus the commits that name it, a line count plus the `file:line` where the repo states the threshold, a size plus a newest-mtime). Tier 2: `agents/audit-scanner.md`, dispatched only on the FIX and REMOVE rows, never on the whole set |
| Apply mechanics | `git mv` for a detector-3 FIX, and nothing else. Detectors 1, 2, 4, and 5 are report-only in every case. No deletion is ever applied, proposed as a command, or staged |

## The five detectors

| # | Name | What it flags | Threshold | Evidence format |
|---|---|---|---|---|
| 1 | `unreferenced-doc` | a tracked non-code file that no other tracked file references | last touched more than `--stale-days` ago (default 180) | the exact `git grep -I -n -E '(^\|[^A-Za-z0-9_-])<basename>' -- ':(exclude)<path>'` and its `0 hits outside itself`, plus the last-touch date and age |
| 2 | `stale-inbox` | an entry directly under a staging dir (`_inbox`, `inbox`, `_staging`) | mtime older than `--inbox-days` (default 30) | the age in days against the threshold, plus `duplicate-of <path> (identical sha256 <first12>)` when a content-identical copy exists elsewhere in the repo |
| 3 | `misplaced-record` | a record in a central control directory (`_meta`, `docs/research`, `docs/briefs`) whose owner is one tool or experiment, and a closed mega-goal still parked in the control surface | owner accounts for at least half the commits touching the file | the owner, the count of owning commits out of the file's total, the latest commit subject, and the destination path it should co-locate to |
| 4 | `log-budget` | an append-only log past the line budget the repo's own docs state | the repo's documented numbers, never the scanner's | total lines against the threshold, the busiest `YYYY-MM` against the per-month threshold, and the `file:line` of the sentence that states them, quoted |
| 5 | `cold-ignored-dir` | a gitignored directory that is large and cold | size at or above `--cold-mb` (default 100) with no file newer than `--cold-days` (default 90) | the size in MB and the fact that no file is newer than the threshold, tagged `REPORT ONLY, gitignored, never a deletion proposal` |

Detector 3 resolves the owner from the CONVENTIONAL-COMMIT SCOPE of the commits that touched
the file, not from the file's contents. Content was tried first and is too noisy: a research
note names every tool it surveyed, so a file owned by one tool mentions four others. What a
file's own history says about who wrote it does not have that problem.

## Process

1. **Refusal guard.** REFUSE if the target is not a git repo. The machine surface belongs to
   `disk-reclaim`, and running here against a bare directory would silently audit nothing.

   ```
   git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "REFUSE: '$TARGET' is not a git repo -- the machine surface belongs to ops-toolkit tools/disk-reclaim, not to this loop"; exit 1; }
   ```

2. **Branch in a worktree first** (native worktree tool), and only when a detector-3 FIX
   exists. A report-only run needs no branch and creates none.

3. **Tier 1, mechanical, one pass, zero model cost.**

   ```
   bash lib/repohygiene/repohygiene.sh scan --repo <dir>
   ```

   Output is TSV: `detector`, `verdict`, `path`, `evidence`. Only findings are emitted; an
   item that passes its contract prints nothing, so an empty body is a CLEAN run.

   **Run detector 1 twice on a first pass over a repo**: once at the default, and once at
   `--stale-days 0`. Age is a NOISE FILTER, not part of the contract, and the manual pass
   that motivated this instance found its unreferenced file four days after it was written.
   The second run needs `--max-candidates` raised or it reports the overflow and caps.

4. **Tier 2, delta only, model-read.** Zero FIX and zero REMOVE rows = zero dispatch; report
   the UNSURE rows and stop. Otherwise dispatch `kit:audit-scanner` (preferred: its tools
   roster physically cannot write, so the propose/apply split holds mechanically in an
   unattended cadence run; fall back to a general-purpose subagent only where the kit agent
   roster is unavailable) with the FIX and REMOVE rows, this instance's contract, and its
   evidence class. Its job is narrow: does the stated owner actually own this record, and is
   the destination path right. A scanner timeout, error, or an out-of-vocabulary verdict is
   treated as UNSURE, never coerced to OK.

5. **Verdict each finding** with the audit-loop grammar. This instance's mapping:

   | Finding | Verdict | Applied? |
   |---|---|---|
   | detector 3, one owner confirmed by Tier 2 | FIX | yes, `git mv` |
   | detector 3, two or more owners, or a closed mega-goal with no resolvable owner | UNSURE | no |
   | detector 2 with a content-identical copy elsewhere | REMOVE (the copy is the named successor) | never |
   | detector 1, detector 2 without a duplicate | UNSURE | never |
   | detector 4 | FIX (rotate or compact per the repo's own procedure) | never |
   | detector 5 | UNSURE, always | never |

   A REMOVE here is a PROPOSAL with a named successor, which is what the pattern's grammar
   means, and it is still the operator who deletes. This instance never issues a delete.

6. **Apply.** `git mv <path> <destination>` per confirmed detector-3 FIX, creating the
   destination directory first. Nothing else is applied. Never `rm`, never `git rm`, never a
   deletion staged "for the operator to confirm in the PR", including for a detector-2 exact
   duplicate: an exact duplicate is still someone's copy, and the manual pass proved the
   human overrules the recommendation about a third of the time.

7. **Re-verify.** Re-run the scan against every moved path: the detector-3 row must be gone,
   and no detector-1 finding may have appeared for the moved file at its new home (a move
   that breaks the last reference to a file trades one finding for another).

8. **Ship.** Commit, push, open a PR whose body carries every finding with its evidence,
   grouped by detector, with the UNSURE rows listed for the operator and the applied moves
   listed separately. Nothing to move: no branch, report the findings inline.

## Cadence

Run on demand, or wrap in `/loop` or a schedule per the audit-loop driver ladder. One repo
per invocation: the scan is bounded by one checkout, and a multi-repo sweep is that command
in a loop, not a mode inside it.

## Red flags

- Proposing, staging, or running any deletion. This loop moves and reports, nothing else.
- Recommending the deletion of anything gitignored. Detector 5 is REPORT ONLY by contract,
  and the scanner cannot see what a gitignored path is for.
- A finding without its evidence inline. Verification is the expensive half; a bare path
  hands the whole cost back to the operator, which is the failure this instance was built
  against.
- Inventing a line threshold for detector 4. If the repo documents no budget, the verdict is
  UNSURE with the counts, not a number the scanner made up.
- Treating an experiment's own result dump or draft folder as decayed. Those are frozen
  records of a run and are excluded, on the same reasoning that keeps dated records out of
  `doc-drift`'s item set.
- Auditing a directory that is not a git repo. That is `disk-reclaim`'s surface.
