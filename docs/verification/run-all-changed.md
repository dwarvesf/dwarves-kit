# Verification -- run-all-changed

`tests/run-all.sh --changed [<base>]` runs only the suites the diff touches, and `RUN_ALL_JOBS` defaults to `auto` on macOS.

The full glob costs 13-15 minutes sequential on a Mac, and every in-session worker was paying that as its pre-push check (two sessions were sitting on it side by side when this was filed). Selection: a suite whose code lines name a changed file's basename, a changed suite itself, `tests/test-<mod>*.sh` for a changed `lib/<mod>/` file, plus every suite carrying an `# always:` header. Six suites carry it: kit-contract, config-registry, no-personal-paths, no-scattered-ids, boundary-lint, meta. They are the tree-wide lints that fail on a file you ADDED while naming no file you touched, so no diff-derived pick can reach them.

## Green run

```
Command: bash tests/test-run-all-changed.sh
Exit: 0
Verdict: PASS (7/7: named pick, always-on pick with the unnamed file listed, changed suite picks itself, lib/<mod> pick, empty diff runs everything, explicit base, a red always-on lint fails the run)
```

The real primary flow, end to end, on this branch at c0d2918 on the Air (M4, 10 cores, `RUN_ALL_JOBS` unset so the macOS default applied):

```
Command: bash tests/run-all.sh --changed
Output: run-all: --changed against 2ca7966: 11 changed files -> 11 suites (11 named, the rest always-on)
        run-all: 11 suites, 4 at a time, 0 serial
        run-all: all 11 suites passed, 0 skipped for missing tooling
Exit: 0
Wall clock: 124s
Verdict: PASS
```

The always-on floor, each lint alone on the same machine: kit-contract 4s, config-registry 47s, no-personal-paths 11s, no-scattered-ids 4s, boundary-lint 6s; test-meta about 140s and the bound of any `--changed` run.

## Negative control

```
Command: git checkout origin/master -- tests/run-all.sh && bash tests/test-run-all-changed.sh; git checkout HEAD -- tests/run-all.sh
Exit: 1
Output: test-run-all-changed: 1 passed, 6 FAILED
Verdict: RED as expected, then restored (git status clean)
```

With the master runner, `--changed` is an unknown argument, so every fixture run executes the whole glob: the six cases that assert a suite was NOT run go red, and only the empty-diff case (which expects the whole glob) stays green.

## The first dogfood run, and what it changed

The first cut matched comments too and ran 7 suites in 420s: `test-orchestrate-wavefront` was picked because its header comment mentions `run-all.sh`, and it hit the 300s ceiling under the load of two other sessions' full runs. Matching now reads code lines only; the second run above did not pick it. The same first run also went red on `test-meta`'s registry freshness pin, because the new test file changed what the registry scans, which is the exact failure class the `# always:` pin exists to surface locally rather than in CI.

## Not proven

- The ubuntu-only parallel flake (#647) is untouched. Linux keeps `RUN_ALL_JOBS=1` by default; macOS gets `auto` on the evidence that every parallel run there has been green, and this branch's two parallel runs add to it.
- CI still runs the full glob; `--changed` is a local check and nothing in the workflow calls it.
- A suite that reaches a changed file only through a helper it sources (no basename in its own code lines) is not picked. None found by hand; the always-on lints do not depend on it.
