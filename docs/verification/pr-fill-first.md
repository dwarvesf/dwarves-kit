# Proof of done: wrap step 10 titles PRs from the feature commit

2026-09-26. Spec: `docs/specs/SPEC-323-pr-fill-first.md`. Lane: normal. Files: `commands/wrap.md`, `tests/test-wrap.sh`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
Output: test-wrap: all 1210 passed
Verdict: PASS
```

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "sed ... --fill-first -> --fill in commands/wrap.md"
Exit: 0 (green before mutation)
Exit: 1 (under mutation, RED expected)
Exit: 0 (green after restore)
Verdict: PASS
```

Before this change the pin `... --fill` also matched `--fill-first` as a substring, so the old suite stayed green against either flag.

## Test plan coverage

| Row | Run |
|---|---|
| draft pin | `chk_has` "a full-lane PR opens as a draft titled from the feature commit", green |
| BUILD/FINISH pin | `chk_has` "a follow-through PR takes the first commit title", green |
| no bare `--fill` | `chk_no` "no step-10 PR is titled by a bare --fill", green; it also caught a prose sentence during the build |
