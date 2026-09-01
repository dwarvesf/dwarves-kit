# NOTES: token-optim-v2

## Active blockers
- (none) UNBLOCKED 2026-06-29: dwarves-kit #80 + #81 merged to master. The orchestrator
  foundation is live; SG-01..04 + SG-10/11 are now executable. SG-12 (benchmark) remains the
  natural first sub-goal.

## Proposed additions
(loop appends discovered-but-out-of-scope sub-goals here; human reviews on return)
- design/execute model-split axis (2026-06-29, Han): SG-05 tests the LOCATOR axis (cheap-discovery
  vs free-index). The orthogonal axis is WHERE to put intelligence when the goal's DESIGN is
  ambiguous: smart-DESIGN (Opus plans the approach) + cheap-EXECUTE (Haiku/Sonnet writes the edit
  from a precise plan) , the classic /think->/spec->/execute split. Han's intuition: in this
  goal-loop the ambiguity lives in DESIGN, so intelligence belongs there, not in execute. Worth a
  separate measured experiment (arm: smart-plan-Opus + cheap-execute vs Opus-all). NOT folded into
  SG-05 to keep one-experiment-one-question (clean verdict, no confound).
- ~~token-eval-bench hardening (hard discriminating task + realistic-context fixture)~~ FOLDED
  into PR #595 (2026-06-29, Han: "fold #2 and #6 in too"). Both collapsed into one deliverable: the
  multi-file `fixture-ledger/` package + the hard `ledger-budget` task (a hard task IS the
  realistic-context task). All four original SG-12 instrument-critique items (#1 variance, #3
  anti-gaming, #5 tokens-by-model, plus these two) are now in #595. Nothing token-eval-bench-shaped
  remains parked.
- pi-swarm secondary harvest (2026-06-29), not yet scheduled as sub-goals:
  - Path-reservations + `await using` flock (`reservations.ts`, `LOCK_README.md`) , only matters
    if/when the orchestrator runs sub-goals in PARALLEL (it is sequential today). Park until a
    parallel mode is on the table.
  - Adopt the pi-swarm SKILL.md doc shape (mechanics up top, "Philosophy" + named anti-patterns
    at the bottom) as a broader rewrite of the orchestrator doc + plan-for-mega-goal , a docs
    pass beyond SG-08's field emission.
  - `computeStatus` aging ladder (active->idle->away->stuck, `lib/status.ts`) as a richer agent
    presence model if the board (SG-10) wants liveness tiers beyond stalled.

## Sequencing note (2026-06-29)
- Remaining kit sub-goals SG-01 (run-modes), SG-06 (offload-verify), SG-10 (board-view), SG-11
  (robustness) all re-touch `lib/orchestrate.sh`. They branch off master independently (per the
  ROADMAP), so they will mechanically conflict with the held SG-02/SG-03/SG-04 PRs; cleaner to
  pick them up in a fresh context (and ideally after this batch merges so they build on the
  merged mechanisms). SG-05 (ops-toolkit experiment) + SG-07 (dotfiles static-floor trim, needs
  a measurement pass) are independent and can go next in either order. SG-09 (eval) stays LAST.

## Event log
- 2026-06-29 (cont.): SG-09 (eval ablation, the TERMINAL PROOF) COMPLETE + HELD, ops-toolkit PR
  #601 (gate-stacked, OPEN). WAVE COMPLETE: all 12 sub-goals built; 10 MERGED, 2 HELD (#163 SG-07,
  #601 SG-09) for Han's single end-of-wave review. Built the 5-arm additive ablation ladder on the
  SG-12 bench (arms/{orchestrator,distilled,routing,handoff}.sh layered by source), lib/merge-result.py
  (multi-session token merge, SG-05 method), lib/verdict.py (pre-registered threshold + infinite-cost
  guard + per-lever keep/drop), and the dated research note. RAN a real cheap Haiku proof
  (run-ablation.sh --proof): baseline-haiku mini-mega = 722,734 tok/11 turns; handoff (3 fresh
  sessions, merged) = 1,161,473 tok/20 turns -> full stack 161% of baseline + worse turns =
  threshold FAIL, +handoff DROPPED. HONEST headline: two independent ablations (SG-05 + SG-09) now
  show the orchestrator/split LOSES on small tasks because the ~405k per-session fixed floor
  dominates -> the real lever is trimming that floor (SG-08), not splitting sessions. Documented
  benchmark limitation: this light bench cannot exhibit the orchestrator's long-horizon-coherence
  value (marathon-context-explosion case), so the full Opus matrix is GATED (not auto-run; ~30+
  Opus sessions, tens-hundreds USD) pending Han's methodology blessing. Negative control: caught +
  fixed a real verdict.py bug (dropped the baseline-haiku control, false PASS). All wave PRs
  verified: dwarves-kit #80-88 MERGED, ops-toolkit #595/#600 MERGED + #601 OPEN, dotfiles #162
  MERGED + #163 OPEN. LAB_LOG arc entry added on the #601 branch (rides into the final PR).
  Remaining before "mega-goal complete": /kit:review-team across the set (the automated end-review
  preflight), then Han's single human review of the 2 held PRs. Stopping per gate-awaiting-Han.
- 2026-06-29 (cont.): SG-07 (static-floor trim) COMPLETE + HELD, dotfiles PR #163 (gate-stacked,
  OPEN for end-review). Measured-then-trim, sensitive (global CLAUDE.md). Findings: (1) the live
  floor was stale 48581B at session start but the S-64 dotfiles-watcher applied a pending prior
  compaction mid-session (-> 44921B baseline) AND advanced dotfiles main 66893e2->22ba5cd under me,
  so I had to git reset --keep the worktree onto current main before editing; (2) chezmoi sources
  from a SEPARATE clone ~/.local/share/chezmoi, not ~/workspace/<owner>/dotfiles. The ONE genuine-fat
  cut: macOS LaunchAgent BTM section -> one-line ops-toolkit pointer (rarely-used + already fully
  duplicated in ops-toolkit/CLAUDE.md where plists are authored), -211B rendered floor (44921->44710).
  Everything heavier is security/machine-routing/Tool-selection = always-consulted, left untouched per
  memory feedback_keep_critical_claude_md_inline. MCP: per-project allowlist gate
  (enableAllProjectMcpServers:false) ALREADY set in managed settings.json; the 3 global servers
  (codebase-memory/peekaboo/macos-use) live in non-chezmoi ~/.claude.json runtime state, so scoping
  peekaboo+macos-use on-demand is PROPOSED to Han in the PR body, not bulldozed. CI: shellcheck green,
  test-macos running at handoff. Canary + all always-consulted sections verified post-render. Next +
  LAST = SG-09 (eval ablation, off ops-toolkit main, stacks on SG-05 branch). /clear before it.
- 2026-06-29 (cont.): MERGED both open held PRs on Han's "merge PRs" (gate authority). #600 (SG-05,
  ops-toolkit) squash-merged 881789b8 clean. #88 (SG-11, dwarves-kit) was BLOCKED on a RED ubuntu CI
  check (macos passed): two watchdog tests failed via one root cause , `_mtime() { stat -f %m || stat
  -c %Y }` is BSD-first, and on GNU/Linux `stat -f` SUCCEEDS printing filesystem text starting
  "File:", starving the -c fallback and poisoning `$((now-last))` (set -u: "File: unbound variable").
  Fixed: swap to GNU `stat -c %Y` first (errors cleanly on BSD -> -f fallback) + digit-guard
  (dc3eed7); CI then green both platforms; squash-merged 581a6bf2. Lesson: a portable-stat helper
  must be GNU-first because BSD-first silently succeeds-with-garbage on Linux. SG-09 now branches off
  ops-toolkit main (SG-05 merged, no stack needed). Remaining: SG-07 (dotfiles static-floor trim,
  sensitive global CLAUDE.md, needs Han's judgment + measurement) -> FRESH context; SG-09 (eval) LAST.
- 2026-06-29 (cont.): SG-05 (planner-split) COMPLETE + HELD, ops-toolkit PR #600 (gate-stacked,
  off main; SG-09 stacks on feat/planner-split-eval). REFRAMED first (Han, out-of-loop): "planner"
  = locator; free index = lead candidate, cheap-LLM-planner = falsification; design/execute axis
  logged to Proposed additions. VALIDITY PIVOT flagged to Han ("proceed"): token-eval-bench fixtures
  are 6-file repos whose 1.46M-token cost is context-re-read-over-turns, NOT discovery, so a locator
  can't win there (artifact). Led with a READ-ONLY discovery probe on the REAL 40k-node ops-toolkit
  repo + 1 cheap fixture execute task. RESULT (n=1, Opus executor, 8 cells): the split NEVER won.
  Opus-all cheapest everywhere; index-locator +0..78%, cheap-planner +25..90% and once WRONG. Cause:
  a ~405k fixed per-run floor (system prompt + tool defs + riding context) dominates; offloading
  discovery can't beat the floor + injected pointers add context the executor reads on top. VERDICT:
  DROP , do not wire into /kit:execute; SG-09 must NOT adopt these levers. Reused token-eval-bench
  (SG-12) runner + added 2 arms (index-locator, cheap-planner). Cost bound honored: skipped the
  expensive ledger-budget runs (logged). Proof: experiments/planner-split/{README,docs/proof-of-done,
  runs/} + selfcheck.py (re-verifies verdict from captured data). ~$13 spend. LAB_LOG arc entry
  rides at SG-09 (last sub-goal) per the stacking plan, not here. NEXT: SG-07 (dotfiles static-floor
  trim, standalone) , best in FRESH context. Then SG-09 LAST. Stopping: gate-stacked PR #600 held
  for Han's end-of-wave review + token hygiene (/clear before SG-07).
- 2026-06-29 (cont.): ADJUSTMENT (Han: "adjust the rest sub goals that they can stack and i will
  review at the end"). The loop NO LONGER stops per-PR for the remaining gate sub-goals; they build
  as open PRs (git-stacked within a repo) and Han reviews the whole set at the END. Retagged SG-05/
  SG-07/SG-09 `gate-stacked` on ROADMAP + their goal files (Merge policy + a Stacking line; Done=
  untouched). New "## Stacking plan" section in ROADMAP. Plan: dwarves-kit #88 already open;
  ops-toolkit chain SG-05 (off main) -> SG-09 (stacks on SG-05, LAST); dotfiles SG-07 standalone.
  Build order SG-05 -> SG-07 -> SG-09. End-review covers all open PRs at once. Tracking-doc edits
  left in the working tree (consistent with prior loop practice; not committed to main mid-wave).
  Stopping to /clear before SG-05 (an expensive 1-2 session measured experiment) per the directive's
  own "/clear between sub-goals" + token-hygiene; the stack-build resumes in fresh context.
- 2026-06-29 (cont.): SG-11 (orchestrator loop robustness) COMPLETE + HELD, dwarves-kit PR #88
  (gate). Branched off master after #86/#87 merged (clean, no stack). Added an advisory
  stall-watchdog gated behind WATCHDOG_STALL_SECS (default 0 = synchronous path UNCHANGED): >0
  backgrounds each session, polls liveness (kill -0, no daemon) + session-log mtime, flags
  `stalled` (event + WARN) after N sec no-output while pid alive, NEVER kills. PID-liveness +
  dead-session reconcile (no box advance + blocked event). Guardrail: warns when a sub-goal has no
  goals/ file; labels the box-not-flipped halt [guardrail]. Deviation logged: progress signal is
  the session-log mtime not SG-10's event log (event log too coarse mid-session); stalled event
  still appended to it. Tests +5 (48/48), shellcheck clean, meta 500/500. Gate-ledger spec+build+
  ship recorded. Orchestrator maturation (SG-01/10/11) now COMPLETE: #86+#87 merged, #88 held.
  Remaining: SG-05 (expensive 1-2 session measured experiment), SG-07 (sensitive global-CLAUDE.md
  trim, needs Han's judgment) -> both best in FRESH context; SG-09 (eval) LAST after SG-12 + the
  levers land. Stopping: gate PR #88 awaiting Han + token hygiene (3 sub-goals + a merge this
  context is plenty; the heavy/sensitive remainder wants fresh context, this mega-goal's own subject).
- 2026-06-29 (cont.): #86 (SG-01) + #87 (SG-10) MERGED on Han's "merge PRs" (gate authority,
  overrides open-only). Stacked-merge dance: retargeted #87 base -> master FIRST (delete-branch
  lesson), squash-merged #86 (ba1f901), #87 went CONFLICTING (squash gave SG-01 a new SHA vs the
  branch's original commit), fixed by `git rebase --onto origin/master e4c487f` to replay only the
  SG-10 commit -> clean, 43/43 tests still green on merged master, CI green, squash-merged #87
  (5372cd3). Worktrees + local branches removed. Proceeding to SG-11 (now cleanly off master; both
  levers merged + SG-10's event log available to reuse).
- 2026-06-29 (cont.): SG-10 (orchestrator board-view) COMPLETE + HELD, dwarves-kit PR #87 (gate,
  STACKED on #86; base feat/orchestrator-run-modes). Same context as SG-01 (warm on orchestrate.sh
  = token-efficient). Added `--board=roadmap|kanban|both` (default detects backlog.sh -> both).
  Event-sourced: loop appends to `.orchestrate/events.log`, BOARD.md DERIVED by replay (last event
  wins, never mutated -> crash/concurrent-safe). State = shipped/executing/queued[ready]/parked
  [blocked: needs SG-..]; dep-analysis reads the ROADMAP `depends ...` tail. ROADMAP stays
  canonical; repo BACKLOG never touched. Deviation logged: backlog.sh's STATES is fixed +
  non-overridable, so ready/blocked/stalled ride as status PROSE on standard keywords (no vocab
  fork, one renderer). Tests +9 (43/43), shellcheck clean, meta 500/500. Gate-ledger spec+build+
  ship recorded. The event log IS the progress signal SG-11 reuses. NEXT: SG-11 (loop robustness,
  stacks on #87) is the heaviest orchestrator piece (needs a bg-launch + poll watchdog, restructures
  the synchronous claude call) -> best in FRESH context per token-hygiene. Then SG-05 (expensive
  experiment) / SG-07 (sensitive dotfiles trim); SG-09 LAST. Stopping: 2 gate PRs held awaiting Han
  + token hygiene (fresh context for SG-11).
- 2026-06-29 (cont.): SG-01 (orchestrator run-modes) COMPLETE + HELD, dwarves-kit PR #86 (gate,
  open-only). Prereqs confirmed: #80/#81 merged AND the held batch (#82/#83/#84/#85/#162) all
  merged to master, so orchestrate.sh changes are live and SG-01 branched cleanly off master (no
  stacking needed). Added two opt-in observability flags to lib/orchestrate.sh: `--step` (pause
  after each completed AUTO sub-goal, resume Enter / q stops, exit 0) and `--stream` (stream-json
  tee'd to .orchestrate/<id>.stream.jsonl, live tail + capture). Both off by default => default
  invocation byte-identical; /goal loop + Stop hook untouched. Arg parsing rewritten to a flag
  loop (any order, unknown -> exit 64). Tests +19 (34/34 PASS), shellcheck clean, meta 500/500.
  Kit gate-ledger recorded spec+build+ship (normal lane). Design choice logged: pause is gated on
  the NEXT sub-goal being auto (no redundant pause before a gate-stop). Stopping per
  gate-sub-goal-awaiting-Han + token hygiene. Next clean-to-do: SG-10/11 (orchestrator, best AFTER
  #86 merges to avoid orchestrate.sh conflicts), SG-05 (ops-toolkit experiment), SG-07 (dotfiles
  static-floor trim); SG-09 LAST.
- 2026-06-29 (cont.): ALL 5 HELD PRs MERGED on Han's "merge PRs" instruction (he is the gate
  authority; overrides the open-only default). Order: #162 dotfiles (8a6a46a) + #84 (338f7d5) +
  #82 (2f2280c) clean; #83 conflicted with #82 on orchestrate.sh + test-orchestrate.sh (both
  rewrote _build_prompt/the run path + each added a "TEST 6") -> merged master into the branch,
  resolved to the COMBINED state (routing flags + stdin temp-file injection together; tests
  renumbered TEST 6 two-tier / 7 routing-dry-run / 8 routing-flags; #82's route mock switched to
  read stdin), 23/23 + meta 500/500, then squash-merged (fa0e632). #85 CI had gone RED on first
  push (meta hook-count parity: a new hook needs settings.json + README + architecture.md + the
  test-hooks count assertion, not just hooks.json) -> fixed, green, merged (f09f4fd). Lesson:
  run test-meta.sh too (not just the feature test) before pushing a hook. Worktrees cleaned. Now
  6 sub-goals done (SG-02/03/04/06/08/12). Remaining: SG-01/10/11 (orchestrate.sh, now build on
  merged master), SG-05 (experiment), SG-07 (static-floor trim), SG-09 LAST. Checkpoint for a
  fresh context (token-hygiene) before the next sub-goal.
- 2026-06-29 (cont.): SG-06 COMPLETE + HELD (dwarves-kit PR #85). Output-offload PostToolUse
  hook (>2k tok -> full payload to ~/.cache/dwarves-kit/offload/ + terse pointer; fast-path,
  match-all) + WORKFLOW.md verify-cost-routing (deterministic -> cheap-model -> Opus) +
  BASH_MAX_OUTPUT_LENGTH doc. test-hooks 432/432 (6 new). Honest limit recorded: PostToolUse
  can't strip the current turn; BASH_MAX_OUTPUT_LENGTH is the real source cap, the hook is the
  non-Bash safety net. Touches hooks/ + WORKFLOW.md only (no orchestrate.sh conflict). 5 PRs now
  held this wave (#82/#83/#84/#85 kit + #162 dotfiles). Remaining clean-to-do-now scope is
  exhausted for this context: SG-01/10/11 re-touch orchestrate.sh (do after the held batch merges
  + fresh context), SG-05 is a 1-2-session measured experiment, SG-07 is a sensitive CLAUDE.md
  static-floor trim, SG-09 is LAST. Stopping per gate-awaiting-Han + token-hygiene.
- 2026-06-29: SG-02/SG-03/SG-04/SG-08 batch COMPLETE + HELD (4 gate PRs). One context, three
  repos. SG-03 model/effort routing (dwarves-kit PR #82), SG-02 two-tier hot/warm handoff +
  stdin temp-file injection (PR #83), SG-04 distilled return contract across all 11 agent defs +
  execute worker prose (PR #84), SG-08 composer (plan-for-mega-goal) emits Model:/Effort: + the
  handoff-completion contract matching SG-02/03 (dotfiles PR #162). Each: own worktree, full
  proof-of-done (kit gate-ledger spec+build+ship recorded for the 3 kit PRs; tests green:
  orchestrate 19/19 on SG-02 and SG-03, meta 500/500 on SG-04; close-the-loop greps on SG-08).
  Discovered + logged: SG-03's parser greps bare `^Model:`/`^Effort:`, so SG-08 emits them
  un-bolded (the existing template frontmatter is bold) , a real cross-sub-goal constraint.
  Stopping per "gate sub-goal awaiting Han" + token-hygiene (/clear between sub-goals); remaining
  sub-goals best picked up fresh (see Sequencing note). Re-launch via POINTER_PROMPT.
- 2026-06-29: SG-12 (token-eval-bench) COMPLETE + HELD, PR #595 (gate, open-only). First
  sub-goal executed. Built the resettable benchmark fixture (stdlib, 4 deterministic-check tasks
  incl. the mini-mega-goal cross-sub-goal-reset test, pluggable run-task.sh runner). One real
  recorded arm-run captured (doc-usage/baseline-haiku: pass, 323k tok, $0.13). Ship-gate passed
  via co-located docs/proof-of-done.md (negative+positive controls). #80/#81 confirmed MERGED, so
  SG-01..04 + SG-10/11 are also unblocked for the next session. Loop stops here per the
  gate-sub-goal-awaiting-Han stop condition; clear + re-paste pointer for the next sub-goal.
- 2026-06-29: dwarves-kit #80 (SPEC-087 + ADR-0027, design) and #81 (lib/orchestrate.sh impl)
  MERGED to master after review (both 7/10, review fixes applied: posture, prompt-structure,
  ADR carve-out, policy parser, goal-file injection). The whole wave is unblocked. Ready to
  launch via POINTER_PROMPT (SG-12 first).
- 2026-06-29: mega-goal scaffolded from the 2026-06-29 design session (orchestrator maturation +
  token-optimization levers). 9 sub-goals; most in dwarves-kit (gate). Hard dep on #80/#81.
  Execution deferred to a fresh `/goal` session after #80/#81 merge, per token-hygiene principle.
- 2026-06-29 (cont.): SG-10 added (board-sync). Then deep-read of `monotykamary/pi-messenger-swarm`
  (research/2026-06-29-pi-swarm-comparison.md): folded borrowed mechanisms+wording into
  SG-01/02/04/08/10 and added SG-11 (loop-robustness). Now 11 sub-goals. Secondary borrow-ideas
  parked in Proposed additions above.
- 2026-06-29 (cont.): proof methodology hardened. Upgraded SG-09 from a naive before/after to a
  token+quality ABLATION vs a pre-registered threshold; added SG-12 (resettable benchmark fixture
  + mini-mega-goal) as the foundation, to run EARLY (no #80/#81 dep). SG-09 retagged gate (the
  methodology must be human-blessed). Now 12 sub-goals; the loop is now all-gate (open + stop).
