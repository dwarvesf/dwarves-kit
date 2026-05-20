# ADR-0012: Adopt systematic-debugging as a command+hook hybrid (refines ADR-0008)

## Status: accepted (2026-05-21). Refines ADR-0008.

## Context
ADR-0008 (v1.3) studied obra/superpowers and *deferred* three of its skills (`test-driven-development`, `systematic-debugging`, `using-git-worktrees`) with the rule: "if they become real gaps, build them as **hooks** per `Guardrails over guidance`, **not** skills."

By 2026-05-21 the gap analysis (maintainer request) found systematic-debugging is the one real lifecycle hole: the kit's lanes are all feature-shaped (`/think -> /spec -> /execute -> /review -> /ship -> /retro`), with no path for a defect, regression, or failing test. The kit already guards the *completion* side (anti-rationalization blocks premature "done"; task-verifier blocks unverified completion) but nothing covers the *diagnosis* side. A cross-framework survey (GSD `gsd-debugger`, doraemonkeys debug-mode, SuperClaude `/sc:troubleshoot`; classic lineage Agans + Zeller) confirmed the four-phase model is the floor and surfaced higher-value borrowable mechanisms.

The deferral's "as a hook, not a skill" rule now collides with reality: a four-phase root-cause loop is irreducibly judgment-driven, and a bash hook cannot run it. A hook can only pattern-match the *smell* of guess-fixing.

## Decision
Adopt systematic-debugging as a **hybrid**, not as a single primitive:
- **The method is a command** (`commands/debug.md`, invoked `/user:debug`): the four phases, the iron law ("no fix without a recorded root cause"), the 3-failed-fixes-question-architecture wall, an append-only evidence ledger under `.claude/debug/<slug>.md`, `[DEBUG Hn]`-tagged instrumentation to `.claude/debug/<slug>.log` with region-marker cleanup, `git bisect` for regressions, failing-test-first routed into the existing verification pipeline (ADR-0005), and human-confirm before declaring "fixed".
- **The enforcement is a hook augment** (`hooks/anti-rationalization.sh`): a guess-fix guard that blocks a premature fix/done claim, gated so it fires ONLY when an active ledger still has an empty `## Root cause`. Silent in all non-debug sessions.

This is a deliberate, documented **refinement** of ADR-0008, not a silent reversal. ADR-0008's "as a hook, not a skill" rule stands for *pure enforcement*; debugging is a *judgment* task, and the kit already ships judgment tasks (`/think`, `/review`, `/spec-validate`) as commands. The hook half preserves the enforcement ADR-0008 wanted, scoped so it cannot pollute normal coding.

## Alternatives considered
- **Command-only.** Rejected: pure guidance (~70% adherence); nothing stops an agent skipping the command and guess-fixing. Loses the enforcement ADR-0008 valued.
- **Hook-only (ADR-0008's literal preference).** Rejected as insufficient alone: a bash hook cannot run a four-phase reasoning loop; it catches the symptom of bad debugging without teaching the method.
- **A standalone debugger subagent (GSD `gsd-debugger` style).** Deferred: the command plus the existing verification pipeline cover the need without a new agent file ("every file justifies its existence"). Re-open if the inline command proves too heavy.
- **Minimal four-phase spine only (no ledger/bisect/tagged-logs).** Rejected by maintainer in favor of the enriched scope, because the survey showed those mechanisms are the genuinely high-value borrows and all are bash/sed/git-native (no new dependency).
- **A new dedicated hook file for the guard.** Rejected: `anti-rationalization.sh` already owns "premature done"; augmenting it avoids a new file and keeps the Stop-gate logic in one place.

## Consequences
- New command `commands/debug.md`; the kit goes from 13 to 14 commands.
- `anti-rationalization.sh` gains a second, gated block (the guess-fix guard). Measured latency ~26ms, well under the 500ms hook budget. The guard is dormant unless `.claude/debug/` holds a root-cause-empty ledger, so non-debug sessions are unaffected.
- A new runtime write target `.claude/debug/` (ledger `.md` + instrumentation `.log`). Already covered by the kit's existing `.claude/` gitignore; downstream templates ignore `.claude/` too.
- The command<->hook contract is the literal heading `## Root cause`. A `tests/test-meta.sh` assertion pins that literal in both files so a rename on one side breaks the build instead of silently disabling the guard.
- No new dependency: `git bisect` is git-native; instrumentation and cleanup are bash/sed.
- Pain signal was anticipated-not-observed at adoption time (no retro recorded debugging thrash); recorded as the owner-accepted risk to revisit at `/user:retro`. See SPEC-013 DEC-006.
- Source: SPEC-013; obra/superpowers `systematic-debugging`, glittercowboy/get-shit-done `gsd-debugger`, doraemonkeys/claude-code-debug-mode, SuperClaude `/sc:troubleshoot`; Agans "Debugging: The 9 Indispensable Rules"; Zeller "Why Programs Fail". Refines ADR-0008; reuses ADR-0005 (verification pipeline).
