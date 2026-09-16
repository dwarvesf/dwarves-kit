# Verification -- run-all default, CI on demand, verdict-first Built lines

Three changes, one ask: the wait between a change and its landing.

- `tests/run-all.sh` with no argument is `--changed`; `--all` is the full glob and the only thing CI runs.
- CI triggers are `workflow_dispatch` and a `v*` tag push. No run on push or pull request.
- Every `**Built:**` item in the wrap report opens with `BUILT`, `STAGED`, `FILED`, or `NOTE`, and `lib/wrap/report-lint.sh` fails an item without one.

## Green run

```
Command: bash tests/test-run-all-changed.sh
Exit: 0
Verdict: PASS (8/8; case 5b is new: a bare invocation picks by the diff, --all runs the whole fixture glob)
```

```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS (511/511; two new cases: a candidate with no leading verdict fails and the finding names the four verdicts, a NOTE verdict with a PROSE-ONLY reason passes; every existing passing fixture now carries a verdict)
```

The real primary flow, a bare invocation on this branch on the Air (M4, 10 cores):

```
Command: bash tests/run-all.sh
Output: run-all: --changed against 64042a7: 7 changed files -> 11 suites (5 named, the rest always-on)
        run-all: 11 suites, 4 at a time, 0 serial
        run-all: FAILED -> test-meta        (docs/FEATURES.md freshness pin: commands/wrap.md changed)
Wall clock: 61s
```

The pin is the always-on lint doing its job locally. After `feature-registry.sh generate`:

```
Command: bash tests/run-all.sh --only test-meta
Output: run-all: all 2 suites passed, 0 skipped for missing tooling
Exit: 0
Verdict: PASS
```

## Negative control

```
Command: git checkout origin/master -- lib/wrap/report-lint.sh && bash tests/test-wrap.sh; git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 1
Output: FAIL a candidate with no leading verdict fails
        FAIL the finding names the four verdicts
        test-wrap: 509 passed, 2 FAILED of 511
Verdict: RED as expected on exactly the two verdict cases, then restored (git status clean)
```

The `--changed` selector's own negative control is recorded in `run-all-changed.md` (the master runner fails 6 of 7 selector cases); the bare-invocation case 5b rides on the same mechanism.

## Not proven

- The CI trigger change has no local proof: the workflow now fires only on `workflow_dispatch` and `v*` tags, which is the behavior, and the first dispatched run is the evidence. Master can drift red unnoticed between dispatches; the 2026-08-10 note at the top of the workflow describes that failure mode, and the operator chose it with eyes open.
- The verdict rule is enforced on the report text only. A session that writes `BUILT` on a staged row lies in a way no lint reads; the rule makes the lie explicit rather than impossible.
