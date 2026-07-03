# 0032. Mega-goal execution hygiene (delegation, model routing, ledgers, multiplexer)

Date: 2026-07-03
Status: Accepted
Relates-to: ADR-0017 (mega-decomposition lane), ADR-0027 (context hygiene), SPEC-087 (inter-sub-goal context hygiene), ADR-0030 (dag-wavefront scheduling), `lib/orchestrate.sh`, `lib/route-suggest.sh`, ops-toolkit `plan-for-mega-goal` skill + `research/2026-07-03-megagoal-execution-hygiene.md` (the rationale) + the kit-face token ledger + understanding-gate debt ledger

## Context

A 9-sub-goal mega-goal run hit 873k tokens / 87% context in one session. Root cause (ops-toolkit
research 2026-07-03): the run went through the IN-SESSION `/goal` loop, which accumulates every
sub-goal's spec/execute/diff into one context. `orchestrate.sh` was built (SPEC-087/ADR-0027) as the
context-hygienic path , one fresh `claude -p` per sub-goal, the bash driver holding no LLM context ,
but the mega-goal POINTER_PROMPTs all instruct `/goal` + paste, so the hygienic path was mis-instructed.
This ADR records the execution model the kit commits to so the divergence closes.

## Decision

### 1. Two run modes; `/goal` stays the official outer loop

- **INLINE** , the `/goal` loop executes each sub-goal in its own context. Simple; only for small runs
  (<= 4 sub-goals).
- **DELEGATE (default > 4)** , the loop is a THIN CONDUCTOR: for each sub-goal it makes ONE call to a
  fresh headless `claude -p` that runs the full lifecycle in ITS OWN context and returns ONLY a terse
  result (box flipped, PR #, proof). The conductor absorbs one line per sub-goal, holds only roadmap +
  results. `orchestrate.sh run <dir>` is the BASH-DRIVEN form (enforces delegation deterministically);
  the /goal-conductor is the MODEL-DRIVEN form (relies on a forceful "delegate, do not inline" clause).
  `/goal` remains the OFFICIAL outer loop either way , delegate changes what the loop DOES, not the runner.
- **Hard rule:** delegate uses plain `claude -p`, NEVER `--stream`/`--verbose` piped to the conductor
  (that dumps the child transcript into the parent context , the exact accumulation trap).

### 2. Per-sub-goal model routing (planning -> opus)

Route by the sub-goal's DOMINANT work-type at decompose time (`Model:` field -> orchestrate `--model`).
Per-SUB-GOAL, not per-phase (a session cannot switch model mid-run; route by what dominates):
- **opus** , planning/thinking/design dominates (schema/architecture design, spec-heavy, hard tradeoffs).
- **sonnet** , execution dominates.
- **haiku** , trivial.
`route-suggest.sh`'s "Opus-spend heuristic" already gestures at this; the rule makes planning-dominant
sub-goals default opus rather than the blanket sonnet.

### 3. Delegated sessions emit the ledgers (with one reconciliation)

- **Gate/proof/run ledgers: preserved by construction** , each delegated session records under its own
  rid (the per-sub-goal rids are the evidence).
- **Token ledger (kit-face SG-03): stream-to-FILE.** Token capture needs `--stream` (usage in the
  stream-json), but delegate forbids `--stream` TO THE CONDUCTOR. Reconcile: stream the child to a FILE
  (`claude -p --stream > child.jsonl`), extract usage from the file, the conductor reads only the
  box-flip. Both hold.
- **Debt ledger (understanding-gate): split** , the worker writes the significance/worthiness marker;
  the ★-tap nudge fires at the conductor (where the human is). Consistent with SG-02/SG-04.

### 4. Multiplexer visibility (opt-in)

For WATCHING and INTERVENING in parallel sessions (wavefront's waves are headless today), orchestrate.sh
MAY spawn each wave session into a tmux/cmux pane (`tmux new-window` / `capture-pane` / `send-keys`).
Pure orchestration does NOT need this (Bash + `claude -p` spawns/controls/receives headlessly); the
multiplexer adds visibility + intervention only. Minimum infra (tmux already installed); opt-in, off by
default.

### 5. Gaps this ADR obliges the kit to close

- No mega-level TIER-4 close in orchestrate.sh today (integration-verifier + review-team + advisor after
  all sub-goals) , currently pushed to the operator. Make it a first-class close step (or a final sub-goal).
- Token-capture stream-to-file (item 3).
- Multiplexer panes (item 4).
- Model-routing enforcement in the delegate call.

## Consequences

- Big mega-goal runs stop hitting the context ceiling (delegate bounds each session to one sub-goal +
  discovery); the human keeps the official `/goal` loop and course-correction.
- Cost shifts from unbounded cache-read accumulation (inline) to a fixed per-sub-goal DISCOVERY cost
  (delegate) , minimized by the HANDOFF.md/DECISIONS.md pointer discipline (handoff is the discovery
  lever).
- More opus spend on planning sub-goals (deliberate , that is where reasoning pays); cheaper execution.
- The ledgers keep working under delegation (the observability line , debt/token/telemetry , survives).

## Alternatives considered

- **Switch all pointers to `orchestrate.sh run`, drop `/goal`.** Rejected by the operator: `/goal` is
  official + interactive; keep it as the outer loop and inject delegation underneath.
- **Keep inline, lean on `/compact`.** Rejected: compaction is lossy and treats the symptom; the token-
  optim work already optimized the accumulating path when the un-accumulating path existed.
- **Build a new terminal-control daemon for multi-session visibility.** Rejected (minimum-infra): tmux/
  cmux already provide the control plane.

## Out of scope

- A DAG/scheduler beyond ADR-0030 wavefront.
- Replacing `/goal` (it stays the official activator; ADR-0017 activator-agnostic stands).
- The weekend-batch / understanding-gate mechanics (their own ADR-0031 + mega-goal).

## Addendum (2026-07-03, SPEC-120): viewer push widens section 4's surface

Section 4 authorized tmux-only mechanics (`new-window` / `capture-pane` / `send-keys`), opt-in and
off by default. SPEC-120 (operator decision 2026-07-03) adds the PUSH half on top: when a wave
spawns panes under `MULTIPLEXER=1`, `orchestrate.sh` opens ONE viewer tab/surface in the
operator's own terminal app (cmux workspace, `kitty @ launch`, `wezterm cli spawn`,
`open -na Ghostty`, or `osascript` against iTerm/Terminal) already attached to the wave's tmux
session , i.e. the authorized surface grows from in-tmux-server control to DEFAULT-ON
(`PANE_VIEWER=auto`) cross-app viewer automation. Bounds that keep the section-4 spirit: it fires
only when the multiplexer is already on AND a viewer is detected on a real TTY (headless stays
byte-identical, pull-only); `PANE_VIEWER=none` restores section 4's exact behavior; the exec is
argv-direct + charset-gated + allowlist-validated (the #143 pattern), fire-and-forget, and can
never fail a wave. Full design + security pins: `docs/specs/SPEC-120-pane-viewer-push.md`.
