# Hermes prompt patterns to absorb (cc-self-improve)

Distilled from the live Hermes engine (`~/dev/hermes-agent`, 2026-06-19):
`agent/background_review.py` (`_MEMORY_REVIEW_PROMPT`, `_SKILL_REVIEW_PROMPT`,
`_COMBINED_REVIEW_PROMPT`) and `agent/curator.py` (`CURATOR_REVIEW_PROMPT`,
`CURATOR_DRY_RUN_BANNER`). These are battle-tested prompts driving Han's personal Hermes. When
the r4 loop writes `prompts/review-skill.md` and `prompts/curator.md`, it MUST start from these
patterns rather than inventing from scratch. Adapt, do not copy verbatim: our reviewer is a
no-write pure function (returns JSON), Hermes's calls tools directly.

## A. Skill-draft reviewer (prompts/review-skill.md) , absorb from `_SKILL_REVIEW_PROMPT`

**Target library shape (state it in the prompt):** CLASS-LEVEL skills, each a rich SKILL.md +
`references/` for session-specific detail. NOT a flat list of narrow one-session-one-skill
entries. A future agent matches on the `description`, so one broad umbrella with labeled
subsections beats five narrow siblings.

**Signals that warrant a draft (any one):**
- User corrected your style / tone / format / verbosity / approach. Frustration ("stop doing X",
  "too verbose", "just give me the answer", "you always do Y") is a FIRST-CLASS signal.
- User corrected your workflow or sequence of steps , encode as a pitfall or explicit step.
- A non-trivial technique, fix, workaround, or debugging path emerged.
- A skill that was loaded this session turned out wrong / missing a step / outdated , patch it.

**Preference order (prefer the earliest that fits):**
1. PATCH a currently-loaded skill (one read via `/skill-name` or skill_view this session).
2. PATCH an existing umbrella that covers the territory.
3. ADD a support file under an existing umbrella: `references/<topic>.md` (detail or condensed
   knowledge bank), `templates/<name>` (copyable starter), `scripts/<name>` (re-runnable probe).
4. CREATE a new class-level umbrella ONLY when nothing covers the class.

**Naming discipline (hard):** a new skill name MUST be class-level. NEVER a PR number, error
string, feature codename, library-alone name, or `fix-X / debug-Y / audit-Z-today` session
artifact. "If the name only makes sense for today's task, it's wrong" , fall back to patch.

**Do NOT capture (the highest-value guardrail , prevents drafts that rot into refusals):**
- Environment-dependent failures (missing binaries, `command not found`, unconfigured creds,
  post-migration path mismatches). The user fixes these; they are not durable rules.
- Negative claims about tools ("browser tools don't work", "X is broken"). These harden into
  self-cited refusals for months after the bug is fixed. Capture the FIX, never the complaint.
- Session-specific transient errors that resolved before the session ended (the lesson is the
  retry pattern, not the failure).
- One-off task narratives ("summarize today's market") , not a class of work.

**Memory vs skill (we only do skills; cc-harvest owns memory):** memory = who the user is +
current state; skill = how to do this class of task for this user. A user-preference complaint
belongs in the SKILL.md body, not just memory.

## B. OUR deliberate divergences from Hermes (the loop must NOT copy these)

| Hermes says | We do | Why |
|---|---|---|
| "Be ACTIVE , a no-op pass is a missed opportunity" | **Selective: returning `null` (no draft) is a valid, normal outcome** | Hermes auto-applies + curates later, so volume is cheap. We stage drafts for human promote; a flood of low-signal drafts burdens the gate. Quality over volume. |
| reviewer calls `skill_manage` (has Write) | reviewer returns a JSON draft; the trusted wrapper writes it | SPEC-103 DEC-008: model has no filesystem write, closes injection-to-arbitrary-write |
| auto-applies skills (`guard_agent_created:false`) | propose-and-stage; `/skill-review` promote gate | cockpit blast radius (NDA/SDD/ops) |
| no secret guard in prompt | reviewer prompt FORBIDS copying secrets/tokens into a draft | transcripts can carry printed creds |

Keep Hermes's "Nothing to save is real but not the lazy default" tension, but tuned: we want
HIGH-PRECISION drafts, so bias toward `null` unless a clear signal above fired.

## C. Curator (prompts/curator.md) , absorb from `CURATOR_REVIEW_PROMPT` + `CURATOR_DRY_RUN_BANNER`

**Framing:** "an UMBRELLA-BUILDING consolidation pass, not a passive audit and not a
duplicate-finder." A library of hundreds of narrow one-bug skills is a FAILURE, not a feature.

**Hard rules:**
1. NEVER delete , archive (our `git mv` to `_archive/`) is the maximum destructive action.
2. Skip pinned/protected skills entirely.
3. DO NOT use usage counters as a reason to skip , `use=0` is absence of evidence, not evidence.
4. Pairwise distinctness is the WRONG bar. The right bar: "would a maintainer write this as N
   skills, or as one skill with N labeled subsections?" If the latter, merge.

**Method:** scan for PREFIX CLUSTERS (shared first word / domain). For each 2+ cluster, ask "what
umbrella CLASS do these serve?" Three consolidation moves: (a) merge into an existing broad
umbrella, (b) create a new umbrella, (c) demote a narrow-but-valuable sibling to
`references/`/`templates/`/`scripts/` under the umbrella. Flag names that are too narrow (PR
number / codename / error string / audit artifact). Iterate , don't stop after 3 merges.

**Package integrity:** inspect a skill as a COMPLETE directory (it may have `references/`,
`templates/`, `scripts/`, `assets/`). Never flatten a skill that has support files or relative
links; re-home everything or archive the whole package. Never leave archived instructions
pointing at files left behind.

**Propose-only banner (our default + our launchd mode):** adopt the `CURATOR_DRY_RUN_BANNER`
shape , a loud "REPORT ONLY, DO NOT MUTATE" header, "your output IS the deliverable", "describe
the actions you WOULD take, not actions you took", and "a downstream reviewer decides whether to
approve a live run". This is exactly our `cc-improve curate` (no `--apply`) contract.

**Archive forwarding:** when archiving a skill whose content was absorbed, record
`absorbed_into=<umbrella>` (Hermes uses it for cron skill-reference migration; we use it in the
archive manifest so `restore` and any references stay coherent).

## Source

Live engine read 2026-06-19: `~/dev/hermes-agent/agent/background_review.py:34-235`,
`~/dev/hermes-agent/agent/curator.py:330-470`. Mechanism map:
`research/2026-06-19-hermes-self-improvement-loop.md`.
