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

- **Phase A (shipped, this sub-goal): the skill-draft reviewer.** Transcript parser, the no-write
  reviewer, the trusted staging writer + cost ledger, `cc-improve status`.
- Phase B (next): `/skill-review` promote gate + SessionStart surfacing + install.sh + the full
  async/reentrancy/staging-gate test suite.
- Phase C (after): `cc-improve curate` consolidation + archive (never delete) + optional weekly
  propose-only launchd.

## Install (documented; not auto-wired)

Phase A ships the reviewer; the live hook wiring lands with `deploy/install.sh` in Phase B. To try
it now, add this entry (marked async) to the `PreCompact` and `SessionEnd` arrays in
`~/.claude/settings.json`, pointing at `hooks/skill-review.sh`:

```json
{ "type": "command", "command": "/abs/path/tools/cc-self-improve/hooks/skill-review.sh", "async": true }
```

Then review `~/.claude/skill-proposals/` and promote by hand (Phase B adds `/skill-review`).

## Knobs

Config: `~/.claude/cc-self-improve/config.toml` (copy `config/config.example.toml`). Every key is
also overridable by `CC_SI_<KEY>` (env wins; tests use this).

- `enabled` (default on), `model` (default `haiku`), `max_turns` (2), `transcript_k` (40).
- Paths: `CC_SI_STATE_DIR` (`~/.claude/cc-self-improve`), `CC_SI_PROPOSALS_DIR`
  (`~/.claude/skill-proposals`), `CC_SI_SKILLS_DIR` (`~/.claude/skills`).
- Cost: every reviewer run appends `total_cost_usd` to `ledger.jsonl`; `cc-improve status` shows
  7-day loop spend and the staged-draft count. Dial back by raising `transcript_k` cost via a bigger
  `model` only if needed, or disable via `enabled = false`.

## Test

```bash
bash tests/test-transcript-parse.sh   # parser locked against a committed sample (6)
bash tests/test-reviewer.sh           # wrapper: stage / null / secret-drop / unavailable / lock (10)
bash tests/test-hook-async.sh         # hook returns fast; detached reviewer; reentrancy; disabled (4)
```

All use a mock reviewer (`CC_SI_REVIEWER_CMD`); no live model. Proof + a recorded run:
`docs/proof-of-done.md`.
