---
name: skill-review
description: Review and promote skill drafts that skill-curator staged from past sessions. Use when the user runs /skill-review, says "review my skill drafts", "promote a staged skill", or asks what skills the self-improvement loop proposed. Lists drafts under ~/.claude/skill-proposals/, runs the inline skill quality bar on each, then promotes the approved ones into ~/.claude/skills/ or rejects them.
disable-model-invocation: false
---

# skill-review (the promote gate)

skill-curator's background reviewer stages skill drafts under `~/.claude/skill-proposals/`. It
NEVER writes `~/.claude/skills/`. This skill is the human gate that promotes a vetted draft into the
live library. `bin/skill-review` (from `lib/skill-curator/`, put it on PATH or invoke by its full
path) is the only writer of `~/.claude/skills/`.

## Flow

1. **List** the staged drafts:
   ```bash
   skill-review list      # tab-separated: <slug>\t<description>
   ```
   If "(no staged drafts)", stop and say so.

2. **For each draft**, read `~/.claude/skill-proposals/<slug>/SKILL.md` and vet it against the
   quality bar below (self-contained; no external plugin needed):
   - Is the name class-level (not a PR number, error string, codename, or today-only artifact)?
   - Is the `description` a real trigger (what class of task + when), so a future agent matches it?
   - Is it a genuine reusable pattern, or environment-dependent / a complaint that will rot into a
     refusal? Drop the latter.
   - **Secret scan**: confirm no token / key / credential is in the body. `promote` also refuses a
     draft that still contains one, but check first.
   - Would this be better as a PATCH to an existing umbrella, or a `references/` add, than a new
     skill? If so, reject and patch by hand.
   - **Baseline first (pressure test).** Does the draft change agent behavior? Run a subagent on a
     realistic scenario WITHOUT the skill and record its rationalizations verbatim ("too simple to
     need it", "I'll do it after", "this case is different"). A skill with no observed failure to
     fix is speculation. Then run the same scenario WITH the draft and confirm the behavior changes.
   - **Close loopholes.** Each verbatim rationalization gets a row in a rationalization table
     (excuse | reality) and a matching red-flag line. If a re-run finds a new excuse, add a row.
   - **Description states triggers only**, never the workflow. A description that summarizes the
     steps lets the agent follow the summary and skip the body. Start with "Use when ...".

3. **Decide per draft** (always show the user the draft and your read before acting):
   - Approve -> `skill-review promote <slug>` (moves it into `~/.claude/skills/<slug>/`; refuses to
     overwrite a live skill without `--force`).
   - Reject -> `skill-review reject <slug>` (moves it to `_rejected/`, recoverable, never deleted).

4. **Report** what was promoted vs rejected, and any draft you left staged for the user to decide.

## Rules

- Never promote a draft you have not read and vetted against the quality bar above.
- Never `--force` overwrite a live skill without explicitly confirming with the user first.
- Promotion is the ONLY path a draft enters `~/.claude/skills/`. The reviewer cannot (it runs with
  no write tool). Keep it that way.
- An optional `auto_promote` config knob (default OFF) can auto-pass the lowest-risk class only
  (a `references/` add to an existing umbrella) via `skill-review auto`; everything else is manual.
