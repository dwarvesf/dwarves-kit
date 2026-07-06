# Mega-goal: cc-elevation-r4

**Destination:** achieve **Hermes self-improvement-loop parity** in Claude Code. The memory
half already ships (`cc-harvest`). This round adds the **skill half** (auto-draft + promote
gate), the **curator** (consolidate + archive, never delete), **unified surfacing + cost**,
and the **per-turn memory cadence** so memory capture matches Hermes's memory nudge. Same
posture as r1/r2/r3: read-only, propose-don't-dispose, minimum-infra, propose-and-stage,
every sub-goal owes a co-located proof-of-done (green run + negative control).

Master spec (VALIDATED): `tools/cc-self-improve/docs/specs/SPEC-103-cc-self-improve.md`.
Research: `research/2026-06-19-hermes-self-improvement-loop.md`.

## Sub-goals

- [x] 01-harvest-per-turn-trigger , cc-harvest gains an OPTIONAL Stop-hook per-N-turns trigger reusing its extractor + ledger + dedup, so memory capture matches Hermes's memory nudge; opt-in (default off), async, exit-0 , PR #422 merged 392e7537 (base: main)
- [x] 02-skill-reviewer , cc-self-improve Phase A: skill-draft reviewer as a NO-WRITE pure function (`claude -p --allowedTools ""`) + trusted-bash staging writer to `~/.claude/skill-proposals/` + cost ledger + transcript parser , PR #425 merged 7f966441 (base: main)
- [x] 03-promote-and-surface , cc-self-improve Phase B: `/skill-review` promote gate + SessionStart surfacing + async/reentrancy/staging-gate tests + install.sh , PR #429 merged 91a7fdec (base: main; 02 merged so off main)
- [x] 04-skill-curator , cc-self-improve Phase C: `cc-improve curate` pure-function plan + trusted git-mv archive (never delete) + propose-only weekly launchd + vps-mon wiring + docs close-out (+ full canonical doc set, architect + doc-verifier reviewed) , PR #430 (base: main; 03 merged so off main) , GATE (host-touching launchd): merged on Han's approval

## Dependencies

- **02 -> 03 -> 04 are stacked** (all edit `tools/cc-self-improve/`; parallel PRs on the same
  tool dir would conflict). 03 branches off 02's branch, 04 off 03's.
- **01 is independent off `main`** (edits `tools/cc-harvest/` only). Merge any time.
- Round-level **Hermes parity** is satisfied when 01 (memory per-turn) + 02/03 (skill
  draft+promote+surface) + 04 (curator) land on top of shipped cc-harvest: memory + skill,
  automatic, background, non-blocking, propose-and-stage. Assert this in the final close-out.

## Round status , Hermes self-improvement-loop parity (close-out, 2026-06-19)

**ASSERTED: parity achieved.** The full loop now exists on Han's Claude Code cockpit, with a
hardening over Hermes (propose-and-stage instead of auto-apply; the model has no filesystem write):

| Hermes mechanism | Claude Code equivalent | Where | Status |
|---|---|---|---|
| Memory nudge (per ~10 turns) | cc-harvest `--stop-trigger` (opt-in per-N-turns) + PreCompact/SessionEnd | `tools/cc-harvest` (01 + shipped) | ✓ PR #422 |
| Skill nudge (draft/patch a skill) | no-write `claude -p` reviewer -> staged SKILL.md draft | `tools/cc-self-improve` Phase A (02) | ✓ PR #425 |
| `guard_agent_created` auto-apply | `/skill-review` promote gate (the only writer of skills/) + SessionStart surfacing | Phase B (03) | ✓ PR #429 |
| `curator.py` umbrella consolidation + archive | `cc-improve curate` (propose-only, git-mv archive never delete) + weekly launchd | Phase C (04) | held PR #430 |

Divergences from Hermes (deliberate, hardened): the reviewer/curator MODEL runs `--allowedTools ""`
(no write at all); staging-by-path is a structural gate; selective drafting (`null` is valid);
secret guards in prompt + wrapper; curator never deletes. Suite = cc-harvest (memory) +
cc-self-improve (skill + curator) + unified surfacing + cost ledger.

## SDD per sub-goal

This repo is kit-adopted. Each sub-goal runs its own full lane (`lane-classify`) and owes a
co-located proof-of-done before its PR, or the ship-gate blocks the push. 02/03/04 extend
`tools/cc-self-improve/docs/proof-of-done.md` (multi-feature index per SPEC-016); 01 extends
`tools/cc-harvest/docs/proof-of-done.md`. Each sub-goal generates its own phase spec under the
relevant tool's `docs/specs/` at execution time; SPEC-103 is the umbrella.

## Merge policy (auto-bottom-up + gated-final)

The loop **auto-merges the `auto` sub-goals itself** (01, 02, 03), bottom-up, doing the
retarget-child-before-delete dance automatically (`feedback_stacked_pr_delete_branch`). An `auto`
PR merges only when all gates hold: its Done= verified, proof-of-done committed WITH captured
evidence (a run-table / real log slice, never a bare "GREEN"), and reviewDecision not
CHANGES_REQUESTED. 01 (off main) merges any time. **04 is `gate`**: the close-out + host-touching
launchd PR is HELD for my click (it carries the LAB_LOG entry, the suite-docs memory/skill split,
and the round-level parity assertion). Record `PR #N` + merge SHA on each roadmap line as it lands.

## Audit cheat sheet

Each sub-goal owes a co-located proof with a green run + a negative control. Key negative
controls: 01 a slow harvest must not block + counter<N must not fire; 02 a no-signal transcript
yields no draft + the reviewer (no Write tool) cannot write under `skills/`; 03 a proposal under
`skill-proposals/` is not auto-loaded; 04 curate changes nothing without `--apply` + archive uses
`git mv` not `rm`.

## Source

`tools/cc-self-improve/docs/specs/SPEC-103-cc-self-improve.md` (VALIDATED) +
`research/2026-06-19-hermes-self-improvement-loop.md`. Predecessors: cc-elevation (r1),
cc-elevation-r2, cc-elevation-r3. Sibling shipped tool: `tools/cc-harvest/` (memory half).
