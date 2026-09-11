# Verification: engine-learn-seam (SG-01, learning-boundary)

Spec: `docs/specs/SPEC-285-engine-learn-seam.md`. Branch `feat/engine-learn-seam`. Commits: `dfe094e` (seam + boundary lint), `093e316` (learn -> reflect rename).

## Run table

```
$ bash tests/run-all.sh
...
run-all: FAILED -> test-no-personal-paths test-orchestrate-gate-dispatch test-orchestrate-wavefront
run-all: 133 suites run, 1 skipped for missing tooling
```

Three failures, all confirmed pre-existing and unrelated to this branch:

- `test-no-personal-paths`: flags `_meta/megagoals/learning-boundary/POINTER_PROMPT.md`, a file this branch does not touch (`git diff origin/master -- _meta/megagoals/learning-boundary/POINTER_PROMPT.md` is empty). It was written by the already-merged SG-00 ADR PR (#556).
- `test-orchestrate-gate-dispatch`: a git-fixture setup issue ("no such megagoal dir") in an unrelated mega-orchestration test; zero references to `learn`/`reflect`, and this branch touches none of `lib/mega/`, `lib/queue/`, `hooks/backlog-stage.sh` (only `lib/mega/mega-review.py`'s two-line path fix, unrelated to this test's fixture).
- `test-orchestrate-wavefront`: a concurrency-timing test; reproduced on a clean `origin/master` scratch checkout with the same class of failure (`wave_run` mock-session timing), confirming it is a pre-existing flake on this machine, not a regression.

Everything else, including every suite this branch touches, is green:

```
$ bash bin/config seams
KEY                            KIND       VALUE                          STATUS          FILLED-BY
wrap.before                    skill      (empty)                        default         the operator, for a skill that must read the pre-landing working tree
wrap.after                     skill      (empty)                        default         learning-kit concept flush, or the operator
wrap.activity_log              file       (empty)                        default         operator
precedent.registry             file       (empty)                        default         operator
knowledge.root                 dir        (empty)                        default         context-kit
PROSE_RAG_BIN                  binary     (not on PATH)                  absent          context-kit
understand.teach               skill      (empty)                        default         learning-kit understand lane, or the operator
```

(run against a fixture `KIT_CONFIG_OPERATOR` pointing at a nonexistent path and a scrubbed `PATH`, so no operator path lands in this doc; `understand.teach` resolves exactly like `wrap.before`.)

```
$ bash bin/learn propose --help
bin/learn: deprecated, use 'bin/reflect <verb>' instead
usage: reflect propose [-h] [--days DAYS | --megas MEGAS] [--staging STAGING]
                       [--backlog BACKLOG] [--dry-run]
                       [--aggregate-file AGGREGATE_FILE] [--retro FILE]
```

Deprecation line first, then the real (renamed) usage, same exit code path as `bin/reflect`.

```
$ bash lib/gate/boundary-lint.sh
boundary-lint: PASS
```

## Negative control (negctl)

Command: bash tests/test-boundary-lint.sh
Exit: 0 (green before mutation)
Mutation: printf '\n# see the learning-ledger skill for prior art\n' >> lib/reflect/weekend-batch.sh
Changed: lib/reflect/weekend-batch.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/reflect/weekend-batch.sh
Exit: 0 (green after restore)
Verdict: PASS

## Individually re-verified suites (touched by this branch)

`test-quiz-gate.sh`, `test-boundary-lint.sh`, `test-bin-forwarders.sh`, `test-kit-contract.sh`, `test-config-seams.sh`, `test-config-registry.sh`, `test-meta.sh`, `test-understanding-wiring.sh`, `test-weekend-batch.sh`, `test-reflect-propose.sh`, `test-reflect-drain.sh`, `test-reflect-propose-precision.sh`, `test-staging-stage.sh`, `test-reserved-config-guard.sh`, `test-self-grill-watcher.sh`, `test-wrap.sh`, `test-mega-review.sh`, `test-explain.sh`, `test-kit-weekly.sh`, `lib/session/audit/tests/smoke.sh`, `lib/session/intel/tests/smoke.sh` -- all green individually, re-run after each fix.

## Real regressions found and fixed during this build (not pre-existing)

The `learn` -> `reflect` directory rename broke five hardcoded path constructions the initial grep sweep missed because they live in extensionless executables (`--include='*.py'`/`--include='*.sh'` skips them, a real gap in the sweep method, not in the house convention that these executables carry no extension):

- `lib/wrap/wrap.sh` (`STAGING_FORMAT_PY`) -- broke every `bin/wrap stage` call; caught by `test-wrap.sh` (12 failures).
- `hooks/intake-sweep.py`, `hooks/backlog-stage.py`, `lib/session/audit/bin/session-audit`, `lib/session/intel/bin/session-intel` (all `_staging_format()`/equivalent loaders) -- broke session-audit/session-intel triage and the intake sweep; caught by `lib/session/audit/tests/smoke.sh` (8 failures) and a manual run of `lib/session/intel/tests/smoke.sh`.
- `lib/stats/src/stats/anomalies.py` (`stage_proposals`'s loader) -- would have broken `stats anomalies --propose`; not caught by any test in `tests/run-all.sh`'s scope (lib/stats has its own `uv`-based suite this repo's `run-all.sh` does not run), found by the manual sweep, not a test failure.

All five fixed; `test-wrap.sh` and both smoke suites re-verified green after the fix.
