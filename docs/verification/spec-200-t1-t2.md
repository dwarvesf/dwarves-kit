# Proof of Done: SPEC-200 T1 + T2 (env-family unification + prefix lint)

**Feature:** one env family per resource (`BACKLOG_STAGE_*` canonical, `CC_BACKLOG_*` deprecated alias) + a lint that keeps it that way.
**Date:** 2026-07-14 · **Lane:** normal · **Host:** dev laptop (macOS 26.5) · **Spec:** `docs/specs/SPEC-200-signal-pipelines.md`

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `stats` resolves the canonical `BACKLOG_STAGE_STAGING` / `BACKLOG_STAGE_BACKLOG` | SPEC-200 T1 |
| A2 | The deprecated `CC_BACKLOG_*` names still work (no flag day) and warn on stderr | T1 migration rule |
| A3 | Canonical wins when both are set | T1 |
| A4 | Canonical resolution is silent (no spurious deprecation noise) | T1 |
| A5 | The 42 pre-existing feedback-loop assertions (which all run on the DEPRECATED names) stay green | NEGATIVE CONTROL for back-compat |
| A6 | A lint fails on any new un-grandfathered `CC_*` env var in kit code | T2 |
| A7 | A planted `CC_NEWLY_BANNED` IS flagged by that lint | NEGATIVE CONTROL |
| A8 | skill-curator speaks `SKILL_CURATOR_*` / `skill-improve`; the retired `CC_SI_*` env and `cc-improve` binary still work and warn; canonical wins when both are set | SPEC-200 I5 |
| A9 | The rename regresses nothing: all 11 skill-curator suites stay green | NEGATIVE CONTROL for the sweep |

## Implementation

| Piece | What | Where |
|---|---|---|
| Alias resolver | canonical first, legacy fallback + stderr deprecation | `lib/stats/src/stats/anomalies.py::_staging_env` |
| Paths | `staging_path()` / `backlog_path()` read through it | same file |
| Lint | `rg` sweep for `CC_*` env reads in code, allowlist = grandfathered kit names + host-provided `CC_PLUGINS_DIR` | `tests/test-config-registry.sh` |
| Registry | canonical rows added; `CC_*` rows re-labeled Deprecated alias | `lib/config/module-registry.md` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Feedback loop + env family (A1-A5) | `bash lib/stats/tests/test-feedback.sh` | `47 passed, 0 failed` (42 pre-existing on the alias + 5 new) | PASS |
| Registry lints + prefix ban (A6-A7) | `bash tests/test-config-registry.sh` | `21/21 passed` | PASS |
| I5 sweep: skill-curator renamed (A8) | `bash lib/skill-curator/tests/test-curate.sh` | `all 11 passed` (9 pre-existing + alias + canonical-wins) | PASS |
| I5 sweep: no regression (A9) | all 11 skill-curator suites | 11/11 suites green | PASS |

## Run detail

```
$ bash lib/stats/tests/test-feedback.sh | tail -7
PASS  F-env canonical BACKLOG_STAGE_STAGING resolves
PASS  F-env canonical name is silent (no deprecation)
PASS  F-env deprecated CC_BACKLOG_STAGING still works
PASS  F-env deprecated alias warns on stderr
PASS  F-env canonical wins over the alias

== 47 passed, 0 failed ==
Exit: 0

$ bash tests/test-config-registry.sh | tail -3
  PASS no un-grandfathered CC_* env var in lib/hooks/bin
  PASS NEGATIVE CONTROL: a planted CC_NEWLY_BANNED IS flagged

=== 21/21 passed ===
Exit: 0
```

The negative control earned its keep on the first run: the lint initially used
`rg -oh`, and in ripgrep `-h` is `--help`, so the sweep piped a help dump onward
and passed vacuously. The planted-var check caught it; the flag is now `-I`.

## Reproduce

```bash
cd <dwarves-kit>
bash lib/stats/tests/test-feedback.sh
bash tests/test-config-registry.sh
```
