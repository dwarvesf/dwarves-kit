# NOTES, orchestrator-finish

## Active blockers

<none yet>

## Proposed additions

- 2026-07-06: successor mega `kit-closeout`, verification absence-checks (ID-020) + hooks-as-fallback layering contract (ID-036) + loop QA-gate (ID-012 P2); all "shipped-but-reopened" full-lane items needing investigation. Scaffold when it starts.
- 2026-07-06: ID-002 (absorb ops-toolkit skills/hooks into the kit), fold under `kit-wiring`, not a fresh mega.
- 2026-07-06: ID-037 status is stale (`validated` but shipped SPEC-096), flip its BACKLOG row to shipped out-of-band.
- 2026-07-06 (advisor P6): a single lint asserting the token/START/cleanup invariants over EVERY dispatch/exit branch of orchestrate.sh , converts the 3 point-fixes (03/04/05) into a permanent regression fence so a new dispatch mode can't silently reintroduce the class. HIGH leverage.
- 2026-07-06 (advisor P6): audit orchestrate.sh for a 4th/5th silent-exit path (abort/Ctrl-C trap, goal-file-missing early return, dup-rid collision) with the same no-token/no-START/no-cleanup shape , audits miss siblings by construction; cheap now while the file is open across 5 branches. MED-HIGH.
- 2026-07-06 (advisor P6): a synthetic "chaos" e2e run as the mega's CLOSING proof , one invocation triggering wave + watchdog-stall + wave-dispatch + TIER-4 dissent together, asserting token totals reconcile and every rid has a ledger row. The composite none of the 6 Rung-2 proofs exercise; closes the gap between "6 fixes proven" and "overnight numbers trustworthy". HIGH.
- 2026-07-06 (advisor P6): after the lint (above) exists, wire it into hooks/ship-gate.sh as a permanent precondition for PRs touching lib/queue/orchestrate.sh (self-enforcing fence). MED, depends on the lint landing.
- 2026-07-06 (advisor P6): consider merging 04 (watchdog-tokens) + 05 (wave-START) into one PR (adjacent, both trivial) to cut stack depth , MED, pure process efficiency (kept separate for now: distinct paths/NCs).

## Event log

2026-07-06 · scaffolded · orchestrator-finish, 6 sub-goals (5 normal + 1 tiny-sweep), from the orphaned orchestrate-hardening spillover (ID-091,093,094,095,096,097,098,099)
2026-07-06 · advisor pre-launch · P5 critique + P6 over-suggest run. P5 verdict: 1 CRITICAL (flat lib paths in POINTER + goal 01 , FIXED, all subdir now) + 2 MAJOR (stack-order 03-before-05 gap , noted-accepted; goal 03 NC not operationalized , FIXED with a pre-fix-shows-zero clause) + 1 MINOR (goal 02 Depends-on fragment , tidied). P6: 5 suggestions → ## Proposed additions. Scaffold now launch-ready.

2026-07-06 · wave 1 dispatched · {01-gate-vocab (sonnet), 02-tier4-split (sonnet)} as bg workers in manual worktrees (.claude/worktrees/orchfin-01,-02) off master. Conductor decision: PR base = master (repo default; goal files say "main"). Cross-repo gotcha sidestepped: manual worktrees + explicit cwd, NOT isolation:worktree (which would cut from ops-toolkit session repo).
2026-07-06 · gate-deny 02 · PR #205 macOS CI red: printf broken-pipe (SIGPIPE) at orchestrate.sh:269,289 in TIER-4 tests ("clean close" + "no-corpus e2e" FAIL), ubuntu green. Resumed worker 02 with triage-first contract to fix at source (guard the writer / avoid early-closing reader), preserve no-corpus skip+hold, re-push same branch. Held bottom-up merge.
2026-07-06 · wave 1 landed · 01 merged 11e04b1, 02 merged 4ff2f88 (bottom-up). 03 dispatched (sonnet) off origin/master. Base-branch lesson: worktrees for 04-06 base off `origin/master` after fetch, NOT local master (local master won't ff while the conductor holds uncommitted ROADMAP/NOTES tracker edits). macOS-bash-3.2 CI lesson forwarded to worker 03 (avoid set -u empty-array + RETURN-trap-on-local, test under /bin/bash).

2026-07-06 · TIER-4 convergence gate (3 fresh verifiers, whole-mega diff 20a9e12..orchfin-06 HEAD) · FAIL-CLOSED, fed back:
- Verifier B: PASS (01 all 12 required names recorded 17/17; 05 both dispatch sites emit START, no 3rd path; 03-before-05 TOKENS-without-START window CONFIRMED CLOSED on assembled tree; advisory pin intact).
- Verifier C: DISSENT (BLOCKING, in-scope) — _route Model allowlist at orchestrate.sh:506 uses substring `case`; `Model: opus sonnet` wrongly ACCEPTED (substring of " opus sonnet haiku ") and dispatched, defeating ID-096. Proven exact-token fix already in same file ~L1760 (PANE_VIEWER security-P2). Resumed worker 06 to apply exact-token match + multi-word-reject test. Final PR #209 held pending fix.
- Verifier A: DISSENT (out-of-scope, non-blocking) — a 4th token-black-hole: a session that spends tokens then exits nonzero OR doesn't flip its box skips _record_tokens on serial (cmd_run ~L1971/1980 return before ~L2018), wave (rc!=0/box!=1 skip ~L1397), watchdog (same). PRE-EXISTING in baseline 20a9e12; no sub-goal scoped the failure-exit path; matches the already-logged P6 "audit for a 4th/5th silent-exit path". No double-count, shared helper not forked, format consistent. → see Proposed additions.

## Proposed additions (append)
- 2026-07-06 (TIER-4 verifier A, concrete): failure-exit token-black-hole. `_record_tokens` is skipped whenever a session spends tokens then exits nonzero or doesn't self-claim (box!=1): serial cmd_run early `return 1` (~L1971, ~L1980) before the record call (~L2018); wave reap rc!=0/box!=1 branches (~L1397 unreached); watchdog-stalled-then-failed inherits it. Pre-existing in baseline. Fix = route _record_tokens through the failure-exit branches too (mirror success path). This is the concrete instance of the earlier P6 "4th/5th silent-exit path" audit item — fold into the successor `kit-closeout` mega with the token/START/cleanup invariant lint.
- 2026-07-06 (TIER-4 verifier B, cosmetic): `tests/test-wave-token-capture.sh` L141-142 emits a harmless bash arithmetic-syntax stderr warning but still reports ALL PASS/RC=0. Cosmetic test bug (sub-goal 03's file); fix opportunistically.
