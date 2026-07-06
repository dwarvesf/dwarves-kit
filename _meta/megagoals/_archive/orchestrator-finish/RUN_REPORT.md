# Run report , orchestrator-finish

**Run:** 2026-07-06 · repo dwarves-kit · mode **subagent-delegate** (in-harness `Agent` workers via the /goal conductor; no `claude -p`, so no auth-kill class) · **6/6 built** · #204 #205 #206 #207 #208 merged bottom-up · **#209 HELD** (gated-final, awaits operator click) · 1 CI re-review (02, macOS bash-3.2) + 1 TIER-4 dissent-fix (06, `_route` allowlist).
**Totals:** recorded worker time **~155m** build/fix across 6 sub-goals + **~40m** TIER-4 (3 fresh verifiers, mostly parallel) · subagent tokens **~2.28M** (workers ~1.85M + TIER-4 ~0.43M) · all sonnet.
**Instrumentation:** every sub-goal recorded its gates to a run ledger under its own rid (`orchfin-0N-*`); this report is derivable from those ledgers + the PR/merge log.

## Timeline (1 col ≈ 4 min · `▒` sonnet worker · `▓` TIER-4 verifier · `·` conductor/CI wait)

```
        wave1        03           04       05        06                TIER-4      06-fix
          |          |            |        |         |                   |           |
W1 01 ▒▒▒                                                                            9m  #204 merged
   02 ▒▒▒     (macOS CI red → resume) ▒▒▒▒▒                              12+18m #205 merged
S  03      ▒▒▒▒▒▒▒▒                                                      31m #206 merged
   04                ▒▒▒                                                 11m #207 merged
   05                        ▒▒▒▒                                        15m #208 merged
   06                                ▒▒▒▒▒▒▒▒▒▒                          39m  → #209 (held)
T4 close                                        ▓▓ A  ▓▓ B  ▓▓▓▓▓▓▓ C    ~40m (A+B fast, C slow)
Fx 06                                                          (dissent) ▒▒▒▒▒  21m #209 updated
   ───────────────────────────────────────────────────────────────────
   wave 1 ran 01‖02 in parallel; 03→04→05→06 SERIALIZE by design
   (all edit lib/queue/orchestrate.sh; the stack is merge-hygiene, not a dep).
   So the only "unparallelizable" span is the orchestrate.sh chain , correct, not waste.
```

## Sub-goals

| SG | slug | model | dur | PR | outcome |
|---|---|---|---|---|---|
| 01 | gate-vocab-align | sonnet | 9m | #204 merged `11e04b1` | `build`/`design-critique`/`design-record` now recorded by their phase-owner commands; recording-gap test 17/17; NC = real revert→RED→restore |
| 02 | tier4-split | sonnet | 12m +18m fix | #205 merged `4ff2f88` | TIER-4 close = 3 fresh verifiers + fail-closed aggregate; **re-review fixed a macOS bash-3.2 fatal** (`RETURN`-trap on a `local` array under `set -u`) |
| 03 | wave-tokens | sonnet | 31m | #206 merged `9380c8a` | shared `_record_tokens` on the wave reap path; NC = pre-fix code writes ZERO wave token lines |
| 04 | watchdog-tokens | sonnet | 11m | #207 merged `f906fd4` | `WATCHDOG_STALL_SECS` branch mirrors the happy-path capture to `$slog`; stall no longer an accounting black hole |
| 05 | conductor-rid-check | sonnet | 15m | #208 merged `78037b5` | wave spawn loop now emits `_emit_start` (START/rid); serial missing-rid stays advisory (pinned); closes 03's transient TOKENS-without-START window |
| 06 | orchestrate-sweep | sonnet | 39m +21m fix | #209 **HELD** `7e7d782` | ID-095 stream age/rotation cap + secret redaction; ID-096 `_route` allowlist pre-flight; ID-098 happy-path `tmux kill-window`; **TIER-4 dissent fixed** (exact-token allowlist) |
| T4 | convergence close | 3×sonnet | ~40m | , | 3 fresh verifiers over the whole-mega diff `20a9e12..HEAD`; **caught 1 in-scope defect** (06 `_route` substring bypass) + 1 out-of-scope pre-existing gap (routed to follow-ups) |

## TIER-4 convergence gate (this mega's own split, 3 fresh verifiers, fail-closed)

| verifier | lens | verdict | finding |
|---|---|---|---|
| A | token-accounting completeness | DISSENT (out-of-scope) | 4th token-black-hole: a session that spends tokens then exits nonzero / doesn't self-claim skips `_record_tokens` on serial+wave+watchdog. **Pre-existing in baseline `20a9e12`; no sub-goal scoped the failure-exit path.** → NOTES follow-up (matches the pre-logged advisor-P6 "4th/5th silent-exit path" item). No double-count; helper not forked; format consistent. |
| B | gate + START/rid coverage | **PASS** | 01: all 12 `required full` names have a recorder (17/17). 05: both dispatch sites emit START, no 3rd path. Cross-seam: the 03-before-05 TOKENS-without-START window is **confirmed closed** on the assembled tree. Advisory pin intact. |
| C | close-path + sweep integrity | DISSENT (in-scope) → **fixed** | `_route` allowlist used a substring `case`; `Model: opus sonnet` wrongly ACCEPTED (substring of `" opus sonnet haiku "`), defeating ID-096. Fix: exact-token enumeration (same pattern as the file's PANE_VIEWER P2 fix). Re-verified: 12/12, multi-word-reject NC green. 02 aggregator fail-closed (25/25); redaction/prune/tmux clean; wavefront failures pre-existing (reproduced on base). |

**Aggregate: PASS** , the one in-scope dissent (C) was fixed and independently re-verified; the one out-of-scope dissent (A) is pre-existing and routed to the successor mega. The gate earned its keep: C's substring bypass passed every per-sub-goal review and only a fresh whole-tree lens caught it.

## Gate coverage (`●` recorded · `○` skipped-with-reason · `·` n/a for lane)

```
                grill  build/exec  test/verify  review  docs  ship
01 gate-vocab     ○        ●            ·          ●       ●     ●
02 tier4-split    ○        ●            ●          ●       ·     ●
03 wave-tokens    ·        ●            ●          ·       ●     ●
04 watchdog       ·        ●            ●          ●       ●     ●
05 rid-check      ·        ●            ●          ·       ●     ·
06 sweep          ○        ●            ●(test-pl) ●       ·     ·
```
(Gate-name variance , build/execute/implement , is the per-worker lane vocab; sub-goal 01
was the fix that made these names recordable in the first place. 06's ship row is `·`
because #209 is held , its ship gate fires on the operator's merge.)

## Callable stack

```
/goal conductor (subagent-delegate, in-harness Agent workers, manual worktrees off origin/master)
├─ WAVE 1 (parallel)
│  ├─ 01 gate-vocab   sonnet  9m         → #204 merged 11e04b1
│  └─ 02 tier4-split  sonnet  12m +18m   → #205 merged 4ff2f88  (macOS CI resume)
├─ 03 wave-tokens     sonnet  31m        → #206 merged 9380c8a
├─ 04 watchdog        sonnet  11m        → #207 merged f906fd4
├─ 05 rid-check       sonnet  15m        → #208 merged 78037b5
├─ 06 sweep           sonnet  39m        → #209 (held)
└─ TIER-4 close (3 fresh verifiers, parallel)
   ├─ A token-acct    sonnet  DISSENT (out-of-scope → follow-up)
   ├─ B gate/rid      sonnet  PASS
   └─ C close/sweep   sonnet  DISSENT (in-scope) → 06 fix +21m → #209 updated 7e7d782 → re-verified PASS
```

## What the numbers say (faster next time)

- **Zero auth-kill recoveries** this run (subagent-delegate, in-harness) vs the predecessor's 2 (`claude -p` delegate). The checkpoint discipline held but was never needed , the mode choice removed the class.
- **2 gate catches** on real defects that per-sub-goal review missed: macOS bash-3.2 (CI, 02) and the substring allowlist bypass (TIER-4, 06). Both are the SAME shape , a portability/correctness trap invisible to a single-context review , which is exactly why CI-on-the-open-PR and a fresh whole-tree TIER-4 are non-negotiable.
- **The bash-3.2 lesson compounded:** learned on 02's denial, injected into every later worker prompt; 03/04/05/06 all tested under `/bin/bash` up front and none re-tripped it. One denial, then immunity.
- **Serialization was honest, not wasteful:** only wave 1 was parallelizable; 03→06 share one file and had to serialize. No dep-independent work ran serial (the predecessor's -64% finding does not recur here).

## Follow-ups (see NOTES ## Proposed additions)

1. **Failure-exit token-black-hole** (TIER-4 verifier A, concrete file:line) , route `_record_tokens` through the nonzero-exit / box-not-flipped branches on serial+wave+watchdog. The concrete instance of the pre-logged advisor-P6 "4th/5th silent-exit path" audit. → successor `kit-closeout` mega, with a token/START/cleanup-invariant lint over every dispatch/exit branch (self-enforcing fence via ship-gate).
2. **Cosmetic** , `tests/test-wave-token-capture.sh` L141-142 harmless arithmetic-syntax stderr (still PASS/RC=0); fix opportunistically.
