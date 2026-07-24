---
title: Q&A record, kit direction + onboarding arc (2026-07-24/25 sessions)
date: 2026-07-25
purpose: >
  The question-answer pairs from the workflow-assessment + kit-direction +
  onboarding sessions, condensed so a future solution discussion can cite the
  answer instead of re-deriving it. Also the SEED CORPUS defining the output
  format for the qa-miner tool (ops-toolkit board ID-398): one H2 per question, Han's
  question paraphrased, the answer condensed to its load-bearing content, a
  pointer to the full record. Q&A pairs are answers-with-provenance, not
  transcripts.
source_repos: [ops-toolkit, dwarves-kit, dfoundation]
refresh_cadence: as-needed
next_review: null
status: active
---

# Q&A: kit direction + onboarding (2026-07-24/25)

Format contract (for the qa-miner tool): `## Q: <question, paraphrased>` then
`**A:**` condensed answer, then `-> full:` pointer. Newest sessions append.

## Q: What is my current approach to dev and non-dev tasks; is there a pattern?

**A:** One process, two loop libraries. Everything is classified twice (lane =
evidence owed, type = loop content), runs a right-sized loop, exits through
proof-not-assertion, and routes residue to a durable home. Signature patterns:
queue-and-route with receipts (every input queue drains to a named home),
hub-and-spoke applied to both work and knowledge (git is the only record),
attention at two points (define done, judge artifact).
-> full: ops-toolkit research/2026-07-24-workflow-pattern-and-assessment.md Part 1.

## Q: Rate the setup; what is missing; what should I know?

**A:** 4.5/5 as a personal OS, 2.5/5 as a team framework; the gap is packaging
and vocabulary, not design. Missing: a slop metric (gates unmeasured), gate
red-teaming, reviewer-capacity budgeting, a positive "card-ready" definition,
a human onboarding front door. Context freshness is the weakest dimension
(2/5): every hygiene tool is pull-based with no owner.
-> full: same file (ops-toolkit), Part 2 (ratings table + issues -> rows map in Part 3).

## Q: Should we depend on GSD v2 for the ordering graph?

**A:** No, and the dependency was never real: "GSD v2" was a stale boundary
marker. ADR-0030 already shipped the wavefront half in-house; the gap is only
explicit depends_on + dynamic ready-queue + ordered merge. Field survey says
our shape is at parity or ahead; best pickups: auto-unblock ready-queue (CC
Agent Teams), sequential merge under parallel execution (gsd-pi),
bisect-on-red (Gas Town). Nobody documents prune-descendants-on-failure; the
kit can be first.
-> full: docs/research/2026-07-25-dag-orchestration-prior-art-refresh.md; row ID-394.

## Q: How should the kit be packaged (extensibility/modularity vision)?

**A:** Standalone-first: each capability = plain git-trackable files (the
artifact IS the source of truth) + one script that works with the kit deleted
+ ONE generated per-host adapter; the kit owns only the composition manifest
(modules declare what they EXPOSE). Acceptance test: delete the kit, every
tool still works; delete a tool, the kit is never broken. Closest wild
analogue: OpenSpec. Cautionary tale: Ruflo ("99% theater").
-> full: docs/research/2026-07-25-packaging-prior-art-refresh.md; rows ID-395/396.

## Q: How do we remember the direction so future solutions align?

**A:** PHILOSOPHY.md §6 extended with N4-N7 (modularity, autonomy,
self-improvement, serve-the-team) + the meta-principles block; git-tracked
repo memory notes in both repos; ID-397 wires the alignment question into
/kit:think, /kit:spec-validate, /kit:absorb. Every proposal states which
criterion it serves; conflicts are surfaced, never silently absorbed.
-> full: docs/PHILOSOPHY.md §6.

## Q: Should per-stage human gates exist (my 7-element pipeline model)?

**A:** No. The kit's ship-only enforcement + decision-type pauses (ADR-0024)
wins over per-stage gates: watching the middle re-creates driver mode and
destroys the parallelism that justifies delegation. Slop economics: expected
cost = P(wrong) x cost of discard; shrink cost of discard (small cards,
worktrees, cheap models), sharpen only the two attention points. Update the
mental model, not the kit.
-> full: ops-toolkit research/2026-07-24-workflow-pattern-and-assessment.md §2.6 + Part 4.

## Q: What did the two skills repos have for us; how do we track them?

**A:** mattpocock delta: grill facts-vs-decisions split (ID-404), typed
tickets (DF-151 type field), dual-distribution as packaging prior art.
az-skills (NO license, mechanisms only): greenlight-pr autonomous PR-to-merge
(ID-401, the strong absorb), deslop lens (ID-402). Tracking with zero infra:
both registered as /kit:absorb seeds (ID-403); watch mattpocock's CHANGELOG
minor bumps monthly, az-skills' closed-PR titles quarterly; last-seen markers
in the absorption file.
-> full: docs/research/2026-07-25-skills-repos-onboarding-absorption.md §1/§2/§5.

## Q: Design the onboarding so people receiving the kit don't have to think.

**A:** Three moments, one action each, education embedded in the doing.
Moment 0 RECEIVE: one message ending with the two /plugin commands +
"/kit:onboard in your repo". Moment 1 INSTALL: plugin path (already shipped in
.claude-plugin/), zero decisions; bash installer demoted to maintainer path.
Moment 2 ONBOARD: /kit:onboard Enter-Enter-Enter tour, adopts the repo with
portable files. Moment 3 WORK: /kit:start every session, state + ONE next
action; onboarding never completes, the doctor IS the onboarding. Key insight:
the machinery already existed; the story was never told plugin-first.
-> full: docs/research/2026-07-25-skills-repos-onboarding-absorption.md §3b.

## Q: What is wrong with the current install/adopt (the "symlinks" problem)?

**A:** Not symlinks: render-time path expansion. lib/adopt.sh bakes
/Users/tieubao/.claude/dwarves-kit/... into consumer files (verified 2 hits in
ops-toolkit CLAUDE.md), so adopted repos break on any other machine. Fix
(ID-408, blocker for the onboarding story; renumbered from ID-406): templates emit the read-time
resolver `KIT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}"`, plus a
--refresh migration and a no-expanded-$HOME lint. Build order: ID-408 ->
ID-400 (plugin-first docs) -> DF-152 (the Moment-0 message).
-> full: docs/research/2026-07-25-skills-repos-onboarding-absorption.md §3b; row ID-406.
