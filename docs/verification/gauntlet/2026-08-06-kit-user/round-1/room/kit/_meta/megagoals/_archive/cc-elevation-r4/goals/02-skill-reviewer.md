# Sub-goal 02: cc-self-improve skill-draft reviewer (Phase A)

**Time budget:** ~4-5h · **Depends on:** none · **Branch:** feat/cc-elev-r4-02-reviewer · **PR base:** main · **Merge policy:** auto

## Outcome

Scaffold `tools/cc-self-improve/` and ship the skill-draft reviewer: a PreCompact/SessionEnd
hook spawns a detached `claude -p` that, as a **no-write pure function**, reads the session and
returns a JSON skill draft; a **trusted bash wrapper** writes the draft to a staging directory and
logs cost. SPEC-103 TASK-001..005.

- Reviewer: `claude -p --bare --no-session-persistence --allowedTools "" --model haiku
  --output-format json`. The model has NO filesystem tools; it returns `{draft|null, cost}` on stdout.
- Staging writer (trusted bash): writes a returned draft to `~/.claude/skill-proposals/<slug>/SKILL.md`
  (the only place it writes a draft; NOT under `~/.claude/skills/`), appends `total_cost_usd` + tokens
  to `ledger.jsonl`.
- Transcript parser `lib/transcript.sh` (bash + jq): last-K user+assistant turns as compact text.
- Stop/hook spawn is detached, `--bare` + `CLAUDE_REVIEWING` sentinel + single-flight flock.

## Quality bar

Bash + jq, no daemon (SPEC-103 DEC-001). The model never has Write (`--allowedTools ""`); the
wrapper does every write to fixed paths (DEC-008, the validated security fix). Reviewer prompt
forbids copying secrets into a draft. Hooks return < 200 ms (async). Exit 0 on any `claude`/JSON
failure (log, no draft).

## How to close the loop

- Scaffold via `ops-tool-shape` (layout, tool.toml, README stub, .gitignore that never tracks
  skill-proposals, config.example.toml).
- Build `lib/transcript.sh` + a committed sample-transcript fixture; lock the per-line schema.
- Build `reviewer-run.sh` (trusted) + `prompts/review-skill.md`; wire the PreCompact/SessionEnd hook spawn. **`prompts/review-skill.md` MUST start from `tools/cc-self-improve/docs/hermes-prompt-patterns.md` section A** (signals, preference order, naming discipline, the "Do NOT capture" guardrails) AND honor section B (selective: returning `null` is valid; bias toward high precision, not Hermes's "always do something").
- Tests: a seeded "repeated manual workflow" transcript yields a draft; a no-signal transcript
  yields `null`; a seeded secret never appears in a draft; ledger line per run; malformed JSON logged not fatal.
- Start `tools/cc-self-improve/docs/proof-of-done.md` (multi-feature index per SPEC-016) with this feature's run-table.

**Done =** a seeded transcript produces a SKILL.md draft under `~/.claude/skill-proposals/` (and
only there); no-signal yields none; the reviewer runs `--allowedTools ""`; a ledger line per run;
transcript-parse + a basic async check green; proof index started; on PR #NN.

## Scope edges

**In:** scaffold, transcript parser, reviewer pure-function, staging writer, cost ledger, fixtures, proof.
**Out:** the promote gate + surfacing + install (03); the curator (04); memory capture (cc-harvest / 01).
**Not:** auto-activating a skill; the model writing any file; reimplementing writing-skills.

## Where to look

`tools/cc-self-improve/docs/specs/SPEC-103-cc-self-improve.md` (TASK-001..005, DEC-008, the
architecture block), `tools/cc-harvest/bin/cc-harvest` (transcript-read approach to reference, not
import: it is Python), `ops-tool-shape` skill, the guide-verified `claude -p` flags in
`docs/specs/CONTEXT.md`, `~/.claude/projects/*/*.jsonl` for a real transcript sample,
`docs/hermes-prompt-patterns.md` (the absorbed Hermes reviewer quality , section A + B).

## PR body

Outcome: cc-self-improve Phase A , no-write skill-draft reviewer + trusted staging writer + cost ledger + transcript parser.
Verify: seeded-transcript draft + no-signal negative control + secret-never-copied control; ledger line per run; proof run-table.
Roadmap: `_meta/megagoals/cc-elevation-r4/ROADMAP.md` (sub-goal 02).
