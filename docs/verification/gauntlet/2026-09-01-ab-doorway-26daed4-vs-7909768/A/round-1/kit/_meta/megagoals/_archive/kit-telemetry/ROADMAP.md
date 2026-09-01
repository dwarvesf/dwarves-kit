# Mega-goal: kit-telemetry

**Destination:** The dwarves-kit trust loop is MEASURED, not asserted: run telemetry survives plugin reinstalls, the SPEC-073 effectiveness eval has run on real usage data, the lane-classify rules are audited against recorded misfires, lane usage is visible on a dashboard, and mega auto-merge is code-guarded against merging a gate/final PR.
**Quality bar:** Every claim in this wave is backed by the recorded corpus (the 8 kit-harden run ledgers + the 2026-07-02 process-effectiveness audit), never re-derived from vibes. This run DOGFOODS the kit-hardening machinery it rides on (advisor lens, recheck-verifier, every-step review, lane escalation, gate-checked auto-merge) , any friction in that machinery is itself a finding, log it.
**Work repo:** `dwarves-kit` (cross-repo: roadmap here in ops-toolkit; all PRs land in dwarves-kit against `master`).
**Stacking tool:** gh (stacked PRs: dependent sub-goals branch off their parent's branch, base = parent)
**Merge mode:** auto-bottom-up (the loop walks the stack bottom-up, merges each `auto` PR once its gates pass, doing the retarget-child-before-delete dance itself)
**Merge autonomy:** gated-final (the LAST sub-goal PR that completes the mega-goal is held for Han; everything before it auto-merges)
**Terminus:** build + merge. Kit-internal tooling, no runtime deploy surface; deliberately no deploy/UAT gate. (01 migrates ledger storage , that is host-config, verified by its own negative control, not a service deploy.)
**Started:** 2026-07-02

## Authority

This wave EXECUTES five already-triaged board rows , dwarves-kit ID-082 / ID-067 (SPEC-073) / ID-083 and ops-toolkit ID-149 / ID-150 (both reconciled+narrowed 2026-07-02) , sequenced by the dependency insight from the 2026-07-02 reconciliation: protect the corpus -> evaluate on it -> visualize it. The evidence base is `ops-toolkit/research/2026-07-02-process-effectiveness-audit.md` + the kit-harden run ledgers (`~/.claude/dwarves-kit/logs/runs/kit-harden-*`). Unlike kit-hardening there is no single ADR; each sub-goal gets its own SPEC via `/spec` + `/spec-validate` (P1 deeper planning, now a kit default).

## Sub-goals

- [x] 01-ledger-durability , run-ledger storage survives plugin reinstall + per-gate override reasons enforced , `auto` , PR #112 merged 7efacc1
- [x] 02-effectiveness-eval , SPEC-073 executed on the kit-harden corpus, consuming the 2026-07-02 audit for the proof-effectiveness half , `auto` , PR #113 merged 581f769
- [x] 03-lane-rule-audit , lane-classify task-shape->lane rule correctness audited against recorded misfires; fixes pinned , `auto` , PR #114 merged e5e9697
- [x] 04-lane-dashboard , routing diagram + run counts rendered over lane-telemetry output , `auto` , PR #115 merged 1bd5958
- [x] 05-mega-merge-guard , code-level gate/final-PR exclusion cross-check in `lib/mega-merge.sh` , `auto` , PR #117 merged a07d992

## Dependencies

- 02 depends on 01 (the eval's corpus must be in durable storage first , losing it mid-eval to a reinstall is the exact failure ID-082 names).
- 03 depends on 01 (same misfire data).
- 04 depends on 01 + 03 (renders the data 01 protects; the audit in 03 may re-shape what is worth rendering).
- 01 and 05 are independent (05 can run any time).
- Stack shape: 01 off `master`; 02 and 03 branch off 01 (PR base = 01's branch); 04 off 03; 05 off `master`.
- Suggested order: 01 -> (02, 03 in either order) -> 04, with 05 slotted whenever free.

## Assumptions (resolved at decompose time, 2026-07-02)

- **Eval output home:** sub-goal 02's report lands at `dwarves-kit/docs/research/2026-07-02-effectiveness-eval.md` (dated snapshot, kit-side since the subject is the kit). It CONSUMES the ops-toolkit audit; it does not re-run the 60-day git forensics.
- **02 is report-first:** small classifier/proof fixes may ride inline; anything structural becomes a board row, not scope creep (no-new-sub-goals rule).
- **Dashboard render target (old ID-150 Open Q):** a `lane-telemetry.sh render` ASCII view + one committed markdown snapshot under `docs/research/`. No web UI, no new dependency.
- **01's negative control simulates reinstall** (temp `$HOME`/env-pointed dir removed and recreated), never by actually deleting the live plugin dir.
- **Board-row flips:** kit rows (ID-082/067/083) flip to `executing`/`shipped` RIDING the sub-goal's own PR (bookkeeping-inside-feature-PR rule). ops rows (ID-149/150) are cross-repo: leave a NOTES line; they get flipped at close from ops-toolkit.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
