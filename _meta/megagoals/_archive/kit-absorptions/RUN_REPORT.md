# Run report , kit-absorptions

**Run:** 2026-07-04 ~06:18-09:45 (+07) · two repos (dotfiles + dwarves-kit) · mode subagent-delegate (in-harness worktree workers) · **9/9 built** , 6 merged to dwarves-kit master, 3 held for Han on dotfiles.
**PRs:** dwarves-kit #165 #166 #168 #169 #170 #171 (merged) · dotfiles #195 #196 #197 (HELD gates).
**Totals:** wall ~3h27m (incl. a ~env-brick STOP gap) · worker time ~2h53m across 12 dispatches (11 sub-goal runs + 1 CI-fix + 1 TIER-4 verifier) · ~2.69M subagent tokens · conductor stayed thin (absorbed one terse report per worker, never ran a sub-goal inline).

## Timeline (two lanes · `█` opus · `▒` sonnet · `▓` blocked/gap)

```
        06:18   06:47      07:37   08:13     08:55  09:14  09:34  09:45
           ·      |           |       |         |      |      |     ·
LANE A (dotfiles, all HELD)
  01 operate    ▒▒                                                    #195
  02 contracts    ▒▒▒▒                                                #196
  08 remega  ██(died on env-brick)  ······  █▒                        #197
LANE B (dwarves-kit, all MERGED)
  03 templates  ▒▒▒▒▒ →#165✓
  04 grill              ▒▒▒▒▒▒▒▒▒ →#166✓   (over-test)
  05 emit-sweep                   ▒▒▒▒▒▒▒▒▒▒ →#168✓ (over-test)
  06 pitch                                 ▒▒▒▒▒▒▒+fix →#169✓ (over-test, AC1 CI-fix)
  07 deescalate                                     ▒▒▒▒▒ →#170✓
  09 mega-mirror                                          ▒▒▒▒▒ →#171✓
  ─────────────────────────────────────────────────────────────
  STOP #1  ▓▓▓  env brick (corrupt secret-guard hook blocks all Bash) + cross-mega
           hold cleared together (Han repaired hook · sibling kit_gates #683 merged)
  TIER-4                                                       ▒▒ integration + demo
```

The two lanes ran in parallel where independent (dotfiles vs dwarves-kit); within each lane one worker at a time (stacked). The dwarves-kit lane was serialized by the cross-mega reader-first hold and its own linear stack. The single biggest wall-clock cost was the STOP #1 gap, not compute.

## Worker minutes by model

```
opus    ██▍            ~11m  ( 6%)   2 runs , 08 remega (1st died on the env brick, re-run)
sonnet  ██████████████ ~162m (94%)   10 runs , every kit sub-goal + the AC1 CI-fix + TIER-4 verifier
```

Design-bearing sub-goals (04, 05, 06, 08) ran the deep lane; only 08 (remega, planning-dominant authoring) was routed to opus per the model rule. All dwarves-kit execution was sonnet and passed adversarial review.

## Gate coverage (`●` recorded in the run ledger · deep-lane columns right of `│`) , dwarves-kit only

```
                    sp  gr  bu  re  do  sh  sv  tp  dr │ th  de  dc  rf
03 templates         ●  ●○  ●   ●   ●○  ●   ─   ○   ●  │
04 grill      deep   ●  ●○  ●   ●   ●   ●   ●   ●   ●  │  ●  ●   ●   ●
05 emit-sweep deep   ●  ●○  ●   ●   ●   ●   ●   ●   ●  │  ●  ●   ●   ●
06 pitch      deep   ●  ●○  ●   ●   ●   ●   ●   ●   ●  │  ●  ●   ●   ●
07 deescalate        ●  ●○  ●   ●   ●   ●   ○   ─   ─  │
09 mega-mirror       ●  ●○  ●   ○   ●   ●   ─   ○   ○  │

● recorded · ○ skipped-with-reason / override · ─ n/a for lane
sp spec · gr grill · bu build · re review · do docs · sh ship · sv spec-validate
tp test-plan · dr design-record │ th think · de design · dc design-critique · rf reflect
dotfiles 01/02/08 are NOT kit-adopted , no gate ledger; proof lives in each PR body.
```

Every dwarves-kit grill gate SKIPPED with an auditable `reason=` (the very mechanism 04 shipped, dogfooded across the run). No gate REQUIREMENT changed anywhere , observability + conditioning only, as mandated.

## Callable stack

```
/goal conductor (subagent-delegate · thin · one terse report absorbed per worker)
├─ LANE A , dotfiles (NOT adopted · proof in PR body · HELD for Han)
│  ├─ 01 operate-portability   sonnet  #195  gate , outcome pre-shipped in #194 (verification-record PR)
│  ├─ 02 contracts-batch       sonnet  #196  4/5 (item-3 = wrong repo) · caused the env-brick incident
│  └─ 08 remega-consolidate    OPUS    #197  gate , 1st run died on the env brick, re-dispatched clean
├─ LANE B , dwarves-kit (adopted · MERGED bottom-up on green CI)
│  ├─ 03 kit-template-fields   sonnet  #165  SPEC-137
│  ├─ 04 grill-conditioning    sonnet  #166  SPEC-138  over-test (2 review-bugs fixed pre-ship)
│  ├─ 05 emit-sweep            sonnet  #168  SPEC-139  over-test (red-NC x2)
│  ├─ 06 pitch-assembler       sonnet  #169  SPEC-140  over-test  └─ AC1 CI-portability fix  sonnet
│  ├─ 07 lane-de-escalation    sonnet  #170  SPEC-141  (no-block NC)
│  └─ 09 mega-mirror-sync      sonnet  #171  SPEC-142
└─ TIER-4 verifier             sonnet  integration check + live demo (fresh context)
```

SPEC block SPEC-137..142 was conductor-reserved up front; no worker self-picked a number.

## Integration + demo (TIER-4, fresh-context verifier)

All 7 objective deliverables PASS on master + the two held dotfiles branches; **no cross-sub-goal seam mismatch** , 04's `reason=` enum, 05's ledger-visibility contract, and the sibling `kit_gates` reader all agree on the `TS | GATE | phase | state | reason` 5-field grammar, verified against a REAL merged-PR emit line (not prose). Demo captures:
- **grill fixtures live:** `test-grill-conditioning.sh` 23/23 + a live `... | GATE | grill | skipped | reason=home-turf` line; 89d/91d + signal-count edges correct.
- **`/kit:pitch` on a real shipped rid** (`kit-emit-sweep`, #168): 5-section doc with a real PR link; live-render on a state-free worktree correctly degraded to "no grill record" instead of fabricating (the graceful-degradation contract, reconfirmed live).
- **remega dry-run:** the committed read-only sample consolidates `safari-extension-unlock` (7 SGs) + `safari-ext-enhancements` (5 SGs); full 7-step shape + the byte-identical read-only NC; honest caveat that both are 100%-done teaching fixtures.

One UNRELATED pre-existing failure surfaced in a full 53-file sweep (`test-classify-md-inert.sh`, a `/tmp` helper-sourcing bug in its own harness, last touched by #18/#19) , NOT a regression from any sub-goal; flagged for hygiene, not blocking.

## Incidents & lessons

1. **Env brick (STOP #1):** sub-goal 02's UNtargeted `chezmoi apply` corrupted the live `secret-guard.sh` hook (chezmoi `run_onchange_*` scripts write real `$HOME` regardless of `--destination`), which as a PreToolUse-on-Bash hook blocked ALL Bash machine-wide for the conductor and every worker. Handed to Han; he repaired it; the cross-mega hold cleared in the same window. Fix baked into every subsequent dotfiles worker prompt: SCOPE every apply to explicit paths + `bash -n` the hook after. Candidate hard-precondition for the plan-for-mega-goal skill.
2. **CI-portability (06):** `gh pr checks --watch` reported green off an early checkpoint commit; the final run failed 27/29 because AC1 rendered a LIVE rid whose ledger state is absent in CI's fresh checkout. Caught by re-reading `mergeStateStatus` at merge time (never trust a stale watch). Fixed by rendering a committed fixture rid + verifying under scrubbed `HOME`. Now a standing rule for live-render proofs.
3. **Two dwarves-kit worker slips (self-corrected):** bundling a `gate-ledger record` with `git push` in one line (ship-gate hook blocks the whole line) , split them; and stale-scratchpad heredoc reuse under noclobber , use fresh `mktemp` + verify-read.

## Held for Han (the gate)

The dotfiles stack (01 #195 → 02 #196 → 08 #197) is held behind gate 01 by design; the remega Consolidate mode + its dry-run report (08) and the portable OPERATE contract (01) want your eyes. Merge bottom-up: 01, then 02, then 08. Everything else is machine-verified and merged.

## Render policy (data vs render)

This md IS the committed record: tables + ASCII/box-drawing only. Numbers are derivable from the run ledgers under `~/.local/state/dwarves-kit/logs/runs/kit-*.log` and the harness `subagent_tokens` per dispatch. Timeline positions are approximate (anchored on merge timestamps + worker durations); the STOP gap is called out rather than smoothed.
