# Proof of done: spec-validate gains a sustainability lens

2026-09-26. Spec: `docs/specs/SPEC-314-sustainability-lens.md`. Lane: normal. Files: `commands/spec-validate.md`, `tests/test-meta.sh`, `tests/fixtures/sustainability-lens/`, `README.md`, `docs/MANUAL.md`, `docs/architecture.md`, `docs/workflow-paths.md`, `docs/tiers.md`, `docs/WORKFLOW.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

Acceptance: `/kit:spec-validate` runs seven lenses. Reviewer 7 is advisory. It passes a short-lived spec in one line and asks a long-lived spec five upkeep questions. Reviewer 6 stays the only blocking reviewer.

## Green run

```
Command: bash tests/test-meta.sh; bash tests/test-design-record.sh; bash tests/test-picture-section.sh; bash tests/test-understanding-wiring.sh
Exit: 0 (each)
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output: run-all: all 49 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Structural negative control

The roster tests went red before `commands/spec-validate.md` changed: header, stale-count guard, `### Reviewer 7:` presence, and section non-empty all failed. Two mutations on the finished command, each restored with `git checkout --`:

| Mutation | Expected | Result |
|---|---|---|
| a `BLOCKING` marker inside the Reviewer 7 section | `Reviewer 7 section carries no BLOCKING marker` fails | FAIL (expected '0', got '1'), RED as designed |
| heading renamed `### Lens 7:` | `has Reviewer 7` and `section is non-empty` fail | both FAIL, RED as designed |

After restore: `test-meta` Passed 861 / 861.

## Behavioral eval (LLM, one sample per row)

Each row ran on a fresh Sonnet subagent that read only the command text and the fixture.

| Run | Command | Fixture | Run cost | Owner / liveness | Retirement | Credential rotation | Handover |
|---|---|---|---|---|---|---|---|
| Control 1 | master (6 lenses) | `long-lived-gaps.md` | no | no | no | no | no |
| Control 2 | master (6 lenses) | `long-lived-gaps.md` | yes, Reviewer 5, marked minor | no | no | no | no |
| Catch | branch (7 lenses) | `long-lived-gaps.md` | yes, R7 | yes, R7: "a missed launchd fire dies silently" | yes, R7 | yes, R7 | no |
| Quiet | branch (7 lenses) | `short-lived.md` | R7: `not long-lived: in-repo CLI flag rename covered by existing tests`, no findings | | | | |

Verdict against the spec's Test plan:

- Catch: PASS. Liveness, unbounded cost, and retirement were all named, plus credential rotation.
- Quiet: PASS. One line, zero Reviewer 7 findings.
- Negative control: PARTIAL FAIL on one dimension. Control 2 named per-email API cost under Reviewer 5. So the six-lens command can catch cost incidentally. It never caught liveness, retirement, or rotation in either run. The lens's added value is those three, plus making the cost question consistent instead of incidental.

Handover was not raised in the catch run. The fixture says nothing about logs or rebuild steps, so a stricter reviewer could have flagged it. One sample cannot show whether that is variance or a weak question.

## Limits

One LLM sample per row. The eval shows the lens can fire and can stay quiet; it does not show a hit rate.
