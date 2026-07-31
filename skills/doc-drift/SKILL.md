---
name: doc-drift
description: Use for the whole-estate doc audit, "run the doc-drift loop", "audit the docs against the code", "are the docs still true", "doc drift sweep", "check every doc claim", or a scheduled doc-audit cadence run. Enumerates every LIVING doc (README, MANUAL, AGENTS, WORKFLOW, architecture, patterns), verdicts each against the live repo with evidence, fixes drift on a branch, gates through a PR. An audit-loop instance (docs/patterns/audit-loop.md). NOT for diff-scoped doc sync inside a build cycle (that is /kit:docs), NOT for dated records like specs, research, retros (they describe their moment and never drift), NOT for one known-wrong doc (just fix it).
disable-model-invocation: false
---

# Doc drift

## Overview

Audit every living doc against the live repo and ship the fixes as a PR. This is the doc-drift
instance of `docs/patterns/audit-loop.md`: enumerate, verdict with evidence, apply on a branch,
gate through a PR the operator approves. `/kit:docs` syncs docs against ONE diff during a build
cycle. This skill audits the WHOLE estate on a cadence, and catches what diff-scoped sync
structurally misses: drift from merged-but-undocumented work, inventory rot, dead pointers,
stale counts. PR #306 (hand-fixing the README inventories) is the proven need.

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | living docs only: `git ls-files README.md MANUAL.md AGENTS.md CLAUDE.md CONTRIBUTING.md ':(glob)docs/*.md' ':(glob)docs/patterns/*.md'` (the `:(glob)` magic is required: a bare `docs/*.md` pathspec matches recursively and pulls in every dated record) |
| Contract | every checkable claim matches the live repo: referenced paths exist, inventory tables match the live dirs, counts match derived counts, named verbs and flags exist, cross-doc pointers resolve |
| Evidence class | Tier 1: the repo itself via grep/ls/diff. Tier 2: a model reads the doc's described behavior against the actual command or script |
| Apply mechanics | FIX in place on an isolated branch; REMOVE only with a named successor; PR body lists every verdict; UNSURE never auto-resolved |

Dated records (docs/specs, docs/research, docs/retro, docs/handoff, docs/decisions,
docs/absorption, and docs/CHANGELOG.md's per-release entries) are OUT of the item set. They describe their moment. Flagging a 2026-05 spec
for describing 2026-05 reality is noise, not a finding.

## Process

1. **Branch first.** All edits ride an isolated branch. Auditing on master is the failure this
   skill exists to prevent.

2. **Enumerate.** Run the item-set command above. Write the list down before judging anything.
   The list is the queue; a resumed or scheduled run picks up where the last one stopped.

3. **Tier 1, mechanical pass, zero model cost, every file.** For each doc, extract and check
   the mechanical claims:
   - every backtick path or file reference resolves (`ls` it),
   - every inventory table row maps to a live file (`diff` the table names against the dir
     listing, both directions: rows with no file, files with no row),
   - every hardcoded count matches the derived count (`ls | wc -l`),
   - every named command, verb, or flag appears in the target script or its `--help`.
   A Tier 1 failure is a finding with evidence attached, severity FIX (or REMOVE when the whole
   doc's referent is gone). `bash tests/test-meta.sh` overlaps part of this pass; run it first
   and treat its failures as pre-confirmed findings, do not re-derive them.

4. **Tier 2, judgment pass, model-read, only where it earns its cost.** Dispatch read-only
   reviewers only for: files Tier 1 flagged (the drift is confirmed, judge how deep it goes),
   plus the high-traffic operator surfaces (README, QUICKSTART, AGENTS) whose prose describes
   behavior no grep can check. Per file: does the described flow still match what the command
   actually does? Quote both sides for any mismatch. Skip Tier 2 entirely for files Tier 1
   cleared that only carry mechanical claims.

5. **Verdict each item** with the audit-loop grammar: OK / FIX / REMOVE / UNSURE / DANGER. A
   verdict with no checkable evidence downgrades to UNSURE. UNSURE items are never auto-fixed;
   list them in the PR body. DANGER (a doc that tells the operator to do something now wrong)
   gets quoted, folded into the policy-carrying doc, then removed or marked superseded.

6. **Apply.** Fix in place. Prefer deriving over restating: a count becomes "every X" prose or
   a derived assertion, never a fresh literal (the no-hardcoded-counts rule). Before removing
   any doc, grep the estate for pointers to it and rewrite them.

7. **Verify.** Re-run the Tier 1 pass on every touched file: it must come back clean. Run
   `bash tests/test-meta.sh`: green, or the run is not done.

8. **Ship.** Commit, push, open a PR whose body lists every FIX/REMOVE with its evidence and
   every UNSURE for the operator. If nothing needed changing, create no branch and report
   CLEAN with the enumeration list.

## Cadence

Run after any batch of merges that skipped `/kit:docs`, before a release tag, or on a schedule
(`/loop` or a cron per the audit-loop driver ladder). One pass per invocation, bounded by the
enumeration list.

## Red flags

- Editing docs without the branch: stop, branch, start over.
- "Obviously outdated" with no quoted evidence.
- Dispatching Tier 2 reviewers for every file when Tier 1 cleared most of them: the cheap-first
  split exists to prevent exactly this spend.
- Writing a fresh hardcoded count while fixing a stale one.
- Auditing dated records: out of scope, always.
