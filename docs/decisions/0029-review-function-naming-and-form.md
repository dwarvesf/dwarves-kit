# 0029. Review-function naming and form convention (both V-model arms)

Date: 2026-07-01
Status: Accepted (2026-07-01, Han , one-axis `security-reviewer`; convention machine-enforced in test-meta per SG-08)
Relates-to: ADR-0018 (V-model phase frame , this names the reviewers that lens defines), ADR-0005 (read-only verifier pattern), ADR-0015 (integration-checker), ADR-0016 (doc-verifier), ADR-0024 (gate-ledger), ADR-0028 (autonomous-loop hardening , SG-06 births new reviewers, SG-08 migrates the legacy names), SPEC-088 (agent-effectiveness validator)

## Context

The kit's review functions grew organically, so the same concept (a read-only reviewer of one V-model artifact) wears many names across two forms. The V-model lens (ADR-0018) names the arms but not the reviewers, so nothing constrains how a new reviewer is named or shaped. The result, today:

| Arm | Artifact | Review function | Form | Suffix |
|---|---|---|---|---|
| Left | spec | `spec-validate` | command (5 inline lenses) | `-validate` |
| Left | design | `devs-team` | command (5 inline lenses) | `-team` |
| Left | code | `review` / `review-team` -> `reviewer`, `security-auditor` | command -> agents | bare / `-auditor` |
| Left | UI | `visual-team` | command (5 inline lenses) | `-team` |
| Left | docs | `docs` -> `doc-verifier` | command -> agent | `-verifier` |
| Right | integration | `integration-checker` | agent (auto in execute) | `-checker` |
| Right | task/code | `task-verifier` | agent (auto in execute) | `-verifier` |
| Right | acceptance | ship-gate | hook | , |

Three inconsistencies: (1) FORM , left-arm reviews are commands you invoke, right-arm reviews are agents auto-dispatched in `/kit:execute`; (2) SUFFIX ZOO , one concept wears `-validate` / `-team` / `-checker` / `-verifier` / `-auditor` / bare; (3) TWO WORDS FOR ONE IDEA , `check` vs `verify`, `audit` vs `review` vs `validate`. ADR-0028's SG-06 was about to add three MORE suffixes (`-auditor`, `-reauditor`, `-reviewer`); this ADR is written before those agents are built so they are born consistent.

## Decision

Name every review function by its ROLE on one axis, and make the panel-command the only command form.

**Naming (role axis):**
- **`<x>-reviewer`** , a LEFT-arm STATIC review of one artifact ("did we build it right"): it READS the artifact and judges it. E.g. `code-reviewer`, `brief-reviewer`, `docs-reviewer`.
- **`<x>-verifier`** , a RIGHT-arm DYNAMIC test of one artifact ("does it actually work"): it EXECUTES the artifact and observes. E.g. `task-verifier`, `integration-verifier`, `acceptance-verifier`, `system-verifier`.
- **`<x>-team`** , a COMMAND that runs a PANEL of `-reviewer` lenses in parallel. The only command-form review. E.g. `devs-team`, `review-team`, `visual-team`.
- **`advisor`** , the single cross-cutting generic lens (ADR-0028 SG-05); legitimately its own noun, not per-artifact.

Retire `-checker`, `-validate`-as-a-suffix, `-auditor`, and bare `reviewer` as review-function names.

**Form:** every review is an AGENT (the ADR-0005 read-only verifier pattern). A `-team` command is an ORCHESTRATOR that dispatches reviewer agents; a single-lens review is the agent, invoked via its phase command. The left/right difference is only WHEN it runs (invoked as a phase on the left; auto-dispatched inside `/kit:execute` on the right), NOT a difference in form. This makes the two arms symmetric: both are agents, some fronted by `-team` panels.

## Amendment (2026-07-02, operator)

Two clarifications, no decision change:

1. **The stated axis is STATIC vs DYNAMIC, not verification vs validation.** The original gloss tagged `-reviewer` "(verification)" and `-verifier` "(validation)"; dropped. Under strict ISTQB vocabulary a right-arm test against acceptance criteria (i.e. against spec) is itself verification, so the ver/val tags fought the very names they glossed , "a verifier doing validation". The distinction that does the real work: a `-reviewer` READS the artifact (static), a `-verifier` EXECUTES it (dynamic). The slogans stay; the ver/val tags go.
2. **`recheck-verifier` semantics pinned: re-execution.** The fresh-context re-audit RE-RUNS the verification commands and re-judges the outcome; it is NOT a read-back of the recorded evidence (a read-back cannot catch stale or fabricated evidence, which is exactly what the ADR-0028 trust metric needs caught). This keeps it on the dynamic side, so the `-verifier` suffix is correct on the convention's own axis.

## The rename map

| Current | -> | Convention | Kind | Blast radius | Note |
|---|---|---|---|---|---|
| `integration-checker` | -> | `integration-verifier` | shipped agent | 31 files, clean token | mechanical sed + `test-meta.sh` |
| `reviewer` | -> | `code-reviewer` | shipped agent | 81 files, COLLIDES with the English word | NOT a blind sed , rename the frontmatter `name:` + dispatch call-sites only, by word boundary; leave prose "reviewer" |
| `security-auditor` | -> | `security-reviewer` | shipped agent | 19 files + external harness registry | RESOLVED one-axis (Han 2026-07-01); migration MUST also update the external `kit:security-auditor` registry exposure + any caller |
| `task-verifier` | -> | `task-verifier` | shipped agent | , | already conforms |
| `doc-verifier` | -> | `doc-verifier` | shipped agent | , | already conforms (tests doc claims against the live codebase = dynamic side) |
| `acceptance-auditor` | -> | `acceptance-verifier` | SG-06 (unbuilt) | 0 | free plan-fix |
| `test-reauditor` | -> | `recheck-verifier` | SG-06 (unbuilt) | 0 | free; the one new role , a fresh-context verifier OF a verifier's PASS; RE-EXECUTES the verification commands, never a read-back of recorded evidence (see Amendment) |
| `brief-reviewer` | -> | `brief-reviewer` | SG-06 (unbuilt) | 0 | already conforms |
| (new) `system-verifier` | | `system-verifier` | SG-06 (new) | 0 | right-arm mirror of design (was the agent-less "project suite") |

Inline panel lenses (the 5 role specs inside `devs-team` / `spec-validate` / `visual-team`) are NOT agent files , they are role labels the command dispatches ad hoc. Aligning their labels to the convention is OPTIONAL / secondary; the named agent files are the priority.

## Migration (SG-08)

Gated (team-facing rename): open the PR, `/kit:review-team`, human ships (this ADR must be Accepted first, per ADR-0028's gate-zero).

1. Per shipped rename: rename `agents/<old>.md` -> `agents/<new>.md`, update the frontmatter `name:`, update every dispatch call-site + doc/test/MANUAL/architecture reference by WORD BOUNDARY (never blind `sed s/reviewer/code-reviewer/` , the `reviewer` token collides with prose).
2. Roster sync (`test-meta.sh` fails closed): MANUAL agent table + `docs/architecture.md` V-phase inventory + README command rows.
3. **Negative control:** `grep -rwn '<old-name>'` over `agents/ commands/ lib/ tests/ docs/ *.md` returns ZERO agent-name hits (prose mentions in historical `docs/research/` snapshots are exempt and noted).
4. `test-meta.sh` green.

## Resolved sub-decision (2026-07-01, Han)

`security-auditor` -> `security-reviewer`, ONE AXIS. The two-tier option (keep `-auditor` as a reserved deep/adversarial tier) was considered and rejected: full vocabulary consistency wins over the depth nuance (the "deep" is already carried by the agent's instructions, not its suffix). Consequence: external callers of `kit:security-auditor` break , SG-08 MUST update the external skills/agents registry exposure in the same change, not just the in-repo references.

## Alternatives considered

- **Collapse all reviews into agents, drop the `-team` commands.** Rejected: the panels are genuinely multi-lens orchestrators; a command that dispatches N lenses is the right shape (ADR-0018 lead-owned convergence). The fix is naming + a stated form rule, not removing the orchestration layer.
- **Leave it; document the map only.** Rejected: the inconsistency actively misleads (a reader cannot predict a reviewer's name or form), and SG-06 was about to entrench three new suffixes. A convention that new agents must follow is the durable fix.
- **Rename everything including `task-verifier`/`doc-verifier` for total uniformity.** Rejected: those two already conform; renaming conformant names is churn for nothing (surgical-change discipline).

## Consequences

- New reviewers (SG-06's, and any future) are born under the convention , predictable name + form.
- A one-time gated rename of 3 shipped agents (SG-08), the `reviewer` one boundary-careful. `task-verifier` / `doc-verifier` untouched.
- The V-model lens (ADR-0018) gains a naming rule row, and `test-meta.sh` asserts every review-agent name matches the axis (`-reviewer` | `-verifier` | `-team` | `advisor`) so a future off-axis name FAILS CLOSED (SG-08, default-2 Han 2026-07-01). The convention is machine-enforced, not just documented.
- Cost: the rename touches ~50 unique reference sites across the 3 agents; external callers of `kit:security-auditor` break (one-axis resolved , SG-08 updates the external registry exposure too).

## Out of Scope

- Renaming non-review agents (`fix-agent`, `responding-to-review`, `research-*`, `meta-agent`) , they are not reviewers.
- The inline panel lens labels (optional, secondary , see the Decision).
- Changing WHAT any reviewer does (this is naming + form only, no behavior change).
