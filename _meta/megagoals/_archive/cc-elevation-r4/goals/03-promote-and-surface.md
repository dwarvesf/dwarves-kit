# Sub-goal 03: promote gate + surfacing + install (Phase B)

**Time budget:** ~4-5h · **Depends on:** 02 · **Branch:** feat/cc-elev-r4-03-promote · **PR base:** feat/cc-elev-r4-02-reviewer · **Merge policy:** auto

## Outcome

Close the human gate and make the loop visible + installable. SPEC-103 TASK-006..010.

- `/skill-review` promote skill: lists `~/.claude/skill-proposals/` drafts, runs the
  `writing-skills` checklist (incl. a secret scan), and on approval `mv`s a draft into
  `~/.claude/skills/<name>/`; reject discards; refuses to overwrite a live skill without `--force`.
- SessionStart surfacing hook: `additionalContext` line with cc-harvest staged-memory count +
  skill-draft count + 7-day loop spend from the ledger.
- `install.sh` / `uninstall.sh`: idempotent read-merge-write of the skill-review (PreCompact +
  SessionEnd) and SessionStart hooks into `~/.claude/settings.json` (backup first, `"async": true`).
- The staging-gate + async + reentrancy tests.
- **OPTIONAL `auto_promote` config knob (default OFF), for closer Hermes parity without losing the
  default gate.** When on, `/skill-review`'s auto-pass promotes ONLY the lowest-risk class: a draft
  that ADDS a `references/<topic>.md` support file under an EXISTING agent-created umbrella (never a
  new skill, never a SKILL.md-body/trigger edit, never a non-agent-created skill), and only if the
  draft passes the writing-skills secret-scan. Everything else still stages for manual promote.
  Document the risk (auto-applied additive context can still be wrong) in the config comment.

## Quality bar

`/skill-review` is the ONLY writer of `~/.claude/skills/` (the reviewer never is). Promote
delegates quality to `writing-skills`, does not reimplement it. install is idempotent (twice = no
dup entries), backs up settings.json, uninstall removes only this tool's entries. SessionStart
hook returns fast.

## How to close the loop

- `tests/test-staging-gate.sh`: a proposal under `skill-proposals/` is NOT discovered/auto-invocable
  by Claude Code, AND the reviewer (no Write) cannot write under `skills/` given an adversarial transcript.
- `tests/test-async.sh` (negative control: a `sleep 30` reviewer does not delay the hook return or
  next prompt) + `tests/test-reentrancy.sh` (a reviewer cannot trigger a reviewer).
- Build the `/skill-review` skill + the SessionStart surfacing hook + `install.sh`/`uninstall.sh`.
- Manual real run: promote a real draft end-to-end; confirm SessionStart shows the line.
- Extend `tools/cc-self-improve/docs/proof-of-done.md` with these features' run-tables + the negative controls.

**Done =** `/skill-review` promotes a draft into `~/.claude/skills/` only after the writing-skills
checklist; SessionStart shows "N memory, M skill drafts, $X/wk"; staging-gate + async + reentrancy
tests green; install idempotent + backs up settings.json; proof updated; on PR #NN.

## Scope edges

**In:** promote skill, surfacing hook, install/uninstall, the three guard tests, proof.
**Out:** the curator (04); the per-turn memory trigger (01).
**Not:** auto-promoting a draft; surfacing that writes anything; editing settings.json by blind overwrite.

## Where to look

SPEC-103 TASK-006..010 + the Failure modes table, `superpowers:writing-skills` (the promote
delegate), the cc-worktree-provision settings.json read-merge-write pattern, the cc-harvest async
hooks (the surfacing reads cc-harvest's staged-memory count from `_meta/learned-ledger.md`),
SPEC-103 SessionStart `additionalContext` contract.

## PR body

Outcome: cc-self-improve Phase B , /skill-review promote gate + SessionStart surfacing + idempotent install + guard tests.
Verify: staging-gate + async + reentrancy green; a real promote end-to-end; SessionStart line shown; proof run-tables.
Roadmap: `_meta/megagoals/cc-elevation-r4/ROADMAP.md` (sub-goal 03).
