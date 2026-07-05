# Sub-goal 07: reconcile the three scaffolding surfaces (never-diverge)

**Merge policy:** gate (never-diverge is taste-adjacent AND this touches Han's authoring skills, held for Han)
**Time budget:** 2-3 hours of loop work
**Proof:** run-table, a diff across all three scaffolding surfaces showing each was updated to the final surface (no stale `ledger-observatory`/`bash lib/<x>`/old-install references); a RE-RUN of the never-diverge mirror check proving the skill and `/kit:mega` still agree (the byte-identical-block + checklist-row contract from runner-fastpath SG-01/02). Named NC: grep each retired token across all three → zero live references. Rung 2.
**Design:** obvious (a reconciliation sweep against a settled surface + a re-run of an existing mirror check)
**Depends on:** 01, 02, 03, 04, 05, 06 (reconciles the FINAL surface, must be last)
Model: sonnet
**Branch:** docs/kitmod-07-reconcile
**PR base:** master (rebased after 06), cross-repo (dotfiles skills + dwarves-kit)

## Outcome

The three goal-scaffolding surfaces agree with the new orchestration surface and with each other: `plan-for-goal` (skill), `plan-for-mega-goal` (skill), and `/kit:mega` (`dwarves-kit/commands/mega.md`). Every reference they make to kit internals, `orchestrate`/`queue`, `board`, `gate-ledger`, `ledger-observatory` (now `stats`), `lib/<x>.sh` paths, the install/wire model, is updated in lockstep, and the never-diverge mirror check is re-run so the skill and `/kit:mega` remain byte-identical where they mirror. This is the CAPSTONE, it can only be done once SG-01..06 have settled the surface.

## Quality bar

No scaffolder silently points at a renamed/removed thing. The skill and `/kit:mega` still pass their mirror check (the runner-fastpath SG-01/02 contract). A future run scaffolded by any of the three lands on the CURRENT surface, not a stale one. Deliverable is a real diff + a re-asserted mirror check, not "looks consistent".

## How to close the loop

- Enumerate every reference the three surfaces make to kit internals (grep `plan-for-goal`, `plan-for-mega-goal` under `~/.claude/skills/`, and `dwarves-kit/commands/mega.md`).
- Update each stale reference in lockstep: `ledger-observatory`→`stats`; `bash lib/<x>.sh` → the standalone-command form where appropriate; the old install model → layered `--with`; any lib-vs-tools framing.
- Re-run the never-diverge mirror check (the byte-identical block + the checklist row that runner-fastpath SG-01/02 established between the skill and `/kit:mega`); confirm they still agree.
- NC: grep each retired token across all three → zero live references.
- Cross-repo: the skills live in dotfiles (`~/.claude/skills`), `/kit:mega` in dwarves-kit, drive each from its own repo; the mirror check spans both. Two PRs may be needed (one per repo); note the pairing.

Kit-adopted (dwarves-kit side): record docs + verify via `bash lib/gate-ledger.sh`.

**Done =** all three scaffolders reference zero stale surface (grep-audited across all three) AND the never-diverge mirror check passes (skill == `/kit:mega` where they mirror), captured in `docs/proof/kitmod-reconcile.md`. THEN OPEN the PR(s) and STOP, held final, for Han (it edits his authoring skills).

## Handoff on completion

1. Flip box, record PR # (do NOT merge, held for Han).
2. HANDOFF.md: mega BUILD-COMPLETE; convergence gate = full suite green + spine-only install + per-module doc/firing audit + the mirror check.
3. DECISIONS.md: record any scaffolder flow that changed materially.
4. Append the ops-toolkit `_meta/LAB_LOG.md` mega-arc entry (SPEC-005) on this branch.
5. Report in records, EXIT (emit the gate-pause approval banner).

## Scope edges

**In:** `~/.claude/skills/plan-for-goal`, `~/.claude/skills/plan-for-mega-goal` (dotfiles), `dwarves-kit/commands/mega.md` (`/kit:mega`); the mirror check.
**Out:** the code + docs (SG-01..06); Decision H.
**Not:** redesigning the scaffolders; changing the triage-ladder content (only stale-reference reconciliation + the mirror re-run); adding new scaffolder features.

## Where to look

`~/.claude/skills/plan-for-goal/SKILL.md` + `plan-for-mega-goal` (+ its references), `dwarves-kit/commands/mega.md`, the runner-fastpath SG-01/02 never-diverge contract, design note Decision G.

## PR body

Reconcile `plan-for-goal` + `plan-for-mega-goal` + `/kit:mega` to the final surface (no stale `ledger-observatory`/`lib/<x>`/old-install refs) + re-run the never-diverge mirror check. Cross-repo (dotfiles skills + dwarves-kit).

Verify: grep-audit (zero stale across all three) + the re-asserted mirror check. Proof: `docs/proof/kitmod-reconcile.md`. HELD final PR, edits Han's authoring skills. Stacked on #<SG-06>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes
