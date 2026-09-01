# Run report , orchestrate-hardening

**Run:** 2026-07-03 18:02-21:01 (+07), run 2 (run 1 = gate-zero STOP 17:54, ADR-0032 Proposed) · repo dwarves-kit · mode delegate (`claude -p` workers via /goal conductor) · 5/5 built; #139-#142 merged, #144 HELD (gated-final), +#143 security fix
**Totals:** wall 2h59m · recorded worker time 92m (+ SG-04 unrecorded, est ~30m) · **parallel potential ~1h05m (-64%)** , 01-04 were dep-independent yet ran serial.
**Generated post-hoc** from the run ledgers (the conductor predated the visible-close contract; this file proves the derivability claim).

## Timeline (1 col = 4 min · `█` opus · `▒` sonnet · `░` no ledger, est)

```
            18:02    18:30      19:00          20:00          21:00
               ·       |          |              |              |
W1  01 routing   ▒▒▒                                              12m #139
    02 tokens        ███████                                      27m #140 †
    03 t4close                  ██████████                        39m #141 †
    04 panes                               ░░░░░░░?               ~30m #142 ‡
T4  close                                          ▓▓▓            12m  → #143 fix
F   05 docs                                            ▒▒▒▒       14m #144 HELD
    ──────────────────────────────────────────────────────────
    same DAG,    ██████████ W1‖ 39m ▓▓▓ T4 ▒▒▒▒ 05   done ~19:07
    parallel
```

† delegate KILL pattern: 02's worker finished + committed, then auth expired pre-push
(recovered 8b1db9b -> #140); 03's worker was killed post-commit (recovered). Boxes +
commits survived , the grounded-completion contract held.
‡ SG-04's worker recorded NO run ledger under an `oh-04-*` rid , killed pre-ledger; the
conductor recovered its UNCOMMITTED worktree files by hand and opened the PR itself.
Timing estimated from merge order; gate coverage unknown. Follow-up filed in NOTES
(ID-099) + the checkpoint discipline codified in `_meta/megagoals/OPERATE.md`.

## Sub-goals

| SG | slug | model | dur | PR | outcome |
|---|---|---|---|---|---|
| 01 | model-routing-enforce | sonnet | 12m | #139 merged 44d2b8f | `Model:` provably reaches `--model` (6/6 tests) |
| 02 | token-capture-delegate | opus | 27m | #140 merged a5393de | `CAPTURE_TOKENS` stream-to-file, 9/9 + regression |
| 03 | tier4-mega-close | opus | 39m | #141 merged 346fe1e | `_tier4_close` + no-orphan check, 17/17 |
| 04 | multiplexer-panes | sonnet | ~30m | #142 merged d3e63ef | opt-in tmux panes (no rid ledger , gap) |
| T4 | close (this run's own) | , | 12m | #143 merged | CLEAN + found a CRITICAL: command injection in `_pane_spawn` (joined-string -> `$SHELL -c` re-parse of unsanitized `Model:`); fixed exec-direct argv after `--` |
| 05 | docs-wiring | sonnet | 14m | #144 OPEN, HELD | WORKFLOW/AGENTS delegate model; 25/25 no-orphan (every documented capability has a live call site) |

## Gate coverage (`●` ran · `○` skipped-with-reason · `·` absent · `?` no ledger)

```
              sp  sv  gr  th  de  dc  va  tp  bu  re  do  rf  sh
01 routing     ●   ●   ○   ○   ○   ○   ·   ○   ●   ●   ●   ○   ●
02 tokens      ●   ·   ○   ●   ●   ●   ●   ●   ●   ●   ●   ●   ●
03 t4close     ●   ·   ○   ●   ●   ●   ●   ●   ●   ●   ●   ·   ·
04 panes       ?   ?   ?   ?   ?   ?   ?   ?   ?   ?   ?   ?   ?
05 docs        ●   ●   ·   ·   ·   ·   ·   ·   ●   ·   ·   ·   ·

deep lane (th/de/dc) ran on 02 + 03 , the two opus design sub-goals, as routed.
03's ship/reflect happened at the conductor after the worker kill (recovery path).
```

## Callable stack

```
/goal conductor (run 2 · delegate)
├─ claude -p oh-01-model-routing   sonnet   12m  → #139
├─ claude -p oh-02-token-capture   OPUS     27m  → #140  (auth-kill, recovered)
├─ claude -p oh-03-tier4-close     OPUS     39m  → #141  (killed, recovered)
├─ claude -p oh-04-panes           sonnet  ~30m  → #142  (no rid ledger)
├─ TIER-4 lenses as fresh subagents          12m  → #143  (dodged the engine's
│    (integration · security · advisor)             single-prompt accumulation)
└─ claude -p oh-05-docs            sonnet   14m  → #144 HELD
```

## Tokens

Not captured: `CAPTURE_TOKENS` is what SG-02 SHIPPED mid-run (off by default; the
conductor never enabled it). The NEXT mega-goal run is the first that can carry real
per-worker token numbers , enable capture, or use subagent-delegate's native
`subagent_tokens`.

## For Han

- **#144 (docs) is the held gated-final , your click.**
- Everything else merged, TIER-4 CLEAN, and the close paid for itself: one CRITICAL
  injection found + fixed (#143) before it ever shipped in a release.
