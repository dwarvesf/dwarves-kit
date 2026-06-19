# cc-self-improve

The **skill half** of the Hermes self-improvement loop, for Claude Code. cc-harvest already ships
the memory half (transcript -> learnings -> `learned-ledger.md`). cc-self-improve adds: a
background reviewer that **drafts a reusable SKILL.md** from a session, a **promote gate**, and a
**curator** that consolidates + archives (never deletes). Same posture as the rest of the suite:
read-only, propose-and-stage, background, non-blocking.

Master spec: `docs/specs/SPEC-103-cc-self-improve.md` (VALIDATED). Suite parity is asserted at the
cc-elevation-r4 mega-goal, not here.

## The one idea: the model has no write

```
PreCompact/SessionEnd ─▶ skill-review hook (async) ─▶ nohup reviewer-spawn.sh & ; hook returns now
                                                          │
   reviewer-run.sh (TRUSTED bash):                        ▼
     last-K turns ─stdin▶ CLAUDE_REVIEWING=1 claude -p --bare --no-session-persistence
                          --allowedTools "" --model haiku --output-format json
                              │ returns JSON {draft?, reason}  (model has NO filesystem write)
                              ▼
     wrapper writes draft ▶ ~/.claude/skill-proposals/<slug>/SKILL.md   (NEVER ~/.claude/skills/)
     wrapper appends cost ▶ ~/.claude/cc-self-improve/ledger.jsonl

   /skill-review ─▶ writing-skills checklist ─▶ mv proposal ─▶ ~/.claude/skills/<name>/   (Phase B)
   cc-improve curate ─▶ claude -p plan ─▶ wrapper git-mv to skills/_archive/ (never rm)     (Phase C)
```

The reviewer **`claude -p` process runs `--allowedTools ""`**, so the model cannot write any file.
Only the trusted bash wrapper writes, and only to `skill-proposals/` (a path Claude Code does NOT
auto-load) and the cost ledger. Even a prompt-injected transcript cannot make a skill appear under
`~/.claude/skills/`: staging-by-path is a structural gate, not a prompt instruction (SPEC-103
DEC-008). Promotion into the live library is a separate, human-run step.

## Status

- **Phase A (shipped): the skill-draft reviewer.** Transcript parser, the no-write reviewer, the
  trusted staging writer + cost ledger, `cc-improve status`.
- **Phase B (shipped): the gate + visibility + install.** `/skill-review` promote gate
  (`bin/skill-review`), SessionStart surfacing, idempotent `deploy/install.sh` / `uninstall.sh`,
  and the full staging-gate / async / reentrancy test suite.
- Phase C (next): `cc-improve curate` consolidation + archive (never delete) + optional weekly
  propose-only launchd.

## Install

```bash
bash deploy/install.sh        # idempotent: wires the hooks (async) into ~/.claude/settings.json, backs it up first
```

This adds the skill-review reviewer on PreCompact + SessionEnd and the surfacing hook on
SessionStart (all `"async": true`), seeds `~/.claude/cc-self-improve/config.toml`, and is safe to
re-run (no duplicate entries). `deploy/uninstall.sh` removes only this tool's entries (state and
staged drafts are kept). Tune via the config; `CC_SI_SETTINGS` lets you target a non-default
settings.json.

After a session stages drafts, review them:

```bash
skill-review list                 # what the loop proposed
skill-review promote <slug>       # vet (writing-skills) then move into ~/.claude/skills/
skill-review reject <slug>        # move to _rejected/ (recoverable)
```

Or run `/skill-review` (the skill) for the guided, vet-each-draft flow.

## Knobs

Config: `~/.claude/cc-self-improve/config.toml` (copy `config/config.example.toml`). Every key is
also overridable by `CC_SI_<KEY>` (env wins; tests use this).

- `enabled` (default on), `model` (default `haiku`), `max_turns` (2), `transcript_k` (40).
- Paths: `CC_SI_STATE_DIR` (`~/.claude/cc-self-improve`), `CC_SI_PROPOSALS_DIR`
  (`~/.claude/skill-proposals`), `CC_SI_SKILLS_DIR` (`~/.claude/skills`).
- Cost: every reviewer run appends `total_cost_usd` to `ledger.jsonl`; `cc-improve status` shows
  7-day loop spend and the staged-draft count. Dial back by raising `transcript_k` cost via a bigger
  `model` only if needed, or disable via `enabled = false`.

- `auto_promote` (default OFF): closer Hermes parity; auto-passes only the lowest-risk class (a
  `references/` add to an existing umbrella) via `skill-review auto`. Everything else stays manual.

## Test

```bash
# Phase A
bash tests/test-transcript-parse.sh   # parser locked against a committed sample (6)
bash tests/test-reviewer.sh           # wrapper: stage / null / secret-drop / unavailable / lock (10)
bash tests/test-hook-async.sh         # hook returns fast; detached reviewer; reentrancy; disabled (4)
# Phase B
bash tests/test-staging-gate.sh       # draft stays in proposals/; traversal slug contained; no model write (5)
bash tests/test-promote.sh            # promote/reject/force-backup/secret-refuse/auto-eligibility (9)
bash tests/test-surface.sh            # SessionStart counts + JSON; disabled control (4)
bash tests/test-async.sh              # sleep-30 reviewer never blocks the hook (2)
bash tests/test-reentrancy.sh         # a reviewer cannot trigger a reviewer (3)
bash tests/test-install.sh            # idempotent install + surgical uninstall, temp settings.json (6)
```

All use a mock reviewer (`CC_SI_REVIEWER_CMD`) / temp dirs; no live model, never the real
settings.json. Proof + a recorded run:
`docs/proof-of-done.md`.
