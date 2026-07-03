## dwarves-kit v2.0.0 , production-facing + cost-measured

The release hold lifts: **kit-hardening** (the hold's condition) is complete and the **kit-face**
megagoal ships on top of it. This is a major bump , three agent renames are breaking, and the kit
now measures its own token cost.

### ⚠️ BREAKING , agent renames (ADR-0029)
| old | new |
|---|---|
| `integration-checker` | `integration-verifier` |
| `reviewer` | `code-reviewer` |
| `security-auditor` | `security-reviewer` |

Update any `subagent_type:` dispatch or invocation-template in a consuming repo. A grep of the
sibling consumer repos found the old names only in historical research/notes/templates , no live
dispatch wiring.

### ✨ kit-face megagoal (8 sub-goals)
- **Cheap-first tier default** across execute workers, meta-agent Mode B, and the subgoal-template , sonnet by default, opus the explicit escape hatch (SPEC-107).
- **Meta-agent provenance** (`generated-by:`) + **runtime efficacy metric 11** (generated-agent catch count) (SPEC-108).
- **Capture-gated token accounting** , a `gate-ledger tokens` ledger line, `sum-usage` parser, `lane-telemetry` token section + `render --mermaid`; honest `usage=?`, default `claude -p` path byte-unchanged (SPEC-110).
- **Operator-persona design lens** , an inline 6th `/kit:visual-team` lens (SPEC-109).
- **UI done-modes + bounded quiescence loop** (proof | over-test | quiescence; two-sided stop, cap 3) (SPEC-112).
- **Starter role-specialized agent roster** , 2 workers + 4 reviewers, two live dispatch paths, reconciling SPEC-089 (SPEC-111).
- **README mermaid hero** + test-pinned layout counts (SPEC-113); **navigable docs map** (SPEC-114).

Three version surfaces aligned at 2.0.0 and pinned together. See `CHANGELOG.md` for the full per-spec detail (this release also folds in the kit-hardening + kit-telemetry waves accumulated under `[Unreleased]`).
