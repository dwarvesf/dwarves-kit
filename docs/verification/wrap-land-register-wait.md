# Verification -- wrap-land-register-wait

`wrap land` merged dwarvesf/share#47 before its `pull_request` CI run existed. The register hold was 30s; GitHub queued the run 190s after the PR opened.

Root cause evidence (gh, share#47): PR created 14:19:40Z, merged 14:20:19Z (39s). The `pull_request` run 37478462017 was created 14:22:50Z (3m10s after open, 2m31s after the merge) and its checks started 14:23:26Z. The workflow trigger was detected correctly; the gate armed and gave up after `KIT_WRAP_LAND_GRACE_SECS` (30).

Lane: bug. Files: `lib/wrap/wrap-land.sh`, `tests/test-wrap-land.sh`, `lib/config/module-registry.md`, `commands/wrap.md`, `docs/CHANGELOG.md`.

## Green run
```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output: test-wrap-land: all 578 passed
Verdict: PASS
```

| Case | Proves |
|---|---|
| PG4d | rollup empty for 20 reads (200s), red on read 21, unfiltered workflow: exit 2, no `pr merge` (the share#47 shape) |
| PG4e | `paths:`-filtered workflow that starts nothing: at most 5 rollup reads, merges |
| PG4f | unfiltered workflow, nothing ever registers: prints `no checks registered on #42 after`, then merges as before |

`bash tests/run-all.sh` ran 26 suites, all ok except `test-config-registry`, which fails the same way on unmodified master (`ORPHAN: DWARVES_BOARD_CONFIG`, `DWARVES_HERMES_LINKS`, board knobs unrelated to this change).

## Negative control
```
Command: bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: git show origin/master:lib/wrap/wrap-land.sh >| lib/wrap/wrap-land.sh
Changed: lib/wrap/wrap-land.sh
Exit: 1 (under mutation, RED expected)
Output: test-wrap-land: 574 passed, 4 FAILED of 578 (PG4d x3, PG4f x1)
Restore: git checkout HEAD -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven
- No live GitHub run; `gh` is stubbed, so real registration latency is taken from the share#47 timestamps above.
- The unfiltered test is a grep for `paths:`/`paths-ignore:`/`labeled` in the workflow file. A `paths:` under `push:` reads as a PR filter (short grace, the old behaviour).
- An unfiltered workflow that truly starts nothing (a `[skip ci]` head) now waits 300s once, then says so and merges.
