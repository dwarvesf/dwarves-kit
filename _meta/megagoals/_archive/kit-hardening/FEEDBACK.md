# FEEDBACK , kit-hardening

Append-only. Categories below are suggestions; use whichever fits. Audience: Han (skill/kit maintainer).

## Skill friction

2026-07-02 · skill friction · The decomposition source (ADR-0028) had already renumbered the sub-goals (SG-01/05/06/07/08) away from the older decision-brief's SG-A/B/C, and the SG-numbers COLLIDED with a different mega-goal (token-optim-v3's SG-10/11 in orchestrate.sh). Reconstructing the canonical map took several greps. Lesson for future kit mega-goals: when an ADR grows a wave, write the SG->sub-goal map into the ADR explicitly instead of leaving it implied across prose refinements.

2026-07-02 · skill friction · The implicit SG map bit for real: the first scaffold shipped 7 sub-goals, but the ADR's "adds THREE to the wave" arithmetic implies SG-01..05 + 3 = 8. The missed one was the kit-side mega-lane reconcile (`/kit:mega` mirror + ship-layer auto-merge enforcement), which the scaffolder had wrongly filed as "P3 out of scope" because `orchestrate.sh` exists , but that is the ACTIVATOR half; the ADR's placement table puts the mirror + enforcement in the KIT. Caught only when Han said "check the kit-hardening in dwarves-kit". Same lesson, sharper: an ADR that names a wave must enumerate it.

## Tooling gaps

<none yet>

## Codebase issues

2026-07-02 · codebase · ADR-0028 and SPEC-088 both referenced `_meta/megagoals/{token-optim-v3,kit-hardening}` as if the folders existed, but neither was scaffolded. Dangling mega-goal references in accepted ADRs. This scaffold fixes kit-hardening; token-optim-v3's folder is still missing.

## Pointer prompt churn

<none yet>
