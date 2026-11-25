# Verification -- sync-adapters

The Hermes, Notion, Reminders, Multica and GitHub connectors moved out of core `lib/board` and `lib/sync` into `lib/adapters/<name>/`, behind one manifest and one interface. Core names no app. The proof below shows (1) the four purity greps, (2) every suite the change touches, run alone and in order after the last fix and the master merge, (3) the golden capture holding with only the closed list of output deltas, (4) negative controls, and (5) what was not run.

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Purity: no app word in core | four `git grep -il <app> -- lib/board lib/sync` | all four print nothing; count 0 | PASS |
| 2 | Golden characterization | `bash tests/test-sync-characterize.sh` | 13 passed, 0 failed | PASS |
| 3 | Adapter module suite | `bash lib/adapters/tests/test-adapters.sh` | 218 passed, 0 failed | PASS |
| 4 | Sync pytest roots | `bash tests/test-sync.sh` | 418 passed | PASS |
| 5 | Core purity suite | `bash tests/test-core-purity.sh` | 12 passed, 0 failed | PASS |
| 6 | Sweep suites (five) | `bash tests/test-board-sweep*.sh`, one at a time | 113, 66, 20, 32 passed, verify 29 ok, 0 failed | PASS |
| 7 | Dispatch | `bash tests/test-sync-dispatch.sh` | 20/20 passed | PASS |
| 8 | Board, mirror, states, hermes, writeback, cleanup, expire | seven suites, one at a time | all 0 failed | PASS |
| 9 | Health and brief | `bash tests/test-board-health.sh`, `bash tests/test-board-brief.sh` | 102 passed; 260 passed | PASS |
| 10 | Config registry, kit contract, state-check | three suites | 60/60; 25 passed; 124 of 124 | PASS |
| 11 | Meta | `bash tests/test-meta.sh` | 943 / 943 | PASS |
| 12 | Personal paths and boundary | `bash tests/test-no-personal-paths.sh`, `bash lib/gate/boundary-lint.sh` | 3 / 3 passed; lint reports one hit in a file this change does not own (see below) | PASS with note |
| 13 | No test lost | `comm` of test names, master against branch | 0 missing; 273 before, 331 after | PASS |
| 14 | Negative controls | see NEGATIVE CONTROLS | each goes red, restored | PASS |

Run on the branch after merging `origin/master` (and `origin/feat/state-check-engine`, already contained), after the six review fixes. Each suite ran alone, in the foreground, one after another.

## Purity greps
```
Command: git grep -il hermes -- lib/board lib/sync ; git grep -il notion -- ... ; git grep -il reminders -- ... ; git grep -il multica -- ...
Exit: 0
Output:
  git grep -il hermes -- lib/board lib/sync => []
  git grep -il notion -- lib/board lib/sync => []
  git grep -il reminders -- lib/board lib/sync => []
  git grep -il multica -- lib/board lib/sync => []
  git ls-files lib/sync/sources => []
  git grep -ilE 'hermes|notion|reminders|multica' -- lib/board lib/sync | wc -l => 0
Verdict: PASS
```

## Suite result lines
```
Command: each suite below, alone, in this order (tail of its output)
Exit: 0 for every suite
Output:
  tests/test-sync-characterize.sh      === 13 passed, 0 failed ===
  lib/adapters/tests/test-adapters.sh  === 218 passed, 0 failed ===
  tests/test-sync.sh                   418 passed in 2.86s
  tests/test-core-purity.sh            === 12 passed, 0 failed ===
  tests/test-board-sweep.sh            PASS=113 FAIL=0
  tests/test-board-sweep-mirror.sh     PASS=66 FAIL=0
  tests/test-board-sweep-expire.sh     TOTAL: 20   PASS: 20   FAIL: 0
  tests/test-board-sweep-post.sh       PASS=32 FAIL=0
  tests/test-board-sweep-verify.sh     29 "ok" lines, 0 fail lines (the suite prints no total)
  tests/test-sync-dispatch.sh          === 20/20 passed ===
  tests/test-board.sh                  TOTAL: 63   PASS: 62   FAIL: 0   SKIP: 1
  tests/test-board-mirror.sh           TOTAL: 116   PASS: 116   FAIL: 0   SKIP: 0
  tests/test-board-states.sh           All board-states tests passed.
  tests/test-board-hermes.sh           board-hermes: 79 passed, 0 failed
  tests/test-board-writeback.sh        TOTAL: 75   PASS: 74   FAIL: 0   SKIP: 1
  tests/test-board-mirror-cleanup.sh   TOTAL: 31   PASS: 31   FAIL: 0
  tests/test-board-mirror-expire.sh    TOTAL: 31   PASS: 31   FAIL: 0
  tests/test-board-health.sh           board-health: 102 passed, 0 failed
  tests/test-board-brief.sh            board-brief: 260 passed, 0 failed
  tests/test-config-registry.sh        === 60/60 passed ===
  tests/test-kit-contract.sh           === kit-contract: 25 passed, 0 failed ===
  tests/test-state-check.sh            == 124 run, 124 passed, 0 failed ==
  tests/test-meta.sh                   Passed: 943 / 943
  tests/test-no-personal-paths.sh      Passed: 3 / 3
Verdict: PASS
```

```
Command: bash bin/board sweep --help | grep -E -e 'Usage: board sweep' -e '--expire-kinds-file' -e '--mirror-hermes-home' -e '--mirror-snapshot'
Exit: 0
Output:
  Usage: board sweep --registry F [options]
    --mirror-hermes-home VALUE  turn the mirror leg on, against the Hermes kanban store at D
    --mirror-snapshot VALUE  mirror snapshot (default <repo-root>/_meta/.board-mirror-snapshot.jsonl)
    --expire-kinds-file VALUE  turn the expiry leg on (needs --mirror-hermes-home): archives the cards the rule list's expire blocks name (a social card in triage for 14 days), once per tick; --dry-run only reports. Observational like the mirror.
Verdict: PASS
```

## Golden delta against the closed list
The golden capture was taken on the untouched tree, then rebased once onto the state-check lines (nine added lines, no other change). Against that rebased golden, the final golden differs in 13 hunks (three lines of context), all in four sections. `tests/fixtures/sync-characterize/deltas.txt` holds 17 `<section><TAB><tag>` rows, and the suite checks every row's tag is in the closed list of eight and every section exists. It does not match hunks to rows one for one: a hunk can carry two rows.

| Section | Hunks | Rows in deltas.txt | Tags |
|---|---|---|---|
| 1-sync-argv | 1 | 2 | apps-hint x2 |
| 3-engine-dry-run | 2 | 2 | describe-line, unknown-app |
| 4-sweep | 3 | 4 | sweep-help x4 |
| 7-help-errors | 7 | 10 | board-help x7, apps-default, unknown-app, sweep-unknown-arg |
| 2, 5, 6 and the rest | 0 | 0 | none |

Seven of the eight tags are used; `health-brief-help` is unused. No tag outside the list exists. The six review fixes changed no golden line: the `mirror-hermes-home` help text keeps its `D` beside the `VALUE` placeholder, because both are in the golden byte for byte from master.

```
Command: bash tests/test-sync-characterize.sh   (tail)
Exit: 0
Output:
    PASS deltas.txt rows are in the closed list
  === 13 passed, 0 failed ===
Verdict: PASS
```

## NEGATIVE CONTROLS
Each control was run, shown red, and restored. The ones from the build phases come from `docs/implementation-notes/sync-adapters.md`; the first three are from the finishing step.

| Control | Failing line |
|---|---|
| Review fix 1: adapter directory appended to the end of `sys.path` again, sibling-origin check removed | `AssertionError: assert 'decoy' == 'own'` (twice); `FAILED lib/sync/tests/test_adapters.py::test_a_sibling_stem_that_resolves_to_a_core_module_is_refused`; `3 failed, 30 passed` |
| Review fix 2: the unknown row kind warning removed from the bash reader | `FAIL the bash reader gives the same unknown row kind warning as the loader (bash) (want 'adapters: <tmp>/unknown/a/adapter.tsv:1: unknown row kind 'mystery' (ignored)', got '')`; `=== 216 passed, 2 failed ===` |
| Review fix 3: `priority` dropped from `CORE_VERBS` | `FAIL CORE_VERBS equals the main() labels and the backlog.sh verbs (minus the adapter verbs) (want '... normalize priority promote ...'`; `=== 217 passed, 1 failed ===` |
| Guards run for every adapter (`only=names` dropped) | `FAILED test_a_guard_checks_only_runs_that_name_one_of_its_apps` |
| Mode check removed | `FAILED test_a_manifest_mode_must_match_the_source_object` |
| Unknown-app exit disabled | `FAILED test_unknown_app_exits_before_the_lock_and_syncs_nothing` |
| Secret copied into argv (sync) | `FAIL a secret row reaches the engine by environment only, never argv` |
| Multica token leaked after the export | `FAIL with the operator ref MULTICA_TOKEN reaches the engine by environment, never argv` |
| `target.exists()` check dropped in the legacy state copy | `FAILED lib/adapters/tests/test_conformance.py::test_legacy_reminders_state_is_copied_once_and_only_when_named` (379 passed, 1 failed) |
| GitHub adapter `cwd=None` | `FAILED ...::test_github_takes_its_repo_from_the_flag_and_its_cwd_from_the_project_root` (383 passed, 1 failed) |
| `const` row removed from the Reminders manifest | `FAILED ...::test_the_reminders_adapter_supplies_the_intake_heading`, `FAILED ...::test_an_existing_reminders_section_keeps_receiving_rows` (389 passed, 2 failed) |
| Root-only config scan, `multica_url` scope changed to `-` | `FAIL declared root-only keys == actual kit_config_get_root call sites` |
| Notion `hook guard` row removed | four FAILED in `test_notion_taskboard_pull.py` |
| Notion `hook body_expander` row removed | four FAILED in `test_body_expander.py` |
| Hermes adapter `assignee=None` | `FAILED ...::test_build_source_hands_every_hermes_flag_to_the_source` |
| Sweep: `leg_fallback_record` disabled | `FAIL health state: {` (`PASS=76 FAIL=1`) |
| Sweep: no missing-script check | 5 FAILED (`exit 0`, `no failed line`, `order`, `health state`, `on-clean ran after a missing leg`) |
| Sweep: no INT and TERM traps | `TERM: the leg never saw TERM`, `TERM: the leg is still running`, `INT: exit 129 (want 130)` |
| Sweep: handler does not wait | `the leg is still running` for both signals |
| Sweep: cleanup lines of `mirror.sh` neutered | `TERM: a stray origin copy`, `INT: a stray origin copy` |
| Sweep: manifest error check removed | `FAIL [--fx-flag v] exit 64` |
| Sweep: leg started through PATH `bash` | `FAIL a leg was started through PATH bash` |
| Brief: `const mirror-label` dropped | 5 FAILED in the brief suite, 2 in the health suite |
| Brief: `hook brief_decisions` dropped | `FAIL dated ... stale skills`, `FAIL the lede counts all ten` |
| Brief: `except` narrowed | `FAIL providers that raise, fail to import or lack the function: the brief still exits 0 (got '1', want '0')` |
| Bridge: plain `pwd` instead of `pwd -P` | the extension-directory case fails |
| Core purity scanner: a planted file naming an app, and a file named `notion_named.sh` | both reported (`PASS negative control: a file named notion_named.sh is reported`) |

## Test plan coverage
The matrix has no numeric `#` column, so `Row` is the ordinal, top to bottom: rows 1 to 13 are the baseline suites in the spec's order, rows 14 to 25 are T0 to T11.

| Row | Run / skip reason |
|---|---|
| 1 | sync python: `bash tests/test-sync.sh`, 418 passed (baseline 326) |
| 2 | sync dispatch: `bash tests/test-sync-dispatch.sh`, 20/20 (baseline 10) |
| 3 | board states: `bash tests/test-board-states.sh`, all pass |
| 4 | hermes link: `bash tests/test-board-hermes.sh`, 79 passed |
| 5 | mirror: `bash tests/test-board-mirror.sh`, 116 of 116 |
| 6 | writeback: `bash tests/test-board-writeback.sh`, 74 passed, 1 skip |
| 7 | mirror cleanup: `bash tests/test-board-mirror-cleanup.sh`, 31 of 31 |
| 8 | mirror expire: `bash tests/test-board-mirror-expire.sh`, 31 of 31 |
| 9 | sweep: `bash tests/test-board-sweep.sh`, PASS=113 (baseline 55) |
| 10 | sweep mirror: `bash tests/test-board-sweep-mirror.sh`, PASS=66 (baseline 43) |
| 11 | sweep expire: `bash tests/test-board-sweep-expire.sh`, 20 of 20 (baseline 14) |
| 12 | health: `bash tests/test-board-health.sh`, 102 passed (baseline 97) |
| 13 | brief: `bash tests/test-board-brief.sh`, 260 passed (baseline 243) |
| 14 | T0 characterization: `bash tests/test-sync-characterize.sh`, 13 passed; the `--hermes-home` mutation control is in the build notes |
| 15 | T1 core purity: `bash tests/test-core-purity.sh`, 12 passed, with the planted-file control |
| 16 | T2 no adapter configured: cases in `lib/adapters/tests/test-adapters.sh` (218 passed) and the sweep suites |
| 17 | T3 frozen surface: `lib/adapters/tests/test-adapters.sh`, the frozen-list equality cases and their controls |
| 18 | T4 loader and reader: `lib/sync/tests/test_adapters.py` (inside the 418) and `test-adapters.sh`, including the review fix 2 parity case |
| 19 | T5 engine over a fixture adapter: `lib/sync/tests/test_core.py` (inside the 418) |
| 20 | T6 body-expander relay: `lib/adapters/tests/test_body_expander.py` (inside the 418), controls in the table above |
| 21 | T7 inbox heading: `test_core.py` and `test_conformance.py` (inside the 418), control in the table above |
| 22 | T8 legacy Reminders state copy: `test_conformance.py`, control in the table above |
| 23 | T9 sweep legs: the three sweep suites, controls in the table above |
| 24 | T10 Multica token: `bash tests/test-sync-dispatch.sh`, control in the table above |
| 25 | T11 floor: `lib/adapters/tests/test-adapters.sh` floor cases; the system Python 3.9 import and the `/bin/bash` shim cases ran inside that suite |

## Review
One independent Opus review of the whole diff for behaviour preservation and security: no Critical, one Important and five Minor findings. All six were fixed in the finishing step, one commit each or grouped by file.

| # | Finding | Fix |
|---|---|---|
| 1 | Important: the loader appended the adapter directory to the end of `sys.path`, so an installed package named like a sibling (`github`, `notion`) won over the kit file | the directory goes right after the core entries; a sibling stem that resolves outside the adapter directory is refused with one `adapters: <adapter>: module name <stem> already provided by <path>` line; the conformance test that a stem never shadows the standard library or core stays green |
| 2 | the bash reader skipped an unknown row kind silently | it prints the loader's line to stderr; parity case added in both shells |
| 3 | `priority` missing from `CORE_VERBS` | added; the equality test now reads the words `cmd_board_single` answers itself. No other core word was in that position |
| 4 | `link-check.sh` took `KIT_LIB` from the environment | it resolves `link.py` from its own physical location. Checked by hand with `KIT_LIB` unset and a stub `python3` that echoed the resolved path; no committed test |
| 5 | Ctrl-C on a hand-run sweep | the code already matches the spec (INT and TERM trap, TERM to the leg, wait, exit 130 or 143; the sweep suite covers it). The adapter README now says that a process the leg itself started is not signalled by the runner |
| 6 | help text says `D`, generated line prints `VALUE` | left as is: both strings are in the golden byte for byte from master, so a rewording would be an unlisted delta. A comment in the manifest says why |

## Not run, and open
- `tests/run-all.sh`: not run. On the lead's instruction the named suites above replaced it, because the host is overloaded and other services depend on it.
- CI: not run. The org's runner pools are down.
- `tests/test-wrap-land.sh` and `tests/test-adopt.sh`: not run. Each has a known red on master that is not part of this change.
- Any live sync: never run, by design. Every suite uses fixtures, stubs and dry-run seams. No real store, Hermes home, Notion, Reminders, Multica, GitHub write or Discord was reached.
- `bash lib/gate/boundary-lint.sh` is not clean: it reports one hit, `tests/test-state-check.sh:365`, a line that arrived with the state-check change this branch is stacked on. The same hit appears on that change's own branch. This change adds no hit: one phrase in a moved dated spec was reworded so the path check passes.
- Finding 4 has no committed test, only the manual check above.
- The first live proof is the post-merge check in the spec (section Risk and rollback), read only, on the first hourly tick that starts after the merge. Until then the only evidence for the live paths is the fixtures and the golden.
