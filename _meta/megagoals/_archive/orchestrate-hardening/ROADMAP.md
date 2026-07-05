# Mega-goal: orchestrate-hardening

**Destination:** The dwarves-kit orchestrator runs big mega-goals CONTEXT-HYGIENICALLY and OBSERVABLY. The delegate run mode is a first-class citizen (not a POINTER_PROMPT convention the model is asked to obey): `orchestrate.sh` honors the per-sub-goal `Model:` field on the delegate path (planning -> opus), delegated sessions still emit EVERY ledger (gate / proof / token / debt), token capture works WITHOUT dumping the child transcript into the conductor, there is a real mega-level TIER-4 close (integration-verifier + review-team + advisor before the final human gate, not just a printed "done"), and parallel wavefront wave sessions are watchable + interruptible in tmux/cmux panes. This mega-goal EXECUTES dwarves-kit ADR-0032; it does not re-decide it.
**Quality bar:** `/goal` stays the OFFICIAL outer loop , delegate changes what the loop DOES, not the runner (no replacing `/goal`, no new orchestration daemon). Every change proves a LIVE dispatch path (kit-hardening c6fbd99 anti-orphan lesson): a `Model:` field that reaches the actual `--model` flag, a token capture path a real run exercises, a TIER-4 close a real assembled wave runs through, a multiplexer pane a real wave session lands in. The gate/proof/debt ledgers ALREADY work under delegation (per-sub-goal rids are the evidence) , this mega-goal VERIFIES + DOCUMENTS that, it does not rebuild them. Minimum-infra: tmux/cmux is already installed, no new daemon. Over-test 02 (token capture from file + conductor context stays lean) + 03 (the mega-close actually runs the verifiers before the gate).
**Work repo:** `dwarves-kit` (kit-adopted; `lib/orchestrate.sh` + `lib/route-suggest.sh` + the delegate hooks). The roadmap lives HERE in ops-toolkit. Cross-repo: the plan-for-mega-goal pointer-template touch, IF any is needed, is a dotfiles half (edit chezmoi source -> `chezmoi apply` -> stage+commit in ONE shell call, the S-64 watcher reverts uncommitted tracked changes); the rest is dwarves-kit.
**Stacking tool:** gh (stacked; linear 01<-02<-03<-04<-05 for merge ordering + shared-file `orchestrate.sh` conflict avoidance)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final (the final PR , 05 docs , is Han's click; 01-04 auto-merge as gates pass)
**Run mode:** delegate (5 sub-goals > 4; the `/goal` loop is a THIN CONDUCTOR that delegates each sub-goal to a fresh headless `claude -p` and absorbs one terse line , per the plan-for-mega-goal run-mode option this mega-goal itself hardens)
**Terminus:** build + merge + the held final PR.
**Started:** 2026-07-03

## Gate zero (decision before code)

**ADR-0032 (mega-goal execution hygiene) must be ACCEPTED first.** It is Proposed (dwarves-kit PR #131).
This mega-goal EXECUTES that ADR; it does not re-decide it. The pointer's turn-1 checks `docs/decisions/
0032-megagoal-execution-hygiene.md` Status; if not Accepted, it STOPS for Han's bless (ADR-0028 gate-zero
pattern). Sequenced AFTER kit-face (SG-03 token ledger) + understanding-gate (SG-02 debt ledger): those
two DEFINE the token + debt ledgers this mega-goal hardens under delegation , do not stack ahead of the
ledgers whose delegation-survival is the thing being proven.

## Provenance

`ops-toolkit/research/2026-07-03-megagoal-execution-hygiene.md` (the execution-economics half of the
873k-context session) + dwarves-kit `docs/decisions/0032-megagoal-execution-hygiene.md` are the design
source. Both are BINDING: the delegate-vs-inline run modes, the discovery-cost framing, per-sub-goal
model routing (planning -> opus), the delegated-ledger reconciliation (token stream-to-FILE), and the
multiplexer control plane are DECIDED there. This mega-goal builds the four gaps ADR-0032 section 5
obliges the kit to close (model-routing enforcement, token stream-to-file, TIER-4 mega-close,
multiplexer panes). Build in a FRESH session (the source session is the 873k ceiling this work answers).

## Sub-goals

- [x] 01-model-routing-enforce , `orchestrate.sh` honors the per-sub-goal `Model:` field on the delegate path (planning->opus etc.); confirm `route-suggest.sh`'s Opus-spend heuristic aligns; a test that a goal file's `Model: opus` reaches the `claude -p --model opus` call , `auto` , `sonnet` , PR #139 (merged 44d2b8f)
- [x] 02-token-capture-delegate , reconcile the token ledger (kit-face SG-03) with the plain-`-p` delegate rule: stream the child to a FILE (`claude -p --stream > child.jsonl`), extract usage from the file, the conductor reads only the box-flip , token capture WITHOUT dumping the child transcript into the conductor. SUBSTANTIAL , OVER-TEST , `auto` , `opus` , PR #140 (merged a5393de)
- [x] 03-tier4-mega-close , a first-class mega-level TIER-4 close in `orchestrate.sh` (or a final auto sub-goal): after all boxes checked, run integration-verifier + review-team + advisor over the assembled result before the final human gate , today `orchestrate.sh` just prints "done" and returns. SUBSTANTIAL , OVER-TEST , `auto` , `opus` , PR #141 (merged 346fe1e)
- [x] 04-multiplexer-panes , opt-in: `orchestrate.sh` spawns each wavefront wave session into a tmux/cmux pane (`tmux new-window` / `capture-pane` / `send-keys`) for visibility + intervention; off by default; pure headless orchestration unchanged when off , `auto` , `sonnet` , PR #142 (merged d3e63ef)
- [x] 05-docs-wiring , WORKFLOW.md + AGENTS.md describe the delegate run model + the ledger-under-delegation guarantee + the multiplexer option (honestly, only what dispatches); the no-orphan wiring check , `auto` , `sonnet` , PR #144 (merged edc7934; tests 25/25 incl. AC10 over-claim NC)

## Dependencies

- 01 / 02 / 03 / 04 are logically INDEPENDENT (each a distinct `orchestrate.sh` / `route-suggest.sh` concern); only 05 hard-depends on all four.
- 02 RELATES to the kit-face token ledger (SG-03) , an EXTERNAL dependency: 02 reconciles against that ledger's `TOKENS` marker + capture path, it does not rebuild the ledger (gate zero sequences 02 after kit-face SG-03 lands).
- 04 RELATES to ADR-0030 wavefront (the parallel waves it spawns into panes) , a SOFT relation, not a hard code dep; the pane spawn wraps the existing headless wave dispatch.
- 05 depends on ALL (docs-last: describe the FINAL wired delegate model, not a mid-wave snapshot , the kit-face lesson that docs written early over-claim).
- Execution order: {01, 02, 03, 04} -> 05. The gh stack is LINEAR for merge ordering + shared-file conflict avoidance (01-04 all touch `orchestrate.sh`): 01 off `master`; 02 bases 01; 03 bases 02; 04 bases 03; 05 bases 04, LAST.

## The delegate run model (BINDING)

```
/goal (official outer loop, THIN CONDUCTOR)        each sub-goal: fresh, cold, dies
 holds only roadmap + terse results                  claude -p  (plain -p, NEVER --stream
     |                                                 piped TO the conductor)
     |-- dispatch sub-goal --> claude -p --model <Model:> --> /spec .. execute .. PR
     |        ^                      |  emits ALL ledgers under its own rid:
     |        | terse box-flip <-----|    gate . proof . run   (by construction, proven)
     |        |  (PR #N, proof)      |    token  -- --stream > child.jsonl (02) ----+
     |    auto-bottom-up merge       |    debt   -- worker writes the marker --------+
     |                               +----------------------------------------------+
     |                                        (conductor context stays LEAN)
     |
     +-- after 01-04 merge --> TIER-4 MEGA-CLOSE (03): integration-verifier
                                 + review-team + advisor + no-orphan check
                                 --> HOLD the final PR for Han

  opt-in (04, off by default): each wavefront wave session --> tmux/cmux pane
                                (watch + intervene; headless path UNCHANGED when off)
```

- `/goal` is the OFFICIAL outer loop , delegate changes what the loop DOES per turn, not the runner. No replacement, no new daemon.
- Delegate uses PLAIN `claude -p` to the conductor. `--stream` is used ONLY to a FILE (02's token capture), never piped to the conductor , piping the child stream to the parent IS the accumulation trap this whole design avoids.
- Gate / proof / run ledgers survive delegation BY CONSTRUCTION (each delegated session records under its own rid). Token needs the stream-to-file reconciliation (02); debt is split (worker writes marker, conductor fires the human nudge).
- The multiplexer (04) ADDS visibility + intervention only; pure orchestration (spawn / control / receive) already works headlessly via Bash + `claude -p`.

## Assumptions (2026-07-03; ADR-0032 + the research note resolved the shape; per-sub-goal /spec re-frames)

- **`/goal` stays the OFFICIAL outer loop** , delegate changes what it does, not the runner. ADR-0017 activator-agnostic stands; `/goal` is not replaced.
- **Delegate = plain `-p` to the conductor** , the child prints only a terse box-flip. `--stream`-to-FILE is used ONLY for token capture (02); it is never piped to the conductor.
- **Gate / proof ledgers ALREADY work under delegation** , the per-sub-goal rids are the evidence. Do NOT rebuild them; VERIFY + DOCUMENT the survival (the observability line holds under delegate).
- **The multiplexer is OPT-IN visibility, NOT required for orchestration** , off by default; the headless wave path is byte-unchanged when off.
- **Minimum-infra** , tmux (and cmux) are already installed; no new daemon, no new listener.
- **Cross-cutting WIRING GATE (kit-hardening c6fbd99 lesson):** every artifact proves a LIVE dispatch path , a `Model:` field that reaches `--model`, a token path a real run exercises, a TIER-4 close a real wave runs through, a pane a real session lands in. TIER-4 runs a NO-ORPHAN check: a defined-but-never-dispatched flag / step / path is a BLOCKING finding, and a WORKFLOW.md / AGENTS.md claim with no dispatch path is a blocking finding.

## Open forks (surface, non-blocking; /spec defaults)

1. **TIER-4 placement (03):** a first-class STEP inside `orchestrate.sh run` vs a FINAL AUTO SUB-GOAL the decompose appends. /spec picks (step = tighter coupling to the run; sub-goal = reuses the existing lifecycle + gate ledger). Scaffold either way behind the same close contract (integration-verifier + review-team + advisor + no-orphan, before the human gate).
2. **Pane driver (04):** tmux vs cmux. Both installed; cmux is the operator's daily driver (CMUX_WORKSPACE_ID + the cmux-browser skill), tmux is the portable/headless-safe default. /spec picks; default to the one that keeps the headless path intact when the multiplexer is off.
3. **Model-routing enforcement site (01):** in `orchestrate.sh` (reads `Model:`, passes `--model` at the delegate call) vs in `route-suggest.sh` (the Opus-spend heuristic owns the tier decision). /spec picks; the two must AGREE (a `Model: opus` goal file and the heuristic must not contradict), so 01 confirms alignment wherever the enforcement lands.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
