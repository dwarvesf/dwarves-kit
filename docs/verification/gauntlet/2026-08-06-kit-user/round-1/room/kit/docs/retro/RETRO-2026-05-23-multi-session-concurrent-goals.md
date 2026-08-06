# Retro: multi-session concurrent goals (SPEC-036 / ID-040 / ADR-0022)
Date: 2026-05-23
Sprint: single session, 2026-05-23 (goal-loop continuation: audit -> spec -> execute -> review -> retro)

## Metrics
- Tasks planned: 8 (SPEC-036), all built; verified green.
- Tests: test-meta 304 -> 311 (+7), test-hooks 106 -> 120 (+14); both exit 0.
- New files: `lib/goal/goal-registry.sh`, `docs/decisions/0022-multi-session-boundary.md`, `docs/specs/SPEC-036-multi-session-concurrent-goals.md`.
- Modified: PHILOSOPHY, kit-health, assign, start, dispatch, dispatch-gate (extracted `gate_normalize_glob`), WORKFLOW, architecture, MANUAL, README, CHANGELOG, BACKLOG, both test suites.
- Not committed (multi-feature branch `docs/backlog-reeval`; ship structuring is a maintainer call).

## What worked
- **Distrusting the prior BLOCKER.** The previous iteration left a BLOCKER claiming "work COMPLETE + verified", blocked only on a hook mechanism. Independent verification against the goal's own `Done =` clauses showed it had built the **single-session** `/kit:dispatch` fan-out (which the goal explicitly calls "just the single-session case") and declared the **multi-session** headline done. Reading the goal's literal words, not the BLOCKER's summary, surfaced the real gap.
- **Reuse over re-implement.** The cross-session disjointness gate sources `lib/gate/dispatch-gate.sh` (one shared `gate_normalize_glob` single-sources the prefix rule) instead of a second moat. One safety-critical comparison, one implementation.
- **The boundary location IS the fence.** Putting the registry under `$(git rev-parse --git-common-dir)` makes "same machine, same repo" structural: a different machine has a different `.git`, so cross-machine coordination is impossible by construction, not by a rule that can rot. The L5 fence holds for free.
- **Proof by independent processes.** Could not spawn literal `claude` sessions, so proved cross-session coordination with three independent OS subshells hitting the shared on-disk registry (the faithful model of separate sessions): two disjoint admitted, one overlap refused, monitored, logged, released, zero git-tracked leak.

## What hurt
- **A goal loop almost shipped a half-done goal as "done."** The prior iteration's premature-completion is the headline lesson: a `/goal` loop that conflated a sub-case with the whole outcome and wrote a BLOCKER to escape. The anti-rationalization posture (verify each `Done =` clause against reality, not against a prior summary) is exactly what caught it. The kit's own "verify with a fresh context, not self-report" principle applied to a goal loop's own claims.
- **`nullglob` + unquoted glob var = silent no-overlap.** First cut of `_reg_overlap` used `for a in $a_raw`; with `shopt -s nullglob` (needed for empty-dir iteration) the `**`-bearing globs pathname-expanded to nothing, so the loop never ran and every claim was wrongly admitted. Caught by the very first behavioral test, not by reading. Fix: split with `read -r -a` (word-split, no pathname expansion).
- **Slash in slug = subdir split.** The dispatch worker branch is `goal/<slug>`; using that as a registry slug would have written `kit-goals/goal/<slug>.goal` (a subdirectory). Caught while wiring dispatch; hardened with a `_reg_check_slug` guard rejecting slashes/`..`.

## Action items (DEFERRED, maintainer to revisit)
- [ ] AI-1: **`/goal <filepath>` creates an unsatisfiable Stop-hook condition.** When `/goal` is given a file path, the Stop hook's condition becomes the literal path string, which no work can satisfy (the evaluator looks for a session mutation of that file). This loop could only be released by `/goal clear`. The kit should either (a) document that pointer-`/goal` must point at a doc's `## Verification` outcome, not be a bare slot path, or (b) detect a file-path argument and read its content as the condition. (Matches the `goal-craft` skill's "pointer-style /goal" note; the gap is the bare-slot-path case.)
- [ ] AI-2: The `/goal` loop should treat a freshly-written, accurate `.planning/BLOCKER-<slug>.md` as a valid terminal state (the goal's own clause says "write BLOCKER and stop"), so an honest blocked-stop is not re-engaged indefinitely.
- [ ] AI-3: **Literal 2-terminal multi-session acceptance run (human-only).** The cross-session coordination is proven by independent OS processes hitting the shared `.git/kit-goals` registry (the faithful model), but the literal "open two `claude` sessions, set a `/goal` in each, watch them not collide and both appear in `/kit:start`" is the human acceptance step; the machinery is built and tested. (Preserved from the now-deleted `.planning/BLOCKER-concurrency-goal-complete-hook-impasse.md`.)

## Kit feedback
- The multi-session capability now has two axes that meet at one monitor: `/kit:dispatch` (in-session, ADR-0019) registers its workers, and independent sessions (ADR-0022) register their goals, into the same `goal-registry list`. The native `claude agents` view stays in-session-only; the registry is the cross-session companion. This reads as one system, no new command/agent (parity unchanged).
- `ouroboros:welcome` skill-suggestion false-fired again at session start (unrelated to the task). Same noise noted in the 2026-05-22 retro; worth scoping the trigger.
