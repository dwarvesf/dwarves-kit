# Proof of done: review-function naming migration (SPEC-090, ADR-0029, kit-hardening SG-02)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | Rename map applied (3 agents) | `git mv` of all three; frontmatter `name:` + live dispatch call-sites updated | PASS |
| AC2 | test-meta rejects a non-conforming review-function name | new ADR-0029 block: global retired-suffix ban + positive axis check + 3 negative controls | PASS |
| AC3 | Full-repo live-surface reference grep clean | 4 negative-control greps over agents/commands/lib/tests + canonical docs print nothing (bar the exempt external citation) | PASS |
| AC4 | External `kit:*` registry exposure updated | agent files renamed (plugin auto-prefixes `kit:<name>`); zero `kit:security-auditor`/`kit:reviewer`/`kit:integration-checker` refs remain | PASS |

## Implementation

- Renames (history preserved via `git mv`): `integration-checker -> integration-verifier`, `security-auditor -> security-reviewer`, `reviewer -> code-reviewer` (word-boundary only; prose "reviewer" untouched).
- `tests/test-meta.sh`: new ADR-0029 enforcement block -- (a) global ban on retired review suffixes (`-checker`/`-auditor`/bare `reviewer`/`-validate`), (b) positive axis check over the review-agent set (`-reviewer`/`-verifier`/`-team` or the named-noun validators `advisor`/`agent-effectiveness`), (c) three negative controls.
- Scope: live dispatch surface (agents/, commands/, lib/, tests/, MANUAL.md, README.md, docs/architecture.md, WORKFLOW.md). Historical records (CHANGELOG, ADRs, past SPECs, retros) keep old names as history, per ADR-0029's exemption.
- `docs/specs/SPEC-090-review-function-naming.md` (VALIDATED, normal lane), `docs/implementation-notes/review-function-naming.md`.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-meta.sh` | 0 | 536/536 passed (incl. the new ADR-0029 block) |
| `bash tests/test-review-team-plants.sh` | 0 | 8/8 passed (updated agent-file refs) |
| `bash tests/test-agent-effectiveness.sh` | 0 | 24/24 (SG-01 validator still green after rename) |
| `bash tests/test-hooks.sh` | 0 | 438/438 passed |

## NEGATIVE CONTROL (the load-bearing proof of the enforcement rule)

The enforcement rule is proven to REJECT, not just rubber-stamp:

```
PASS negative control: is_retired_suffix REJECTS foo-checker/foo-auditor/reviewer/foo-validate
PASS negative control: is_retired_suffix does NOT flag conforming names (no false positives)
PASS negative control: is_on_review_axis REJECTS off-axis fake names
PASS review agent 'agent-effectiveness' is on the naming axis (reviewer|verifier|team|named-noun)
```

## Run detail (live-surface negative-control greps -- all empty = clean)

```
grep -rwn 'integration-checker' agents/ commands/ lib/ tests/ MANUAL.md README.md docs/architecture.md WORKFLOW.md
  -> only agents/integration-verifier.md:106 (Source: citation to the EXTERNAL GSD file
     `gsd-integration-checker.md` + historical SPEC-021 filename; real files, not dispatch refs; exempt)
grep -rwn 'security-auditor'  ... -> (empty)
grep -rn  'name: *reviewer$' agents/  -> (empty)
grep -rwn 'kit:reviewer|kit:security-auditor|kit:integration-checker' ... -> (empty)
```

## Reproduce

```
cd dwarves-kit
bash tests/test-meta.sh                  # 536/536, exit 0
bash tests/test-review-team-plants.sh    # 8/8, exit 0
grep -rwn 'security-auditor' agents/ commands/ lib/ tests/ MANUAL.md README.md docs/architecture.md WORKFLOW.md   # empty
```
