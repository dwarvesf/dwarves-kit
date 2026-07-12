# RUN REPORT , harness-loop

**Ran:** 2026-07-12 (one day, one operator, ~14h wall)
**Destination:** close the Specify -> Execute -> Observe -> Govern -> Learn loop.
**Outcome:** MET. The Learn leg fires (`learn propose` staged real, cited proposals off the live
ledgers on its first run), the Observe leg is legible (`mega review --html` sign-off dashboard +
weekly scorecard), the surface consolidated to one grammar (ADR-0034), and the front door tells
the loop's story with parity-pinned counts that cannot drift again.

## Telemetry

`RUN_REPORT , harness-loop (10/10 built · 9 merged · #244 final green + held)`

### Worker minutes by model

```
fable  |██████████████      | ~420m (~75%)  2 conductor sessions: #1 built 01 + dispatched
       |                    |               every wave (23 subagents, 15.9M child tokens);
       |                    |               #2 built SG-10's five tasks, then hit its usage limit
opus   |█████               | ~140m (~25%)  operator: stacked-merge reconcile of waves 2-3
       |                    |               (3 seam fixes), SG-10 close-out, this report
worker tiers: not ledgered , the run predates per-dispatch TOKENS emit, so per-worker
model minutes are honest-dash; $ from the conductor status line: session-1 $267 + $439
across its subagents, session-2 $26. Durations are wall-clock and include idle CI-watch.
```

### Gate coverage (● recorded-ran · ○ skipped/override-with-reason · — n/a), from each rid's gate-ledger rows

```
                    gr th de dc sp sv dr tp bu re do sh rf   lane    SPEC
01 taxonomy         ○  ●  —  —  ●  —  ●  ○  ●  ●  ●  ●  —   full    ,     (GATE, Han-approved)
02 outcome-emit     ○  ○  —  —  ●  —  ●  ○  ●  ●  ●  ●  —   normal  193
03 harvest-land     —  —  —  —  —  —  —  —  —  —  —  —  —   tiny    ,     (merge-only; evidence rode PR #226's own record)
04 surface-consol   ○  ○  ○  ○  ●  ●  ●  ●  ●  ●  ●  ●  ○   normal  194
05 retro-cycle      —  —  —  —  ●  —  —  —  ●  ●  —  ●  —   full    195   (thin rid: operator finished the reconcile by hand)
06 staging-drain    ○  ○  ○  ○  ●  ●  ○  ●  ●  ○  ●  —  —   normal  196
07 mega-dashboard   ○  ○  ●  ○  ●  ●  ●  ●  ●  ●  ●  ●  ●   normal  197
08 config-surface   ○  ●  ●  ○  ●  ●  ●  ●  ●  ●  ●  ●  ●   normal  198
09 onboard-wizard   ○  ○  ●  ●  ●  ●  ●  ●  ●  ●  ●  ●  ●   full    199   (GATE, Han-approved)
10 front-door       —  —  —  —  ●  —  —  —  ●  ●  ●  ●  —   normal  ,     (docs; operator-recorded)
```
gr grill · th think · de design · dc design-critique · sp spec · sv spec-validate · dr design-record · tp test-plan · bu build · re review · do docs · sh ship · rf reflect.
SPEC block 193-199 was reserved at scaffold time; no worker self-picked a number. **No gate REQUIREMENT was changed anywhere**; the immutable `Done =` held for all 10.

### Callable stack

```
/goal conductor #1 (tmux dk-queue · Fable high · queue.sh-launched; paste needed a manual C-m , runner defect, twice)
├─ 01 taxonomy      in-conductor worktree   #236  merged 8c09e0d  (GATE: held, Han approved)
├─ WAVE 1  parallel subagents + one merge
│  ├─ 02 outcome-emit        Agent          #237  merged 76fbafe  (auto-merged per policy)
│  ├─ 03 harvest-land        gh merge       #226  merged a6c5a9e  (existing PR reviewed + landed)
│  └─ 07 mega-dashboard      Agent          #238  merged c2eb239
├─ WAVE 2 (stacked on #236 after Han's mid-run switch to stacked PRs)
│  ├─ 04 surface-consol      Agent          #239  merged 04fbdaf  (+ dotfiles companion #213)
│  └─ 08 config-surface      Agent          #240  merged ad81d46
└─ WAVE 3 (stacked)
   ├─ 05 retro-cycle         Agent          #243  merged b2131dc  (first live run staged 3 cited proposals)
   ├─ 06 staging-drain       Agent          #241  merged d688306
   └─ 09 onboard-wizard      Agent          #242  merged 2ba70b6  (GATE: held, Han approved)
operator (Opus) , stacked-merge reconcile of waves 2-3 on the integrated tree:
   3 cross-sub-goal seams caught + fixed (see Incidents), suites re-run per merge
/goal conductor #2 (tmux loop10 · Fable high) , SG-10: five build tasks done, then usage-limit stall
operator (Opus) , SG-10 close-out: RUN_REPORT, proof-of-done, gate rows, held PR #244
```
Per merge: `gh pr checks` + the affected suites re-run on the integrated tree (full local suite where feasible).

## Outcome table

| SG | What shipped | PR | Merge SHA |
|---|---|---|---|
| 01 | ADR-0034 taxonomy: census + 10 locked decisions (GATE, Han-approved) | #236 | 8c09e0d |
| 02 | OUTCOME timing brackets at the skipped gate call sites (+ standing coverage lint) | #237 | 76fbafe |
| 03 | harvest dedup: flock on the staged-append race | #226 | a6c5a9e |
| 04 | surface consolidation: one `bin/<subsystem> <verb>` grammar, `lib/learn/`, skill relocation | #239 | 04fbdaf |
| 05 | `learn propose`: ledger -> cited, deduped, adversarially-checked staging | #243 | b2131dc |
| 06 | `learn drain`: staging review render + 30d expiry-to-section | #241 | d688306 |
| 07 | `mega review --html`: the per-mega sign-off dashboard | #238 | c2eb239 |
| 08 | `bin/config list\|get\|explain` + env<->key module registry + drift lint | #240 | ad81d46 |
| 09 | `/kit:onboard` guided first-run wizard (GATE, Han-approved) | #242 | 2ba70b6 |
| 10 | front door: README five-leg rewrite, parity pins, one scheduler, this report | (this PR) | (held) |

## Defects the harness caught mid-run

The things a post-merge reviewer cannot reconstruct from diffs.

**Three cross-sub-goal seams, none visible to per-PR CI.** Waves 2 and 3 built in parallel off the
gate branch, so each sub-goal's CI was green against a tree that never contained its siblings. All
three only surfaced when the branches were reconciled onto the integrated master:

1. **SG-07's dashboard read a path SG-04 had moved.** `mega-review.py` looked up the unpaid-debt
   counter at `lib/queue/weekend-batch.sh`; SG-07 merged *after* SG-04 relocated that file to
   `lib/learn/`, so SG-04's repoint could not have covered a call-site that did not yet exist.
   Caught by `test-mega-review` failing on the reconciled branch (25/26), fixed, 26/26.
2. **Two staging-block parsers shipped, both claiming to be the only one.** SG-05 landed
   `staging_format.py` and SG-06 landed `staging-format.py`, each with a docstring asserting it was
   "the ONE definition" , a direct violation of ADR-0034 decision 1, caused purely by the two
   sub-goals building concurrently with the shared-fixture rule unable to arbitrate. Their
   `parse_blocks` implementations differed. Unified onto the canonical hyphenated module (master's
   read side + SG-05's write side + its `parse|render` CLI); duplicate deleted. Suites: propose
   33/33, drain 23/23.
3. **`learn.sh` refused its own siblings' verbs.** Each branch's copy dispatched its verb and
   REFUSED the other two ("ships in SPEC-19x"), so a naive merge would have shipped a router that
   disabled two thirds of the subsystem. Resolved by three-way union: `debt` + `propose` + `drain`
   all live. Related: the bin census test still expected 12 entries after `bin/config` made 13, and
   SG-04's forwarder NC still asserted `learn propose` REFUSES after SG-05 made it live , both
   updated to assert dispatch.

**Lesson (the generalizable one):** per-PR CI cannot see a seam that only exists on the integrated
tree. Parallel waves buy speed and *manufacture* integration debt; the reconcile pass is where that
debt is paid, and it must run tests, not just resolve conflict markers. This is precisely the class
the TIER-4 convergence gate exists for, and it is the second mega in a row to prove it (kit-modularity
#198 was the first).

**One robustness bug fixed in passing (SG-10):** SG-08's drift lint swept files with `grep -roh`
and no `-I`, so grep's `Binary file <x> matches` message entered the token stream and a stray
`__pycache__/*.pyc` became a phantom ORPHAN. It false-failed twice locally (CI never saw it: the
cache is gitignored). Fixed with `-I --exclude-dir=__pycache__`; the negative control still fires.

**The Learn leg worked on day one.** During SG-05's verification `learn propose` ran against the
real ledgers and staged three cited proposals, including a genuine finding nobody had noticed: one
ops-toolkit session burned **2,115,144,012 tokens** (`lens=anomalies:token_runaway`), plus an
under-specced spec carrying 15 deviations and 21 memory notes pointing at dead paths. The loop's
first act was to hand the operator real work. That is the whole point of the mega.

**Process notes.** The queue launcher's send-keys sequence failed to submit twice (bracketed paste
and plain text both needed a separate `C-m`), so its Enter handling needs a settle-then-send fix.
The conductor session also hit a model usage limit mid-close-out and stalled; the operator finished
sub-goal 10 by hand. Neither is a defect in the shipped work, but both are real friction worth
carrying to the next run.

## Evidence index

| Artifact | What it proves |
|---|---|
| `proof/config-list.png` | `bin/config list` renders every knob with provenance + status tag (SG-08) |
| `proof/learn-drain.png` | `learn drain` renders staging grouped, age-sorted, evidence-first (SG-06) |
| `proof/mega-review-dashboard.png` | the per-mega HTML sign-off surface (SG-07) |
| `tests/test-meta.sh` (698/698) | README/architecture counts are parity-pinned; the agents-11-vs-25 drift class cannot recur |
| `tests/test-kit-weekly.sh` (14/14) | ONE weekly scheduler + jobs list; the per-job plist stays retired |
| `tests/test-learn-propose.sh` (33/33), `test-learn-drain.sh` (23/23) | the Learn leg's two verbs, on one unified staging module |
| `docs/verification/loop-10-front-door.md` | this sub-goal's proof-of-done |

## Close-out

- ROADMAP boxes 01-09 carry their PR + merge SHA; 10 flips when this PR merges.
- The mega folder stays in `dwarves-kit/_meta/megagoals/harness-loop/` (kit-owned work, per the
  lifecycle rule); no co-location move is owed.
- ops-toolkit ID-101 flips to shipped on merge; ID-273 (kit-wiring) gets a pointer note that its
  drafted `kit-retro` sub-goal shipped here as SG-05 (one engine, one truth).
- Deliberately NOT done, and stated so: the weekly LaunchAgent is *prepared*, not loaded. The kit
  ships the template + dispatcher + jobs list; instantiating and `launchctl bootstrap`-ing it on the
  consumer host is Han's click (SPEC-126 split, unchanged).
