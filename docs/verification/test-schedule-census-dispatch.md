# The test workflow guards again, and the battery's findings on the repair

Lane: normal

`/kit:battery` over a95c0f99..be1c062 (PRs #487, #488, #489, the repair of the `test` workflow after three weeks hand-disabled). Verifier: PASS on all 64 workflow steps plus the CI-shape rerun. Reviewer and advisor: FIX THEN SHIP. What landed:

| Sev | Finding | Fix |
|---|---|---|
| HIGH | the workflow lost `push` and `pull_request` on 2026-08-10, so re-enabling it made the suites runnable, not guarding | both triggers restored (public repo, hosted minutes free) |
| HIGH | the inherit fallback ("no config, no `--model`") had no live assertion once the kit-root default was pinned | a case with both config layers pointed at empty dirs asserts SG-02 dispatches with no `--model` |
| MED | the tests re-implemented the toml parse with `grep '^default_model'` | the expectation comes from `kit_config_get` itself |
| MED | `KIT_PROJECT_ROOT` was left loose, so a host repo's `.kit.toml` could flip the expectation | pinned to an empty temp dir |
| MED | the bin/ census was widened in the test alone; `activate` and `release` are standalone executables, not forwarders | ADR-0034 amended with the third class; the census proves each answers with its own contract; header count corrected |
| MED | `lib/bench/SPEC.md` named a test file that does not exist and omitted two modules | roster and table corrected |
| LOW | `tests/test-bench.sh` swallowed the failing file's output | re-run visibly on failure |
| LOW | battery recorded under the `review` phase key, so its timing landed on /kit:review's row in stats | own key `battery`; `normalize_phase` maps it to the review gate |

## Green run

| Command | Exit | Verdict |
|---|---|---|
| every `run: bash tests/...` step of `.github/workflows/test.yml`, in order | 0 each | PASS (0 red of 65) |
| `DWARVES_KIT=/nonexistent bash tests/test-orchestrate.sh` (CI shape) | 0 | PASS, including `no config layer at all -> SG-02 inherits (no --model)` |
| `bash tests/test-bin-forwarders.sh` | 0 | PASS (32, two new: activate usage line, release semver refusal) |

Recorded run
- Command: `bash tests/test-orchestrate.sh`
- Exit: 0
- Verdict: PASS

## NEGATIVE CONTROL

Targeted edit: make the orchestrator apply a hardcoded default when the config layers are empty (`model="${model:-sonnet}"` after the `kit_config_get`).

- Command: `bash tests/test-orchestrate.sh`
- Exit: 1, `FAIL inherit fallback lost: SG-02 got a --model with no config` (RED). Restored from a copy: PASS.

## Rollback

Revert the commit. The workflow returns to dispatch-only; nothing outside the repo changes.
