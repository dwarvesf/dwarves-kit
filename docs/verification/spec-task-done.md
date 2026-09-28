# Proof of done: `spec task-done` verb

2026-09-28. Spec: `docs/specs/SPEC-337-spec-task-done.md`. Lane: normal. Proof class: behavioral. Files: `lib/spec/spec-task-done.sh`, `lib/spec/spec.sh`, `tests/test-spec-task-done.sh`, `commands/execute.md`, `lib/README.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

## Green run

```
Command: bash tests/test-spec-task-done.sh
Exit: 0
Output: Passed: 35 / 35
        spec-task-done green.
Verdict: PASS
```

The same suite passes 35/35 with macOS `/bin/bash` 3.2.57 first on PATH (`PATH=/bin:/usr/bin:$PATH bash tests/test-spec-task-done.sh`). `bash tests/test-meta.sh` passes 879/879 run alone. `test-bin-forwarders` and `test-spec-index` pass.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-spec-task-done.sh" "sed -i '' 's/return c == \"\" || c == \":\" || c == \" \" || c == \"(\"/return 1/' lib/spec/spec-task-done.sh"
Exit: 0 (green before mutation)
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/spec/spec-task-done.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation drops the ID boundary check, so `TASK-1` also matches `TASK-10`. Under it the suite reads `Passed: 32 / 35`: `flip exits 0` (got 1), `flip reports the ID` (got `TASK-1 has more than one unchecked line`), and `TASK-1 checked with the done tag` fail.

## Not green, not this change

`bash tests/run-all.sh --changed` ran 45 suites. `test-no-scattered-ids` fails on two `SPEC-330` comments in `lib/gate/proof-ledger.sh`, a file this branch does not touch; it fails the same way on the base commit. `test-hooks`, `test-meta` and `test-wrap` hit the runner's 300s ceiling under parallel load; `test-meta` passes alone.

## Test plan coverage

| Row | Run |
|---|---|
| flip among several | green run, section "flips the right task among several" |
| missing ID | green run, "missing ID errors, spec unchanged" |
| already checked | green run, "already-done ID errors, spec unchanged" |
| log created | green run, "log created when absent, every field present" |
| log appended | green run, "appends to an existing log" |
| log fields missing | green run, "--verify-log without its fields errors before any write" |
| two unchecked lines for one ID | green run, "two unchecked lines for one ID error" |
| file mode | green run, "keeps the spec's file mode and leaves no temp file" |
| fence in excerpt | green run, "an excerpt holding a fence gets a longer fence" |
