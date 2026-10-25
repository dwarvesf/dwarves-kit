# SPEC-031 / ID-034: V-model SDLC mapping — research targets

## Deliverable 1: C2 reword target list

Locations that hard-code "8 phases" or the exact phase set and require rewording
when the V-model phase set replaces the current frame.

| File | Line | Quoted text needing reword |
|---|---|---|
| `docs/PHILOSOPHY.md` | 51 | "covering 8 lifecycle phases (Think, Spec, Validate, Build, Review, Docs, Ship, Reflect) at 70% depth each" |
| `docs/PHILOSOPHY.md` | 170 | "It serves fewer than 2 of the 8 workflow phases." (feature-rejection criterion #2) |
| `commands/kit-health.md` | 152 | "Single-purpose features serving fewer than 2 of the 8 workflow phases." (Step 4 reject list item 4) |

No other files contain a literal "8 phases / 8 workflow / 8 lifecycle" string.
`WORKFLOW.md`, `docs/ORCHESTRATION.md`, and `docs/operating-layer-vision.md` list
phases structurally (in tables/diagrams) but do NOT count them as "8"; they are
safe to extend without a reword.

---

## Deliverable 2: Current define -> verify mirror (V-model right-arm map)

Left arm = define/build command. Right arm = its verification counterpart.

| Phase | Define command | Verification mirror | Mirror exists? |
|---|---|---|---|
| Think / Brief | `/kit:think` | none | NO — gap |
| Requirement / Assign | `/kit:assign` | none | NO — gap |
| Design | `/kit:design` | `/kit:devs-team` (5-lens critique) | YES (advisory) |
| UI Design | `/kit:ui-design` | `/kit:visual-team` (visual critique) | YES (advisory) |
| Spec | `/kit:spec` | `/kit:spec-validate` (adversarial 5-lens review) | YES |
| Test plan | `/kit:test-plan` | `/kit:execute` reads + runs the plan | YES (implicit) |
| Build | `/kit:execute`, `/kit:next` | `task-verifier` subagent + `fix-agent` retry (max 2) | YES (hard gate) |
| Review | `/kit:review`, `/kit:review-team` | `reviewer`, `security-auditor` subagents | YES |
| Docs | `/kit:docs` | `doc-verifier` subagent | YES |
| Ship | `/kit:ship` | ship gate (DO-NOT-SHIP check) + push-to-main blocker | YES (hard gate) |
| Reflect | `/kit:retro` | none (narrative only) | NO — by design |

**Gaps ID-034 must address:**
- **Think/Brief**: no verification mirror. A brief can be written and left unreviewed.
  The V-model right arm here would be a "brief-critique" or structured challenge pass.
- **Requirement/Assign**: `/kit:assign` produces a goal draft and routes a lane, but
  there is no dedicated check that the requirement is testable / complete before SPECIFYING
  begins. The V-model right arm would be a requirement-review step before the spec.
- **Reflect/Retro**: intentionally gap (narrative artifact; no machine-checkable criterion).
  Not an ID-034 target.

