---
title: Mega-goal execution hygiene , delegation, discovery cost, model routing, ledgers, multiplexer
date: 2026-07-03
purpose: >
  Consolidates the execution-economics analysis from the 873k-context session: why big
  mega-goal runs overflow context, the delegate-vs-inline run modes, the discovery cost of
  fresh sessions (first-principles + a measured data point), handoff as the discovery-cost
  lever, per-sub-goal model routing (planning->opus), whether delegated claude -p sessions
  still emit the ledgers as designed, and the terminal-multiplexer control plane. Feeds
  dwarves-kit ADR-0032 + the orchestrate-hardening mega-goal.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: as-needed
next_review: null
status: active
---

# Mega-goal execution hygiene

Companion to `research/2026-07-03-understanding-bottleneck-sdlc.md` (the Addendum there first
surfaced the /goal-accumulation finding). This note is the execution-economics half.

## 1. Run modes , delegate vs inline

`/goal` is the OFFICIAL Anthropic-maintained loop and stays the OUTER conductor. Two modes for
what it DOES per turn:
- **INLINE:** the /goal session executes each sub-goal in its OWN context , everything accumulates
  (873k on a 9-sub-goal run). Simple, watch closely; fine for <= 4 sub-goals.
- **DELEGATE (default > 4):** the loop is a THIN CONDUCTOR , for each sub-goal it makes ONE Bash
  call to a fresh headless `claude -p` (plain `-p`, NEVER `--stream`/`--verbose` to the conductor)
  that runs the full lifecycle in its own context and prints back ONLY a terse result (box flipped,
  PR #, proof). The conductor absorbs one line per sub-goal, does the auto-bottom-up merge, delegates
  TIER-4 the same way, holds only roadmap + terse results.

`orchestrate.sh run <dir>` is the BASH-DRIVEN form of delegate (enforces it deterministically);
the /goal-conductor is the MODEL-DRIVEN form (relies on the loop obeying a forceful clause). Verified
2026-07-03: recent mega-goals ALREADY delegate , the per-sub-goal run-ledger rids (`sg-01`,
`kit-face-04-tiers`, `SPEC-105..109`) are the evidence. Wired into the plan-for-mega-goal template
(dotfiles 6a2c7c0).

## 2. Discovery cost of fresh sessions (first principles + data)

Tom's framing mapped to us: "exploration subagent a bit cheaper" = our fresh `claude -p` (pays
DISCOVERY D, not the parent context); "context-inheriting subagent 3x+" = a FORK (we do NOT use forks
to delegate , our workers start COLD, avoiding the 3x); "skill inline keeps cache" = the inline /goal
mode (rides cache but accumulates).

Delegate TRADES accumulation for repeated discovery. For N sub-goals, work W each, discovery D each:
- **Inline:** context -> N*W; the growing context's CACHE-READ re-billing dominates (measured earlier:
  772M cache-read : 1.6M uncached = the cost center) -> eventual compaction (lossy).
- **Delegate:** each sub-goal = D + W, fresh, dies. Total ~ N*(D+W). No pile-up, no compaction.
- Delegate wins as N grows (D is fixed per sub-goal; inline's cache-read grows with N). Matches the
  > 4 default.

Measured data point: the ledger-observatory scaffold worker (a fresh subagent, our delegate kind) cost
**206k tokens / 70 tool calls**. Rough split: discovery (read understanding-gate ~5 files + the research
note ~= 30-50k) + work (write 9 files + git ~= 150k). So **discovery ~= 20-25%** , Tom's "a bit
cheaper", real but not free. Critically it did NOT inherit the lead's ~800k context , THAT would have
been the 3x fork tax. The delegate pattern is the cheap kind by construction.

**D (discovery) is the tax of fresh sessions.** The lever to shrink it is section 3.

## 3. Handoff is the discovery-cost lever

`handoff` (skill) and the mega-goal's built-in `HANDOFF.md` (HOT) + `DECISIONS.md` (WARM) shrink D:
a fresh worker reads a curated NEXT-ACTION + `file:line` POINTERS instead of cold-reading many files,
then reads only the pointed SLICES , not everything. orchestrate.sh already injects HANDOFF.md into the
next sub-goal. Calibration is the catch: POINTERS, not dumps , a dump bloats the worker's start; a
too-terse handoff forces re-discovery. Done right it cuts D hard. Net: delegate avoids accumulation;
handoff minimizes the discovery it costs. Complementary levers.

## 4. Model routing , planning -> opus (wired)

Route by the sub-goal's DOMINANT work-type at decompose time (`Model:` field -> orchestrate `--model`).
Per-SUB-GOAL, not per-phase (Claude Code cannot switch model mid-session, so a sub-goal that is mostly
execution with a small /spec phase still runs one tier , pick by what dominates):
- **opus** , planning/thinking/design dominates (schema/architecture design, spec-heavy, hard tradeoffs).
  The operator's rule: planning is where the smart model earns its cost.
- **sonnet** , execution dominates (build-from-clear-spec, wiring, mechanical).
- **haiku** , trivial (config flip, doc line, rename).
Wired into the template (dotfiles 50995cc). Observed gap it fixes: the ledger-observatory worker put
SG-01 (schema DESIGN) on sonnet by a "substantial->opus" heuristic; the "planning->opus" rule would put
it on opus. The mega-goal-level planning the LEAD does (think/design/decompose) also runs the smart tier.

## 5. Do delegated sessions still emit the ledgers? Yes, with one reconciliation

- **Gate/proof/run ledgers: YES, proven.** Each delegated session runs the kit lifecycle and records
  gate-ledger lines under its own rid , the per-sub-goal rids ARE that evidence.
- **Token ledger (kit-face SG-03): TENSION -> stream-to-FILE.** Token capture is gated on `--stream`,
  but delegate uses plain `-p` (no --stream to the conductor). Resolution: stream the child to a FILE
  (`claude -p --stream > child.jsonl`), capture usage from the file, the conductor reads only the
  box-flip / terse result. Both hold. Fold into SG-03.
- **Debt ledger (understanding-gate): split, by design.** The worker writes the significance/worthiness
  marker; the ★-tap nudge fires at the CONDUCTOR (where the human is). Consistent with SG-02/SG-04.

## 6. Multiplexer , the terminal control plane (tmux/cmux, not ghostty)

The browser-tab pattern's terminal analog is the MULTIPLEXER, not the emulator. Ghostty is the display
(minimal scripting); tmux/cmux running inside it is the control plane (all three installed):
`tmux new-window 'claude -p ...'` (spawn) · `tmux capture-pane` (receive) · `tmux send-keys` (pass /
control / intervene). Zero new infra (minimum-infra rule).

Honest challenge: for pure ORCHESTRATION (spawn/control/receive) you do NOT need multiple terminals ,
Bash + `claude -p` already does it headlessly (the delegate pattern). The multiplexer ADDS visibility +
interactive intervention (watch each session in a pane, jump in). The natural fit: wavefront already runs
parallel `claude -p` in the background (headless, unwatchable); spawning each wave session into a
tmux/cmux pane gives the "watch + intervene across tabs" experience. A small orchestrate.sh enhancement,
not a new daemon.

## 7. Kill-resilience , what the orchestrate-hardening run actually taught (field-proven)

The orchestrate-hardening run itself was the stress test: its `claude -p` workers were killed repeatedly
(one auth expiry, several hard-kills). It still shipped 5/5 sub-goals. Three rules made the difference,
now codified in `_meta/megagoals/OPERATE.md` "Worker checkpoint discipline":

1. **Commit before, and independently of, pushing.** Push can fail (headless children cannot re-auth when
   the token expires mid-run); commit cannot. The run recovered work from three distinct kill shapes , a
   deleted branch, a killed-post-commit branch, and an uncommitted worktree , purely from git state. So
   every worker commits at phase boundaries (post-build, post-review); a killed worker must be fully
   recoverable from git + its rid ledger alone. This is the single load-bearing rule.
2. **In-harness subagents are kill-immune where `claude -p` children are not.** A subagent shares the
   conductor's auth + lifecycle, so the auth-expiry/hard-kill class simply does not apply to it. Running
   the TIER-4 review/verify lenses as in-harness subagents (not headless children) is exactly why the
   CRITICAL command-injection in the multiplexer pane-spawn was caught before it shipped. This is also the
   deeper argument for subagent-delegate (section 1) as the default WORKER mode, not only a context-hygiene
   choice , it is a resilience choice.
3. **A missing rid ledger is a recovery signal, not a bookkeeping gap.** "No rid log for sub-goal N"
   almost always means killed-pre-ledger; the conductor should treat it as "go check N's branch/worktree
   for unpushed work", not "N did less". (dwarves-kit board ID-099 makes this a conductor-side check.)

Corollary for the conductor: before re-dispatching any dead worker, inspect its branch AND worktree first;
re-dispatch only what git does not already hold. Recovery beats restart.

## Status

Wired: run-mode option (dotfiles 6a2c7c0), model routing (dotfiles 50995cc), subagent-delegate default +
progress strips + visible close + checkpoint discipline (dotfiles f64def8/a4fad84/105919e/1e40278 +
`_meta/megagoals/OPERATE.md`). Design: dwarves-kit ADR-0032. Built + SHIPPED: the orchestrate-hardening
mega-goal , model-routing enforcement (#139), token-capture stream-to-file (#140), TIER-4 mega-close
(#141), multiplexer panes (#142) + injection fix (#143) + docs (#144); PANE_VIEWER push-default (#145).
