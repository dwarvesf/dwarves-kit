---
title: Supervisor-Skills (HKUSTDial) teardown, skill-design patterns to steal
date: 2026-06-12
purpose: >-
  Teardown of HKUSTDial/Supervisor-Skills, a CC-BY-NC-SA repo that encodes a
  CS professor's 10-year PhD-advising experience as Claude Skills (the same
  SKILL.md format used across ops-toolkit and dwarves-kit). Two reasons to
  keep this: (1) it is a high-quality worked example of encoding expert tacit
  knowledge into a skill, with reusable design patterns I can lift into my own
  learning/ops skills; (2) the handbook chapters on paper writing and figure
  design transfer to any research craft. Use it as a skill-design calibration
  reference, not as a math-learning curriculum.
source_repos: [ops-toolkit]
refresh_cadence: none
next_review: null
status: active
---

# Supervisor-Skills teardown

External source: `github.com/HKUSTDial/Supervisor-Skills` (author Luoyu Luo,
Asst. Prof HKUST(GZ); venues SIGMOD/VLDB/ICML/NeurIPS). License CC-BY-NC-SA 4.0.
Chinese-primary, English mirror under `docs/en/`. Local clone:
`~/workspace/Supervisor-Skills`.

## What it actually is

A folder of **7 Claude Skills** (`plugins/phd-research/skills/<name>/SKILL.md`
+ per-skill `references/`) plus a **6-chapter handbook** (`docs/en/handbook/`).
It distills an advisor's tacit knowledge into agent-executable procedures. It
does not train humans directly; it role-plays the advisor through an LLM.

No `marketplace.json` / `plugin.json`, so it does NOT install via `/plugin`.
Install = copy/symlink the skill dirs into `~/.claude/skills/`.

| Skill | What it does | Cross-domain value to me |
|---|---|---|
| idea-evaluator | Scores a research idea on 5 dims (Higher/Faster/Stronger/Cheaper/Broader) + fatal-flaws gate | Low (CS-applied framing) |
| pre-submission-reviewer | 5-dim paper audit, CRITICAL/MAJOR/MINOR taxonomy, **bans em-dash + AI-tone words** | High (writing audit, matches my no-em-dash rule) |
| figure-designer | Picks paradigm + layout + tool for the 3 core paper figures, vision audit | High (diagram discipline) |
| intro-drafter | Generates intro from a 6-step flowchart model | Medium |
| tech-paper-template | Logic-chain template for a technical full paper | Low-Medium |
| benchmark-paper-template | Template for evaluation/benchmark papers | Medium (I run tool-eval experiments) |
| vibe-research-workflow | Meta-skill: tool selection + integrity rules for AI-assisted research | Medium (mirrors my own vibe-coding rules) |

## Fit verdict (two axes)

- **As a human returning to academia / learning math**: medium fit. The craft is
  *research-for-CS-publication*, not *math*. The Higher/Faster/Stronger idea
  rubric maps poorly to pure math. What transfers regardless of field: ch.3
  (paper writing), ch.4 (figure design), ch.1 (systematic paper evaluation).
- **As someone who writes agent skills (ops-toolkit, dwarves-kit, learning/ skills)**:
  high fit. Same SKILL.md format. It is a clean example of turning a mentor into
  a procedure with rubrics, gates, and a deterministic output contract.

## Skill-design patterns worth stealing

Lifted from idea-evaluator, pre-submission-reviewer, figure-designer,
vibe-research-workflow. Checklist to apply to my own skills (concept-explain,
learning-day-process, the dwarves-kit verifiers, etc.):

1. **Fatal-flaws / early-termination gate up front.** idea-evaluator runs a
   fatal-flaws audit first and *terminates early* if a critical issue exists,
   before spending tokens on the full rubric. Cheap-reject before expensive work.
   Directly applicable to any dwarves-kit verifier or eval skill.

2. **Severity taxonomy (CRITICAL / MAJOR / MINOR).** pre-submission-reviewer
   tags every finding. Forces triage and a "top-3 fixes first" summary. My
   review/verify skills should label findings, not list them flat.

3. **Inspection vs attestation split in the integrity gate.** Each gate bullet is
   tagged `[inspection]` (the LLM can verify from its own output) or
   `[user-verify]`/`[user-attest]` (depends on facts the agent cannot see).
   Honest about what the agent can and cannot confirm. This is a better pattern
   than my skills' implicit "trust me" gates. Steal verbatim.

4. **Quote-locking.** Every finding must cite actual text; no fabricated
   examples. Kills hallucinated critique. Apply to any review/audit skill.

5. **Deterministic output contract.** Fixed numbered output sections + a score
   constrained by the gate result. Reproducible, comparable across runs.

6. **Timing-window + NOT-use guard.** Skills declare when NOT to fire and route
   to a sibling skill instead (figure-designer → "paper not structured yet, use
   tech-paper-template first"). Explicit cross-skill routing reduces misfire.

7. **Dense, trigger-phrase-heavy description.** Descriptions enumerate the exact
   phrases that should fire the skill. Matches the convention I already use in
   concept-explain / learning-day-process; this repo is a good calibration bar.

8. **Vision-aware branch.** figure-designer loads an image with Read before
   auditing, and downgrades vision-only checks to `[user-verify]` in text-only
   mode. Clean pattern for any skill that may or may not have an artifact to see.

## Handbook bits that transfer to any field

- **Intro = compressed paper, 6-step flow** (ch.3.2): scenario → existing-work
  limits → problem characterization/goal → key challenges → method overview →
  contributions. A reusable skeleton for any technical write-up, including math.
- **3 figures carry the story** (ch.4): motivated example (Fig 1), solution
  overview, experimental results. Reviewers scan these in <1 min.
- **Plotting checklist** (ch.4.4): vector export, ≥8pt fonts, self-contained
  caption stating the finding, dual color+style encoding (colorblind), honest
  axis range, figures generated by code (reproducibility), method highlighted.

## Decision

- Clone kept at `~/workspace/Supervisor-Skills` (reference + skill source).
- Adopted into `~/.claude/skills/` via symlink (reversible; mirrors the existing
  `content-spec` symlink pattern). Prune unused ones with `rm` of the symlink.
- NOT building a `math-research-reviewer` skill yet: premature, no paper in flight.
