# Sub-goal 02: review-function naming convention + legacy rename

**Merge policy:** auto , mechanical rename + a test-meta enforcement rule, machine-verifiable.
**Time budget:** 2-3 hours (the `reviewer` rename is the careful part).
**Proof:** run-table , rename map applied (3 agents) · test-meta rejects a non-conforming review-function name · full-repo reference grep clean · external registry exposure updated. Plus a green `test-meta.sh` row.
**Depends on:** none. Lands EARLY so 03/04's new agents are born under the convention.
Model: sonnet
Effort: medium
**Branch:** feat/kit-harden-02-naming
**PR base:** mega/kit-hardening

## Outcome

Every review-function name follows the ADR-0029 role axis (`<x>-reviewer` left-static · `<x>-verifier` right-dynamic · `<x>-team` panel command · `advisor` generic), and `test-meta.sh` MACHINE-ENFORCES it so any future review agent is born conforming. The three legacy names are renamed: `integration-checker -> integration-verifier`, `reviewer -> code-reviewer`, `security-auditor -> security-reviewer`, including the external `kit:*` registry exposure.

## Quality bar

The `reviewer -> code-reviewer` rename is NOT a blind sed (81 files, collides with the English word "reviewer"): rename the frontmatter `name:` + dispatch call-sites by word boundary only, leave prose "reviewer" untouched. `integration-checker` (31 files, clean token) is a mechanical sed. `security-auditor` (19 files) MUST also update the external harness registry + any caller. Zero dangling references after; the kit still dispatches every renamed agent.

## How to close the loop

Apply the ADR-0029 rename map + add the test-meta enforcement rule. Verify:

```
cd dwarves-kit && bash tests/test-meta.sh
rg -n 'integration-checker|security-auditor' --glob '!docs/decisions/0029*' --glob '!CHANGELOG.md'   # expect: no live refs
rg -n "name: *reviewer\b" agents/   # expect: none (now code-reviewer)
```

Captured evidence: run-table at `dwarves-kit/docs/verification/review-naming.md` with the rename-count per agent, the test-meta enforcement assertion (feed it a bad name, expect reject), and the clean-grep row.

**Done =** `test-meta.sh` green with the new name-convention rule active, all three agents renamed with zero live dangling references, and the external `kit:security-auditor` registry exposure updated to `security-reviewer`.

**Kit-adopted repo? Record the gates.** Run `bash lib/lane-classify.sh classify "rename 3 review agents + machine-enforce naming convention in test-meta"`, then record build + review gates via `lib/gate-ledger.sh` before the PR push (see 01 for the pattern).

## Handoff on completion

1. Flip 02's box, record PR # + SHA.
2. HOT `HANDOFF.md`: next is 03-generic-advisor (or 04 if 03 blocked); first action = draft the `advisor` agent via `/kit:draft-agent`, then gate it through the 01 effectiveness validator. Pointer: ADR-0028 P5/P6.
3. WARM `DECISIONS.md`: the naming convention is now test-meta-enforced; every new review agent in 03/04 uses the role axis (`advisor`, `brief-reviewer`, `acceptance-verifier`, `recheck-verifier`, `system-verifier`).
4. Report IN records, EXIT.

## Scope edges

**In:** the 3 agent renames, `test-meta.sh` convention rule, call-sites, external `kit:*` registry exposure, CHANGELOG.
**Out:** the unbuilt SG-06 agents (04 creates them, already conforming); the inline panel lenses inside `devs-team`/`spec-validate`/`visual-team` (label alignment is OPTIONAL/secondary, not this sub-goal).
**Not:** renaming `task-verifier` / `doc-verifier` (they already conform); rewriting prose uses of the word "reviewer".

## Where to look

`agents/` (the 3 files + frontmatter `name:`), `tests/test-meta.sh` (add the convention assertion), dispatch call-sites in `commands/` + `lib/`, the external registry exposure (skills/agents manifest), ADR-0029 rename-map table.

## PR body

Renames the 3 legacy review agents to the ADR-0029 role-axis convention (`integration-verifier` / `code-reviewer` / `security-reviewer`) and machine-enforces the convention in `test-meta.sh` (kit-hardening SG-08). New review agents are now born conforming.

Verify: `bash tests/test-meta.sh` + the dangling-reference greps in the proof. Proof: `docs/verification/review-naming.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. Targets `mega/kit-hardening`.

## Notes

<empty>
