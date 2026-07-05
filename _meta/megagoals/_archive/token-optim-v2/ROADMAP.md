# Mega-goal: token-optim-v2

> Canonical design reference: `research/2026-06-29-token-coherence-design.md` (the principle +
> architecture + index). REFRAME (token-efficient note): the real objective is COHERENCE over a
> long run; lower token is the SIDE EFFECT. A lever that cuts tokens but hurts coherence
> (turns-to-green / rework up) is DROPPED, not kept. This ROADMAP is the execution plan; the
> design doc is the why.

## Destination
Make the kit execute a mega-goal at structurally-lower token cost AND full observability.
Builds directly on token-hygiene (the orchestrator + `--loops` measurement): mature the
orchestrator (run-modes, two-tier handoff, per-sub-goal model/effort routing, distilled
returns), add the cheap-planner split, enforce output-offload + deterministic verify, trim the
static floor, teach the composer skill to emit the new fields, and PROVE the win with a
before/after `token-forensic --loops` comparison. Non-deployable (kit framework + tooling +
docs); terminus = all sub-goals merged-or-held + SG-09 shows the measured win. No deploy/UAT
gate (intentional).

## Hard dependency (read first)
This whole wave builds on token-hygiene's foundation, currently HELD for Han:
- dwarvesf/dwarves-kit **#80** (SPEC-087 + ADR-0027, the orchestrator design)
- dwarvesf/dwarves-kit **#81** (`lib/orchestrate.sh` phase 1, stacked on #80)
SG-01..04 cannot execute until #80 + #81 are merged. Until then the loop is BLOCKED on this
prerequisite; that is the expected state, not a failure.

## Theory of change (where the tokens go)
Forensic (2026-06-28): cache_read ~58.5% of spend, Opus 4.8 = 86.5% of spend, thousands of
>2k-token tool outputs riding in context. The structural levers, ranked:
- Biggest $: per-sub-goal model/effort routing (SG-03) + cheap-planner/expensive-executor
  split (SG-05). Opus only does the hard work; discovery + light sub-goals go cheaper.
- Structural growth: the orchestrator (token-hygiene #81) + two-tier handoff (SG-02) +
  distilled returns (SG-04) keep each sub-goal a lean, near-fresh unit.
- Medium: enforce output-offload + deterministic verify (SG-06).
- Small (forensic: minor): static-floor trim + MCP prune (SG-08).
- Observability so we trust it: run-modes + step/stream (SG-01).
- Proof: the measurement (SG-09).

## Sub-goals
- [x] SG-01 orchestrator run-modes: --step pause + live stream (observability + intervention) (kit) , gate , PR #86 (MERGED ba1f901) , depends #81
- [x] SG-02 two-tier feed-forward handoff (hot HANDOFF + warm DECISIONS: dead-ends + next-action + read-pointers) (kit) , gate , PR #83 (MERGED fa0e632) , depends #81
- [x] SG-03 per-sub-goal model/effort routing (orchestrator reads model:/effort: -> claude -p --model) (kit) , gate , PR #82 (MERGED 2f2280c) , depends #81
- [x] SG-04 distilled subagent returns / Mechanism C (return-contract in agents/*.md) (kit) , gate , PR #84 (MERGED 338f7d5) , depends #81
- [x] SG-05 cheap-planner / expensive-executor split + codebase-index reuse (experiment) (ops-toolkit experiments/) , gate-stacked , PR #600 (MERGED 881789b8; verdict DROP , split never won, +25-90% tokens, ~405k fixed floor dominates) , SG-09 now branches off main (SG-05 merged)
- [x] SG-06 enforce output-offload (>2k-tok) + deterministic-verify default (kit) , gate , PR #85 (MERGED f09f4fd)
- [x] SG-07 static-floor trim + MCP prune (measure-then-trim, selective) (dotfiles) , gate-stacked , PR #163 (OPEN, held for end-review; trimmed LaunchAgent BTM rule to an ops-toolkit pointer, -211B rendered floor; MCP allowlist gate enableAllProjectMcpServers:false already in place, global-server scoping PROPOSED to Han not bulldozed) , standalone (dotfiles repo)
- [x] SG-08 teach plan-for-mega-goal to emit model:/effort:/handoff fields (skill) , gate , PR #162 (MERGED 8a6a46a) , depends SG-02+SG-03
- [x] SG-09 eval harness: prove the win by ablation (tokens + quality vs a pre-registered threshold) (ops-toolkit) , gate-stacked , PR #601 (OPEN, held for end-review; 5-arm ladder + merge-result.py + verdict.py over the SG-12 bench; validated on a real Haiku proof: full stack = 161% baseline tokens + worse turns -> +handoff DROPPED, consistent w/ SG-05 fixed-floor drop; full Opus matrix gated; honest benchmark-limitation noted) , depends SG-12 , off main (SG-05 merged), LAST
- [x] SG-10 orchestrator board-view / kanban-sync mode (--board=roadmap|kanban|both; per-mega-goal BOARD via backlog.sh; event-sourced status; ROADMAP canonical) (kit) , gate , PR #87 (MERGED 5372cd3) , depends #81
- [x] SG-11 loop robustness: stalled-watchdog + PID-liveness + tool-baked guardrails (borrowed from pi-swarm) (kit) , gate , PR #88 (MERGED 581a6bf2; ubuntu CI fix: GNU-first _mtime) , depends #81
- [x] SG-12 benchmark fixture: resettable task suite + deterministic checks + a mini-mega-goal (the measurement foundation; do EARLY, no #80/#81 dep) (ops-toolkit experiments/) , gate , PR #595 (MERGED)

## Assumptions (from the 2026-06-29 design session)
- Orchestrator coordinates sub-goal loops; it does NOT replace the in-session /goal loop (they
  coexist). The loop driver is non-LLM (DEC-004); a gate sub-goal halts it.
- pi-swarm harvest (2026-06-29): SG-01/02/04/08/10 fold in borrowed mechanisms + wording, SG-11
  is net-new (robustness). Full analysis + borrow plan: `research/2026-06-29-pi-swarm-comparison.md`.
  We borrow pi-swarm's PRIMITIVES (event-sourcing, liveness, guardrails, wording, observability),
  NOT its topology (their coordinator is an LLM = the marathon we avoid).
- Board-sync (SG-10): goal-files/ROADMAP stay canonical; the kanban board is a derived view-sync
  only (Han, "your call" 2026-06-29). The mega-goal renders its OWN board (per-mega-goal BOARD.md
  via backlog.sh), never injecting sub-goal rows into the repo-wide BACKLOG cockpit.
- Most sub-goals live in dwarves-kit (shared repo) = `gate`: the loop opens the kit stack and
  STOPS for team review; it never merges a kit PR. All current sub-goals are `gate` (SG-09 + SG-12
  are `gate` too: the proof methodology + the benchmark design must be human-blessed before any
  number is trusted, the anti-cherry-pick guard).
- Proof methodology (SG-09, 2026-06-29): the win is proven by a token+quality ABLATION over the
  SG-12 fixed benchmark against a PRE-REGISTERED threshold (full stack <=70% baseline tokens at
  pass-parity, turns-to-green not worse; each lever kept only if its isolated delta is a positive
  win at quality parity, else dropped). A naive before/after is rejected (confounded). SG-12 is the
  foundation and has no #80/#81 dep, so it is the natural EARLY sub-goal to establish baseline.
- Stacking: `gh` stacked PRs. Merge: auto-bottom-up + gated-final (effectively open-only for
  the kit `gate` sub-goals).
- SG-05 is experiment-first (experiments/), per Han.
- SG-08 updates the composer skill itself (resolve its repo at execution: dotfiles if
  chezmoi-managed, else the skill's source).

## Stacking plan for the remaining sub-goals (Han 2026-06-29: "adjust the rest so they stack, I review at the end")
The loop NO LONGER stops per-PR for the remaining gate sub-goals. They build as open PRs (git-
stacked within a repo where possible) and Han reviews the whole set at the END of the wave. Merge
policy on these is `gate-stacked`: open + keep going, never merge, one human review pass at close.
Cross-repo PRs cannot git-stack, so "stack" applies within a repo:
- dwarves-kit (orchestrator): #86 + #87 MERGED, #88 (SG-11) OPEN. Reviewed at close with the rest.
- ops-toolkit chain: SG-05 (experiments/planner-split) off `main` -> SG-09 (eval) stacks on SG-05's
  branch (SG-09 is LAST, measures the levers incl. SG-05). One stacked pair, reviewed top-down.
- dotfiles: SG-07 (static-floor trim) standalone off `main` (can't git-stack with ops-toolkit);
  held open for the same end-review.
Build order: SG-05 -> SG-07 -> SG-09 (SG-09 must be last; its ablation needs the levers landed +
SG-05's branch as its base). The end-review (the "Before close" block) covers ALL open PRs at once.

## Before close
Run `/kit:review-team` (+ a focused lens) across the merged set, then append the LAB_LOG arc
entry on the last sub-goal's branch (ops-toolkit SPEC-005), then mark complete.
