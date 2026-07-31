# Spec: skills/memory-tidy/SKILL.md contract (backfill)
Generated: 2026-07-31
Status: DRAFT (reverse-engineered)

Backfill item 1/6 of the ID-452 campaign. The feature is a prompt-file skill; its observable behavior IS its body. The acceptance criteria below pin the load-bearing claims of `skills/memory-tidy/SKILL.md` as it exists today. Process deviation, stated honestly: the `/kit:test-plan` Step 0 `kit:research-features` dispatch was skipped; the surface is one 46-line file, read directly, and a researcher dispatch adds no observation the file does not already contain.

## Acceptance Criteria
- [ ] AC-1: Frontmatter names the skill `memory-tidy` and the description scopes OUT both the machine-local auto-memory under `~/.claude/projects` and single-note edits.
- [ ] AC-2: Process step 1 requires branching in a worktree BEFORE any edit, and the red flags repeat that editing without the worktree branch means stop and start over.
- [ ] AC-3: The mechanical pre-pass step itself (not merely the overview) names `stats memory-sweep` and requires diffing both directions (note files on disk vs `MEMORY.md` entries).
- [ ] AC-4: The audit contract is a four-slot verdict grammar (KEEP / MERGE / STALE / UNSURE), EACH slot with required evidence: KEEP shows a distinct fact with spot-checked referents; MERGE quotes the overlapping claim from both notes; STALE names a concrete tested reason; UNSURE names what only the operator can answer. A verdict with no checkable evidence is downgraded to UNSURE.
- [ ] AC-5: UNSURE notes are never deleted; they are listed in the report for the operator.
- [ ] AC-6: Deletions reach main only through a PR merge (the PR is the approval gate); the PR body lists each removal with its reason; when nothing needs changing, no branch is created and the report is CLEAN.
- [ ] AC-7: The `MEMORY.md` index is derived, not hand-edited: each line comes from the note's frontmatter `description`, entry count equals note count, and a grep for every deleted note's name returns nothing; hand-editing index lines is a named red flag.
- [ ] AC-8: The danger check: a note whose recommended fix contradicts current policy has its still-true diagnostics folded into the policy-carrying note, is then deleted, and the PR body says so.
- [ ] AC-9: Fan-out judgment splits the notes into 2-4 subsystem clusters and dispatches parallel READ-ONLY agents; a tiny store is audited directly.
- [ ] AC-10: Apply-step safety: before deleting any note, the store is grepped for references to its name and they are rewritten; merges preserve incident detail and dates.

## Test plan
Date: 2026-07-31 (revised once after the round-1 critique)
Source: this spec's ## Acceptance Criteria. Dialect: doc/prompt-file contract (not spec-feature; the standard's doc dialect applies: pin the claims with grep assertions, prove falsifiability with a negative control). All proofs run from the repo root; `S=skills/memory-tidy/SKILL.md`. Rows 1-25 are deterministic reads (grep on the tracked file, or on a scratch mktemp copy that is never the tracked file): no network, no clock, no ordering. Row 26 is the one deliberate exception, a one-time recorded mutation with a byte-identity restore. Proof cells escape a literal `|` as `\|` (markdown table convention, per SPEC-204).

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | frontmatter name pinned | happy-path | AC-1 | first frontmatter block contains `name: memory-tidy` | `awk '/^---$/{c++;next} c==1' $S \| grep -qx 'name: memory-tidy'` |
| 2 | auto-memory scope-out | boundary | AC-1 | `NOT for the built-in machine-local auto-memory` with the `~/.claude/projects` referent | `grep -qF 'NOT for the built-in machine-local auto-memory under ~/.claude/projects' $S` |
| 3 | single-note scope-out | boundary | AC-1 | `NOT for editing a single note` present | `grep -qF 'NOT for editing a single note' $S` |
| 4 | worktree-first step | happy-path | AC-2 | step 1 heading `Branch in a worktree first` present | `grep -qF 'Branch in a worktree first' $S` |
| 5 | worktree red flag | regression | AC-2 | red flag `without the worktree branch: stop, branch, start over` present | `grep -qF 'without the worktree branch: stop, branch, start over' $S` |
| 6 | pre-pass tool named IN the process step | happy-path | AC-3 | `stats memory-sweep` inside the Mechanical pre-pass step region (anchored, so the Overview's decoy mention cannot satisfy it) | `sed -n '/Mechanical pre-pass/,/Fan-out/p' $S \| grep -qF 'stats memory-sweep'` |
| 7 | two-direction index diff | boundary | AC-3 | `diff both directions` required | `grep -qF 'diff both directions' $S` |
| 8 | all four verdict slots as table cells | happy-path | AC-4 | table rows for KEEP, MERGE, STALE, UNSURE present as verdict CELLS (POSIX class, not `\s`) | `grep -qE '^[[:space:]]*\| KEEP \|' $S && grep -qE '^[[:space:]]*\| MERGE' $S && grep -qE '^[[:space:]]*\| STALE \|' $S && grep -qE '^[[:space:]]*\| UNSURE \|' $S` |
| 9 | KEEP evidence rule | boundary | AC-4 | `distinct fact, referents spot-checked alive` | `grep -qF 'distinct fact, referents spot-checked alive' $S` |
| 10 | MERGE evidence rule | boundary | AC-4 | `quote the overlapping claim from both notes` | `grep -qF 'quote the overlapping claim from both notes' $S` |
| 11 | STALE evidence rule | boundary | AC-4 | pins one worked example of the STALE evidence list (`concrete reason: referenced path tested and gone`), NOT the rule's full text; accepted trade-off, see coverage notes | `grep -qF 'concrete reason: referenced path tested and gone' $S` |
| 12 | UNSURE evidence rule | boundary | AC-4 | `what only the operator can answer` | `grep -qF 'what only the operator can answer' $S` |
| 13 | no-evidence downgrade | failure-injection (of the audit itself) | AC-4 | `A verdict with no checkable evidence is not actionable` | `grep -qF 'A verdict with no checkable evidence is not actionable' $S` |
| 14 | UNSURE never deleted | security/safety | AC-5 | `UNSURE notes are never deleted; list them in the report` | `grep -qF 'UNSURE notes are never deleted; list them in the report' $S` |
| 15 | fan-out is read-only + clustered | security/safety | AC-9 | `dispatch parallel read-only agents` and `2-4 subsystem clusters` both present | `grep -qF 'dispatch parallel read-only agents' $S && grep -qF '2-4 subsystem clusters' $S` |
| 16 | pre-delete reference rewrite | security/safety | AC-10 | `grep the store for references to its name and rewrite them` | `grep -qF 'grep the store for references to its name and rewrite them' $S` |
| 17 | merges preserve detail | boundary | AC-10 | `Merges preserve incident detail and dates` | `grep -qF 'Merges preserve incident detail and dates' $S` |
| 18 | PR-gate principle | security/safety | AC-6 | `deletions reach main only through a PR merge` | `grep -qF 'deletions reach main only through a PR merge' $S` |
| 19 | PR body lists removals | happy-path | AC-6 | `PR whose body lists each removal with its reason` | `grep -qF 'PR whose body lists each removal with its reason' $S` |
| 20 | CLEAN no-op path | boundary | AC-6 | `create no branch and report CLEAN` | `grep -qF 'create no branch and report CLEAN' $S` |
| 21 | index derived from frontmatter | happy-path | AC-7 | `derived from its frontmatter` | `grep -qF 'derived from its frontmatter' $S` |
| 22 | index count + deleted-name checks | boundary | AC-7 | `entry count equals note count` and `returns nothing` (each unique in-file) | `grep -qF 'entry count equals note count' $S && grep -qF 'returns nothing' $S` |
| 23 | hand-edit index red flag | regression | AC-7 | `Hand-editing index lines instead of deriving them from frontmatter` | `grep -qF 'Hand-editing index lines instead of deriving them from frontmatter' $S` |
| 24 | danger check | security/safety | AC-8 | `contradicts current policy` and `say so in the PR body` (each unique in-file) | `grep -qF 'contradicts current policy' $S && grep -qF 'say so in the PR body' $S` |
| 25 | in-suite negative control (permanent, scratch copy) | falsifiability | AC-5 | on a mktemp COPY of `$S` with the sentence `UNSURE notes are never deleted; list them in the report.` stripped (substring removal, tracked file untouched), row 14's grep FAILS while row 13's grep still PASSES: proves the suite discriminates, re-runs every invocation, mirrors `tests/test-test-writer-contract.sh` AC3 | inside the test script: mktemp scratch copy + substring strip + `! grep -qF <row-14 string>` + `grep -qF <row-13 string>` with an EXIT trap cleanup |
| 26 | live negative control (one-time, recorded) | falsifiability | AC-5 | strip ONLY the row-14 sentence (substring removal, NOT the whole physical line: rows 13 and 14 share SKILL.md line 30, so a line deletion would flip both; verified by simulation during critique round 1) from the tracked `$S`, run `bash tests/test-memory-tidy-contract.sh`, expect exactly the row-14 assertion RED plus the row-25 in-suite NC also RED (its target string is already gone from the source it copies: an expected, named side effect, not a blast-radius surprise); restore, prove byte-identity via `shasum` before/after, re-run green | recorded with both transcripts in `docs/verification/backfill-memory-tidy.md` |

### Coverage notes
- Every AC maps to at least one row and every row back to an AC; no orphans. Failure-injection is honestly thin: the subject is a static prompt file, so the only injectable failure is content drift, which IS rows 25-26 plus the regression rows (5, 23).
- Skill registration in the plugin manifest is NOT re-pinned here; `tests/test-meta.sh` owns skill/frontmatter structural sweeps.
- These are exact-string pins by design: the tested contract is the prose itself. A legitimate rewording of the SKILL body is EXPECTED to break the matching row; the failure is the prompt to re-verify the contract survived the rewording (same stance as `tests/test-test-writer-contract.sh`). Row 11 additionally pins one worked example rather than the STALE rule's full alternative list: accepted, documented, per the round-1 determinism finding.

## Test plan critique
Date: 2026-07-31
Spec: SPEC-208
Lenses run: Coverage completeness, Oracle & falsifiability, Determinism & maintainability (3 of the standard 6, dispatched as parallel read-only subagents). Skipped, honestly: Feasibility & reproducibility (every proof is a pasteable one-liner, trivially satisfied), Test-ladder & boundary depth (the ladder collapses for a static-file subject: nothing exists above grep plus negative control), Tiering & floor (N/A: no Tier column, no model call in scope). This is the ID-452 calibrated-cost triage, stated rather than hidden.

Rounds:
- [[QL-VERDICT round=1 clean=false findings=11]]
- [[QL-VERDICT round=2 clean=false findings=2]]

Round 1 (full 3-lens dispatch) returned 11 deduplicated findings: 2 CRITICAL, 2 HIGH, 5 MEDIUM, 2 LOW. One revision was applied (the matrix above). Round 2 was NOT a fresh lens dispatch: it was a narrow mechanical re-check by the coordinator, every changed grep run live against the real file, the negative-control blast radius re-simulated on a scratch copy (row-13's string survives the substring strip; the anchored row-6 grep catches the decoy gut that the old grep missed). Recorded as the confirmation path used, per this lane's narrow-re-check allowance. K fell 11 to 2 and max severity fell CRITICAL to LOW: falling under the severity-aware rule; the 2 remaining are accepted LOW trade-offs, so the loop stops.

### Critical findings
1. The negative control as first written ("delete the UNSURE rule line") would flip BOTH rows 13 and 14: their pinned strings share one physical line (SKILL.md line 30), so "exactly that assertion RED" was provably false; the oracle lens proved it by simulation -- fix: substring-only removal of the row-14 sentence, blast radius re-verified as exactly {14} among the string pins (plus row 25 by construction) -- resolved in round 1.
2. The negative control had never been executed and its artifacts (`tests/test-memory-tidy-contract.sh`, `docs/verification/backfill-memory-tidy.md`) did not exist -- true by pipeline position (critique precedes materialization in SPEC-203); resolved at the materialization + verification steps; the recorded runs live in `docs/verification/backfill-memory-tidy.md`.

### High findings
1. AC-level hole: the step-3 fan-out mechanism (2-4 clusters, parallel READ-ONLY agents) was load-bearing and entirely unpinned -- fix: AC-9 + row 15 -- resolved in round 1.
2. The one-time NC mutated the tracked file with no rollback discipline and no permanently re-running form -- fix: row 25 (in-suite NC on a mktemp scratch copy, tracked file untouched, runs every invocation) + row 26 gains an explicit shasum byte-identity restore check -- resolved in round 1 (merged with the determinism lens's permanent-wiring MEDIUM).

### Medium findings
1. Row 6's old grep was satisfied by the Overview's decoy mention of `stats memory-sweep`; gutting the actual process step stayed green -- fix: region-anchored sed+grep, discrimination verified live both directions -- resolved in round 1.
2. KEEP's and UNSURE's evidence phrases were unpinned (only 2 of 4 verdict slots enforced) -- fix: AC-4 reworded to all four slots, rows 9 and 12 added -- resolved in round 1.
3. Pre-delete store-wide reference rewrite (step 5) was unpinned -- fix: AC-10 + row 16 -- resolved in round 1.
4. Row 8 used non-POSIX `\s` in ERE -- fix: `[[:space:]]` -- resolved in round 1.

### Low findings
1. Long exact-string pins break on benign punctuation edits -- accepted as the documented, intended behavior of a prompt-file contract test (coverage notes) -- OPEN as accepted.
2. Row 11 pins one worked example of the STALE evidence list, not the rule's full text -- accepted and documented in the row and coverage notes -- OPEN as accepted.

### Scores (final round)
- Coverage completeness: 9/10
- Oracle & falsifiability: 9/10
- Determinism & maintainability: 9/10

### Verdict: SOLID
