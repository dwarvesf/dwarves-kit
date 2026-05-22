# AGENTS.md: the operating layer (spm)

> Tool-agnostic front door for the `spm` project. Any agent runtime (Claude Code,
> Codex, Gemini, a human) reads this first to learn how work is done in this repo.
> It carries the portable operate-contract: what to read, how to run a unit of
> work, when work is done, and when to stop and ask. This is the downstream
> template that ships with dwarves-kit; replace the `spm` specifics with your own.

## Enforcement boundary (read this first)

**This file is a contract, not a guardrail.** `spm` uses dwarves-kit, and the
kit's enforcement is Claude-Code-only: the hooks (safety-gate, push-to-main
blocker, anti-rationalization Stop hook, the verification pipeline) are what
actually block bad outcomes, and they run only under Claude Code. Under any other
runtime (Codex, Gemini, a bare LLM) this file is **advisory only**: it tells an
agent what to do, but nothing enforces it. Do not assume the guardrails are
portable. See `CLAUDE.md` for the Claude-Code layer (stack, rules, where the spec
lives).

The rest of this file is four portable zones. A goal-crafter projects them into a
six-section operating directive (see "How a goal is composed" at the end).

---

## 1. Read in this order

Orient before you touch anything. Read top to bottom; stop when you have enough.

1. **AGENTS.md** (this file) - how work is done here; the operate-contract.
2. **CLAUDE.md** - the project anchor: what `spm` is, the stack (Python 3.12 / uv / pytest / ruff), code-quality rules, where specs live.
3. **docs/specs/SPEC-NNN-<slug>.md** - the active spec; the shared contract for the cycle. Read its `## Verification` and `## After state` before implementing. (Today that is `docs/specs/SPEC-001-version-flag.md`.)
4. **WORKFLOW.md** - reference, not required per task. Read it for the lanes and the gate at each phase boundary.

## 2. Task loop

How to do one unit of work. The smallest verifiable increment, verified, committed.

1. **Size the lane.** Pick `tiny` / `normal` / `full` / `bug` / `backfill` per `WORKFLOW.md`. When in doubt between two lanes, take the heavier one.
2. **Read the spec and its acceptance criteria.** For a spec-driven task: the active spec's task row, its AC, its `## Verification`, and its `## After state`. No spec (tiny lane): the one obvious edit.
3. **Implement the smallest verifiable increment.** One logical change. No speculative features (`spm` does install/freeze/list; new subcommands need a spec), no premature abstraction (no `BaseCommand` until there are 6 commands); clarity over cleverness.
4. **Verify.** Run the spec's `## Verification` command, or the lane's check: `uv run pytest && uv run ruff check .`. Do not claim a result you did not run.
5. **Commit.** Conventional commit, one logical change. No spec/ticket IDs in the subject line.

If you cannot make progress, see zone 4 (Pause if) and stop with a named blocker note. Do not churn.

## 3. Done means

A task or goal is done only when **its acceptance criteria are met AND the
verifier actually ran the check**, not when you claim they pass. Self-reported
"done" is not proof.

Concretely, done means: **acceptance criteria met, the check actually ran (not
just asserted), review recorded + report written, and the final response says
what changed and what was not attempted.** If you could not run the check, report
that plainly; under Claude Code the anti-rationalization hook is the backstop for
premature completion, but the honesty obligation is yours under any runtime.

## 4. Pause if (ask a human)

Stop and ask a human before acting on any of these. These are decisions with
direction or irreversible cost that a goal loop must not make on its own.

- **Architecture direction** - a new subcommand, a new module, a change to the argparse dispatch shape, or any new public interface for the CLI.
- **Source-of-truth hierarchy** - which file or section is canonical when two disagree (for example, the operate-contract split across `AGENTS.md`, `CLAUDE.md`, and `WORKFLOW.md`).
- **Validation removal** - weakening, deleting, or skipping a test, a ruff rule, or any check; suppressing a `pip` subprocess error instead of propagating its exit code.
- **Risk-classification change** - moving work to a lighter lane, or narrowing a `full`-lane trigger (anything touching how `pip` is invoked, the wheel build, the published package, or `pyproject.toml` dependencies).
- **Privacy / security** - secrets, credentials, access scope, anything that touches what data leaves the repo or who can reach it.

When you pause: write the named blocker, state the decision you are not making and why, and stop.

---

## How a goal is composed

A goal-crafter projects these four zones into a six-section operating directive.
The mapping is a **composition, not 1:1**: two of the six sections come from the
active spec, not from this file. Keep the four zone names stable; renaming one
breaks the projection.

| Goal section | Source |
|---|---|
| Context-to-read | AGENTS.md zone 1 (Read in this order) |
| Constraints | CLAUDE.md / AGENTS.md rules |
| Operating rules | AGENTS.md zone 2 (Task loop) |
| Validation loop | the active spec's `## Verification` |
| Done-when | AGENTS.md zone 3 (Done means) + the active spec's `## After state` |
| Pause-if | AGENTS.md zone 4 (Pause if) |
