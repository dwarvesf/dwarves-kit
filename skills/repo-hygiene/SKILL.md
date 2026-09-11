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

The loop is REPO-SCOPED. The machine surface, an abandoned tool directory in a home folder, a
package cache, a downloads pile, anything outside a git checkout, belongs to `ops-toolkit
tools/disk-reclaim`, which already owns read-first machine cleanup with its own safe set. If
the ask is "my disk is full", it is the wrong loop.

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | five detector classes over ONE git repo, enumerated by `bash lib/repohygiene/repohygiene.sh scan --repo <dir>`: an unreferenced non-code file past its age threshold, a staging drop past its age threshold, a record parked in a central control directory whose owner is one tool or experiment, an append-only log past the budget the repo itself documents, and a gitignored directory that is large and cold |
| Contract | a file earns its place: something references it, or it is young, or it sits with its owner, or it is inside its own stated budget. A gitignored directory has no contract at all here, only a size and a date |
| Evidence class | Tier 1: the scanner's own output, one line per finding, each carrying the proof inline (the exact path-boundary grep and its zero-hit result, an age in days against its threshold, a duplicate's path plus its sha256, an owner plus the commits that name it, a line count plus the `file:line` where the repo states the threshold, a size plus a newest-mtime). Tier 2: `agents/audit-scanner.md`, dispatched only on the FIX and REMOVE rows, never on the whole set |
| Apply mechanics | `git mv` for a detector-3 FIX, and nothing else. Detectors 1, 2, 4, and 5 are report-only in every case. No deletion is ever applied, proposed as a command, or staged |

## The five detectors

| # | Name | What it flags | Threshold | Evidence format |
|---|---|---|---|---|
| 1 | `unreferenced-doc` | a tracked non-code file that no other tracked file references | last touched more than `--stale-days` ago (default 180) | the exact `git grep -I -n -E '(^\|[^A-Za-z0-9_-])<basename>' -- ':(exclude)<path>'` and its `0 hits outside itself`, plus the last-touch date and age |
| 2 | `stale-inbox` | an entry directly under a staging dir (`_inbox`, `inbox`, `_staging`) that no tracked file names, and that is not an OS artifact | mtime older than `--inbox-days` (default 30) | the age in days against the threshold, plus `duplicate-of <path> (identical sha256 <first12>)` when a content-identical copy exists elsewhere in the repo |
| 3 | `misplaced-record` | a record in a central control directory (`_meta`, `docs/research`, `docs/briefs`) whose owner is one tool or experiment, and a closed mega-goal still parked in the control surface | owner accounts for at least half the commits touching the file; a mega-goal folder must also be closed by its own record (see below) | the owner, the count of owning commits out of the file's total, the latest commit subject, and the destination path it should co-locate to; for a mega-goal, the `file:line` of its status marker and its checked-against-open counts |
| 4 | `log-budget` | an append-only log past the line budget the repo's own docs state FOR THAT LOG | the repo's documented numbers, never the scanner's | total lines against the threshold, the busiest `YYYY-MM` against the per-month threshold, and the `file:line` of the sentence that states them, quoted |
| 5 | `cold-ignored-dir` | a gitignored directory that is large and cold | size at or above `--cold-mb` (default 100) with no file newer than `--cold-days` (default 90) | the size in MB and the fact that no file is newer than the threshold, tagged `REPORT ONLY, gitignored, never a deletion proposal` |

Detector 2 runs detector 1's reference grep before it flags anything. A staging entry a
tracked file names is somebody's deliberate home, not a drop awaiting triage, and age alone
never distinguished the two. The first family-office sweep ran three of five false positive on
exactly this: a note a tracked doc names as the home for third-party phone numbers it keeps OUT
of the tracked tree, a rename map cited as evidence in an ingest record, and a bot's landing
zone whose nightly drain job is documented. Acting on the first would have stripped a
deliberate privacy split. The grep excludes the whole staging dir, so a drop can never cite
itself, and the basename carries the path, so one pass covers `_inbox/x.md` and a bare `x.md`
alike. An OS artifact (`.DS_Store`, `Thumbs.db`, `desktop.ini`, `.localized`) is skipped
outright: nobody dropped it and routing it is not a decision anybody owes.

Detector 4 reads a budget only from a clause that names the log AND carries an `<N> ... lines`
phrase. Naming the log and carrying a line count somewhere on the same line is not enough: one
sentence routinely states one file's budget while merely mentioning another. A SPEC line
reading `Slim HANDOFF.md to <=100 lines (status-only; journal content stays in INGEST_LOG)`
handed a real INGEST_LOG a 100-line budget owned by HANDOFF.md, and two decisions-table rows
handed it a per-month threshold of `0001` scraped out of digit runs in unrelated prose. A
number loose in the prose is not a budget, whatever else shares its line.

Detector 3 resolves the owner from the CONVENTIONAL-COMMIT SCOPE of the commits that touched
the file, not from the file's contents. Content was tried first and is too noisy: a research
note names every tool it surveyed, so a file owned by one tool mentions four others. What a
file's own history says about who wrote it does not have that problem.

### Mega-goal completion is read from the folder, not the log

Detector 3 also judges mega-goal FOLDERS, and there the OWNER question comes second to the
CLOSED question. A closed mega-goal is a record and co-locates with its owner; an open one is
a live engine and stays where it is. The test runs in a fixed precedence and stops at the
first step that answers:

0. **A tracked record.** A folder holding no tracked `.md` / `.markdown` / `.mdx` / `.txt` is
   residue a `git mv` left behind, not a mega-goal, and is skipped.
1. **An explicit status marker** in the folder's TOP-LEVEL docs, a `Status:` or `State:`
   heading, bold label, or list item at the start of a line. Files under `goals/` are excluded,
   so one drafted sub-goal never describes the goal. An OPEN marker anywhere (charter, draft,
   held, blocked, pending, deferred, in progress) wins over a closed one, because the loop's
   only mutation is a move and a live engine must not be moved out of the control surface.
2. **Its own checkboxes.** An unchecked item anywhere in the folder (`- [ ]`, and the `- [~]`
   in-progress form) means the goal is not complete, whatever the commits say. A box counts at
   the start of a line, a blockquote, or a table cell, on a bullet or a number, which keeps
   prose ABOUT checkboxes out of the count: every POINTER_PROMPT.md in the estate writes the
   convention out mid-sentence as `` `- [ ] NN-... PR #N` ``.
3. **Commit evidence, only for a folder that declares nothing at all**, and then the verdict
   is UNSURE. A commit keyword alone never earns a mega-goal folder a FIX.

FIX needs all of: a closed marker, no open item, at least one CHECKED item, a basename with no
glob metacharacter in it, and a commit scope that resolves a majority owner to give the move a
destination. Each refusal names itself in the UNSURE row it produces instead. The checked-item
requirement is the fail-closed catch: every way the box scan can come back empty also yields
zero checked items, so a folder whose checklist could not be read never reaches a move.

This precedence exists because commit keywords alone were the first test, and on the first
live run they misread three of five real folders: a sweep commit reading "co-locate completed
mega-goals" carries a keyword about OTHER goals, and "mochi build complete, 08 shipped" closed
nothing while that folder's ROADMAP still carried four open sub-goals and a section blocked on
a human. The cost is deliberate and asymmetric: a stale unchecked box on a genuinely finished
goal suppresses one finding, while a wrong FIX moves a live engine. Measured before and after:
`lib/repohygiene/docs/proof-of-done.md`.

## Verdict mapping

| Finding | Verdict | Applied? |
|---|---|---|
| detector 3, one owner confirmed by Tier 2 | FIX | yes, `git mv` |
| detector 3, a mega-goal closed by its own marker, nothing open, something checked, one majority owner, no glob in its name | FIX | yes, `git mv` |
| detector 3, two or more owners, or a closed mega-goal that fails any other FIX condition | UNSURE, naming which condition failed | no |
| detector 3, a mega-goal that declares no status, nothing open, commit evidence only | UNSURE | no |
| detector 3, a mega-goal with any open checklist item and no closed marker | not emitted | no |
| detector 2 with a content-identical copy elsewhere | REMOVE, the copy being the named successor | never |
| detector 1, detector 2 without a duplicate | UNSURE | never |
| detector 4 | FIX, rotate or compact per the repo's own procedure | never |
| detector 5 | UNSURE, always | never |

A REMOVE here is a PROPOSAL with a named successor, which is what the pattern's grammar
means, and it is still the operator who deletes. This instance never issues a delete.

DANGER never comes from Tier 1. No detector reads a file's content for a policy claim, so
"this record tells the operator to do something now wrong" is a judgment only the lead can
make after reading the file, and it must quote the contradiction. UNTESTABLE does not arise
either: every detector runs against a local checkout the scanner can read, so evidence it
cannot gather is a scan that failed, not a vantage problem.

## Process

1. **Refusal guard.** REFUSE if the target is not a git repo. The machine surface belongs to
   `disk-reclaim`, and running here against a bare directory would silently audit nothing.

   ```
   git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "REFUSE: '$TARGET' is not a git repo -- the machine surface belongs to ops-toolkit tools/disk-reclaim, not to this loop"; exit 1; }
   ```

2. **Branch in a worktree first** (native worktree tool). Every sibling instance branches
   before it judges anything, and auditing on the main branch is the failure they all exist
   to prevent. A run that turns out to have nothing to move reports inline at step 8 and the
   branch goes away unused.

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
   treated as UNSURE, never coerced to OK. The dispatch set needs no chunking: it is bounded
   by the FIX and REMOVE rows, which are a small fraction of one repo's findings, unlike
   `backlog-reconcile`, whose delta can span a whole board.

5. **Verdict each finding** with the audit-loop grammar, per the Verdict mapping above.
   Treat the scanner's verdict as a proposal: a Tier-2 judgment can move a row from FIX to
   UNSURE, never the other way.

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
   listed separately. Follow the repo's own session-close conventions. A push or
   `gh pr create` failure after Apply exits non-zero and names the orphan branch, never a
   silent success. Nothing to move: no branch, report the findings inline.

## Cadence

Run after a batch of merges that added records to a central directory, after a staging-dir
intake session, before a repo changes owner or gets archived, or on a schedule via `/loop`
per the audit-loop driver ladder. One repo per invocation: the scan is bounded by one
checkout, and a multi-repo sweep is that command in a loop, not a mode inside it.

## Red flags

- Proposing, staging, or running any deletion. This loop moves and reports, nothing else.
- Recommending the deletion of anything gitignored. Detector 5 is REPORT ONLY by contract,
  and the scanner cannot see what a gitignored path is for.
- A finding without its evidence inline. Verification is the expensive half; a bare path
  hands the whole cost back to the operator, which is the failure this instance was built
  against.
- Inventing a line threshold for detector 4. If the repo documents no budget, the verdict is
  UNSURE with the counts, not a number the scanner made up. Borrowing a number that belongs to
  a DIFFERENT file counts as inventing one: the rule is about whose budget it is, not about
  whether a constant was hardcoded.
- Treating an experiment's own result dump or draft folder as decayed. Those are frozen
  records of a run and are excluded, on the same reasoning that keeps dated records out of
  `doc-drift`'s item set.
- Reading a commit subject as proof that a mega-goal closed. A commit says what one run did,
  not what the goal's own roadmap still has open, and this loop's one applied verdict rides on
  the difference.
- Auditing a directory that is not a git repo. That is `disk-reclaim`'s surface.
