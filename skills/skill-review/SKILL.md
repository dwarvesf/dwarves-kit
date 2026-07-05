---
name: skill-review
description: Review and promote skill drafts that skill-curator staged from past sessions. Use when the user runs /skill-review, says "review my skill drafts", "promote a staged skill", or asks what skills the self-improvement loop proposed. Lists drafts under ~/.claude/skill-proposals/, runs the writing-skills quality bar on each, then promotes the approved ones into ~/.claude/skills/ or rejects them.
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

2. **For each draft**, read `~/.claude/skill-proposals/<slug>/SKILL.md` and vet it. **Run the
   `superpowers:writing-skills` checklist** (this skill does NOT reimplement it , delegate):
   - Is the name class-level (not a PR number, error string, codename, or today-only artifact)?
   - Is the `description` a real trigger (what class of task + when), so a future agent matches it?
   - Is it a genuine reusable pattern, or environment-dependent / a complaint that will rot into a
     refusal? Drop the latter.
   - **Secret scan**: confirm no token / key / credential is in the body. `promote` also refuses a
     draft that still contains one, but check first.
   - Would this be better as a PATCH to an existing umbrella, or a `references/` add, than a new
     skill? If so, reject and patch by hand.

3. **Decide per draft** (always show the user the draft and your read before acting):
   - Approve -> `skill-review promote <slug>` (moves it into `~/.claude/skills/<slug>/`; refuses to
     overwrite a live skill without `--force`).
   - Reject -> `skill-review reject <slug>` (moves it to `_rejected/`, recoverable, never deleted).

4. **Report** what was promoted vs rejected, and any draft you left staged for the user to decide.

## Rules

- Never promote a draft you have not read and vetted against writing-skills.
- Never `--force` overwrite a live skill without explicitly confirming with the user first.
- Promotion is the ONLY path a draft enters `~/.claude/skills/`. The reviewer cannot (it runs with
  no write tool). Keep it that way.
- An optional `auto_promote` config knob (default OFF) can auto-pass the lowest-risk class only
  (a `references/` add to an existing umbrella) via `skill-review auto`; everything else is manual.
