# SPEC-090: Review-function naming migration (SG-08)

Status: VALIDATED
Date: 2026-07-02
Lane: normal
Type: refactor
Relates-to: ADR-0029 (review-function naming and form convention), ADR-0018 (V-model phase frame), ADR-0005 (read-only verifier pattern), ADR-0015 (integration-checker), ADR-0028 (autonomous-loop hardening, SG-08)
Board: kit-hardening mega-goal SG-02 (ops-toolkit `_meta/megagoals/kit-hardening`)

## Problem

Three shipped review agents wore names off the ADR-0029 convention: `integration-checker` (retired `-checker` suffix), `security-auditor` (retired `-auditor` suffix), and bare `reviewer` (collides with the naming axis, which reserves `-reviewer` as a per-artifact suffix, not a standalone noun). ADR-0029 fixed the target convention (`-reviewer` = static/left-arm, `-verifier` = dynamic/right-arm, `-team` = panel command, plus the `advisor`/`agent-effectiveness` named-noun exceptions) and its rename map, but the migration itself, and a machine gate that stops a FUTURE off-axis name from landing silently, had not been executed.

## Decision

Execute ADR-0029's rename map on the live dispatch surface (`agents/`, `commands/`, `lib/`, `tests/`, and the canonical live docs `MANUAL.md`/`README.md`/`docs/architecture.md`/`WORKFLOW.md`), word-boundary-careful on `reviewer` (it collides with ordinary English prose), and add a machine-enforced test-meta.sh block that bans the retired suffixes on any future agent `name:` and asserts the current review-agent roster is on-axis. Historical records (`CHANGELOG.md`, `docs/decisions/`, `docs/specs/`, `docs/implementation-notes/`, `docs/retro/`, `docs/research/`) keep the old names; they are the record of what shipped under the old convention, not live references.

Rename map applied:
- `integration-checker` -> `integration-verifier` (clean token, mechanical)
- `security-auditor` -> `security-reviewer` (also updates the external `kit:security-auditor` exposure, which is just the agent filename the plugin auto-prefixes)
- `reviewer` -> `code-reviewer` (word-boundary only: frontmatter `name:`, the file, and dispatch call-sites that name the agent; prose uses of "reviewer" are untouched)

## Acceptance criteria

- AC1: the 3 agent files are renamed via `git mv` (history preserved) with matching frontmatter `name:` updates.
- AC2: `MANUAL.md` and `docs/architecture.md` roster rows reflect the 3 new names; `test-meta.sh`'s MANUAL-vs-`agents/` cross-ref check is green.
- AC3 [negative control]: `test-meta.sh`'s new ADR-0029 enforcement block rejects a fake retired-suffix name (`foo-checker`, `foo-auditor`, bare `reviewer`, `foo-validate`) via a pure-function check, without adding a real bad agent to `agents/`.
- AC4: a clean grep for the 3 old names over the live dispatch surface (`agents/ commands/ lib/ tests/ MANUAL.md README.md docs/architecture.md WORKFLOW.md`) returns zero hits, except for legitimate historical/external citations (an external-repo source filename, or a citation of our own exempt `docs/specs/` filename) which are documented, not silently left.
- AC5: `tests/test-review-team-plants.sh` (the security-lens vocabulary regression guard) is updated to the new agent filenames and stays green.
- AC6: `tests/test-hooks.sh` stays green (no regression from the rename).

## Tasks

- T1: `git mv` the 3 agent files; update frontmatter `name:` in each.
- T2: update cross-agent self-references (`agents/agent-effectiveness.md`, `agents/doc-verifier.md`, `agents/meta-agent.md`, `agents/code-reviewer.md`'s own security-lens pointer).
- T3: update `commands/execute.md`, `commands/verify.md`, `commands/review-team.md`, `commands/devs-team.md` dispatch call-sites.
- T4: update `tests/test-meta.sh` (mechanical `integration-checker` -> `integration-verifier`, incl. the section-header comment) and `tests/test-agent-effectiveness.sh` roster list.
- T5: update `tests/test-review-team-plants.sh` to read `security-reviewer.md` / `code-reviewer.md`.
- T6: roster-sync `MANUAL.md` + `docs/architecture.md` (table rows + prose cross-refs) and `README.md`.
- T7: add the ADR-0029 enforcement block to `tests/test-meta.sh`: (a) global ban on retired suffixes in any `agents/*.md` `name:`, (b) positive-axis assertion over the current review-agent set, (c) a negative-control pure-function proof that the ban logic discriminates.
- T8: run the verification suite; leave historical docs (`docs/decisions/0029-*.md`, `docs/specs/SPEC-021-integration-checker.md`, `docs/specs/SPEC-022-doc-verifier.md`, `CHANGELOG.md`) untouched.

## Verification

```
bash tests/test-meta.sh                # roster cross-refs + the new ADR-0029 enforcement block, green
bash tests/test-review-team-plants.sh  # security-lens vocabulary guard against the renamed agent files, green
bash tests/test-hooks.sh               # no regression, green

# negative-control greps over the LIVE surface -- must print nothing (or only the
# documented historical/external citation in agents/integration-verifier.md:106):
grep -rwn 'integration-checker' agents/ commands/ lib/ tests/ MANUAL.md README.md docs/architecture.md WORKFLOW.md
grep -rwn 'security-auditor' agents/ commands/ lib/ tests/ MANUAL.md README.md docs/architecture.md WORKFLOW.md
grep -rn 'name: *reviewer$' agents/
grep -rwn 'kit:reviewer\|kit:security-auditor\|kit:integration-checker' agents/ commands/ lib/ tests/ MANUAL.md README.md docs/architecture.md WORKFLOW.md
```

Proof-of-done: a table-first run-table (ADR-0026) with the 3 test-suite results, the 4 negative-control grep outputs, and the per-file rename/reference-update count.

## Out of Scope

- Renaming non-review agents (`fix-agent`, `responding-to-review`, `research-*`, `meta-agent`) , not reviewers (per ADR-0029).
- The inline panel lens labels inside `devs-team` / `spec-validate` / `visual-team` (optional, secondary per ADR-0029).
- Building the SG-06 (unbuilt) agents from the ADR-0029 rename map (`acceptance-verifier`, `recheck-verifier`, `system-verifier`) , those are born on-axis, no migration needed.
- Editing historical records (`CHANGELOG.md`, `docs/decisions/`, `docs/specs/`, `docs/implementation-notes/`, `docs/retro/`, `docs/research/`) , they record what shipped under the old convention.
