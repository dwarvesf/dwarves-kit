# Spec: split wrap.sh and its tests into modules
Generated: 2026-09-30
Status: DRAFT (validation round 1 NEEDS REVISION, folded)
Lane: normal
Depth: research (repo: the function map, the test-section coupling, every reference to the two files)

## Problem
`lib/wrap/wrap.sh` (3,616 lines, 98 functions) and `tests/test-wrap.sh` (5,987 lines, 1,581 asserts) changed 55 and 73 times in 30 days. Every agent edit reads the whole 3,600-line file to touch one verb. `bin/test-affected` maps any `lib/wrap/*` change to `tests/test-wrap*.sh`, so a one-line change runs all 1,581 asserts: 7m43s measured on this Mac. This spec splits both files by subcommand with zero behavior change.

## Picture
```
bin/wrap ──exec──> lib/wrap/wrap.sh   header + set/env/constants + _usage + main (case on verb)
                        │ source "$SELF_DIR/wrap-<m>.sh", fixed order, before main runs
      ┌─────────┬───────┼────────┬─────────┬────────┬─────────┐
   common     scan    apply     pull     carry      ci      merge
      └─────────┴───────┼────────┴─────────┴────────┴─────────┘
              land    start     log     deploy   rebase

tests/test-wrap.sh (runner, `# runner:` header) ──> bash tests/test-wrap-<m>.sh, one per module (+ report-lint, cli)
tests/run-all.sh ──skips every `# runner:` file──> runs each tests/test-wrap-<m>.sh once, directly
tests/test-wrap-<m>.sh ──source──> tests/lib/wrap-stub.sh (chk, TMPD, gh stub, fixture builders)
bin/test-affected: lib/wrap/wrap-<m>.sh -> tests/test-wrap-<m>.sh ; wrap.sh, wrap-common.sh -> tests/test-wrap.sh
```

## Module map
Each function moves with the comment block and top-level statements directly above it. Line ranges are today's.

| Module | Today's lines | Functions (count) |
|---|---|---|
| `wrap.sh` (dispatcher) | 1-121, 3593-3616 | `_usage` `main` (2); keeps header, `set -uo pipefail`, GIT_* scrub, LOCK_STALE_SECS, LOG_LINE_BUDGET, SELF_DIR, LIB_ROOT, *_PY/*_SH paths, kit-config and default-branch-warn sources |
| `wrap-common.sh` | 122-253, 385-437, 846-854 | `_is_repo` `_origin_url` `_ref_exists` `_default_branch` `_gh_state` `_gh_note` `_gh_merge_transient` `_gh_merge_retry` `_mtime` `_fmode` `_short` `_open_own_prs` `_squash_json` `_squash_verdict` `_write_guard` `run` `_union_marked` (17); globals WRAP_MERGE_RETRY_*, _OWN_PR_LIMIT, APPLY..OWN_N |
| `wrap-scan.sh` | 255-383 | `_scan_repo` `_add_under` `_expand_bare_under` `cmd_scan` (4) |
| `wrap-apply.sh` | 439-845, 1649-1766 | `_scanned_tip` `_merge_proof` `_absorbed` `_wt_locked` `_wt_lock_pid` `_wt_lock_live` `_wt_cleared` `_apply_worktrees` `_apply_branches` `_archive_slug` `_apply_archive_unmerged` `_apply_origin_branches` `_apply_repo` `cmd_apply` (14); _ORIGIN_PR_LIMIT, _ORIGIN_DELETE_CHUNK |
| `wrap-pull.sh` | 855-1169 | `_union_carry_back` `_pull_past_dirty_on` `_ff_blocked_into` `_stash_blocked` `_unstash` `_pull_default` `_land_ff_pull` (7) |
| `wrap-carry.sh` | 1170-1231, 1325-1647 | `_stray_lines` `_stray_board_rows` `_autoland_on` `_carry_branch_ours` `_autoland_carry` `_carry_stray_file` `_carry_stray` `_carry_stray_commits` (8); KIT_WRAP_CARRY_CHECKS_SECS and its `case` guard |
| `wrap-ci.sh` | 1232-1324 | `_ci_on_merge` `_ci_label_sync` `_ci_checks_wait` (3); KIT_WRAP_CI_ON_MERGE, CI_JQ_DEFS, KIT_WRAP_CI_GRACE_SECS and its `case` guard |
| `wrap-merge.sh` | 1767-2335 | `_pr_detail` `_pr_gate` `_pr_detail_settled` `_branch_worktree` `_union_dedupe_rows` `_scratch_wt_add` `_scratch_wt_drop` `_union_remerge` `_remerge_push` `_fallback_ok` `_squash_fallback` `cmd_merge` (12); KIT_WRAP_SETTLE_SECS and its `case` guard |
| `wrap-land.sh` | 2336-2664 | `_tree_verify` `_path_change` `_land_feature_title` `cmd_land` (4) |
| `wrap-start.sh` | 2665-2804 | `cmd_start` `_start_carry` (2) |
| `wrap-log.sh` | 2805-3188 | `_realpath_f` `_home_fence` `_refuse_symlink` `_worktree_copy` `_log_anchor_head_lines` `cmd_log` `cmd_knowledge_root` `cmd_stage` (8) |
| `wrap-deploy.sh` | 3189-3356 | `cmd_default_branch` `cmd_follow_mode` `_dw_seconds` `cmd_deploy_wait` `_deploy_wait_poll` `_deploy_wait_pending` (6); DEPLOY_POLL_SECS |
| `wrap-rebase.sh` | 3357-3592 | `_rb_git` `_rb_rebasing` `_rb_markers` `_rb_stages` `_rb_changelog_merge` `_rb_abort` `_rb_has` `_rb_changed` `_rb_stop` `_rb_final_regen` `cmd_rebase` (11); _RB_* |

Total 98, equal to today's `grep -c '^[a-zA-Z_][a-zA-Z0-9_]*()' lib/wrap/wrap.sh`. Grouping follows the call graph: a helper called from three or more modules lives in `wrap-common.sh`; a helper with one caller module lives with that caller. Cross-module calls resolve at call time, since every module is loaded before `main` runs.

## Design
The Picture shows the load path, the runner, the run-all skip and the test-affected mapping this section specifies.

**Sourcing.** `wrap.sh` keeps its `SELF_DIR` line (`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd`, valid in bash 3.2) and adds, right after the default-branch-warn source line, one loop in the table's order: `for _m in common scan apply pull carry ci merge land start log deploy rebase; do source "$SELF_DIR/wrap-$_m.sh" || { echo "FATAL: lib/wrap/wrap-$_m.sh missing or unreadable" >&2; exit 1; }; done; unset _m`. The fatal line copies the two existing source guards.

**Globals and options.** Modules are sourced into the dispatcher's shell, so `set -uo pipefail`, the GIT_* scrub, GIT_TERMINAL_PROMPT and every constant apply unchanged. A module holds function bodies plus exactly the top-level statements the table below assigns it: no shebang, no `set`, no `exit`, nothing else that runs at source time. Today's file has 52 non-blank, non-comment lines outside functions (awk in Verification):

| File | Top-level statements (today's line) |
|---|---|
| `wrap.sh` | `set -uo pipefail` (81); `export GIT_TERMINAL_PROMPT=0` (84); GIT_* scrub: `_loc_vars=` and its `[ -n ] \|\|` fallback (92-95), `for _v ... case ... done` (96-98), `unset _v _loc_vars` (99); LOCK_STALE_SECS (102); LOG_LINE_BUDGET (104); SELF_DIR, LIB_ROOT (106-107); STAGING_FORMAT_PY, BACKLOG_SH, GATE_LEDGER_SH (110, 111, 114); two `source ... \|\| { ...; exit 1; }` (116, 118); `main "$@"` (3616); plus the new source loop |
| `wrap-common.sh` | WRAP_MERGE_RETRY_MAX, WRAP_MERGE_RETRY_SLEEP (177-178); _OWN_PR_LIMIT (215); APPLY, WORKTREES, ARCHIVE_UNMERGED, MODE, FAILURES, TIPS_FILE, TIPS_OVERRIDE, OWN_SET, OWN_SEEN, OWN_N (387-396) |
| `wrap-apply.sh` | _ORIGIN_PR_LIMIT (783); _ORIGIN_DELETE_CHUNK (785) |
| `wrap-ci.sh` | KIT_WRAP_CI_ON_MERGE (1253); CI_JQ_DEFS, a six-line single-quoted jq string (1261-1266); KIT_WRAP_CI_GRACE_SECS (1301) and `case "$KIT_WRAP_CI_GRACE_SECS" in ...` (1302) |
| `wrap-carry.sh` | KIT_WRAP_CARRY_CHECKS_SECS (1332) and `case "$KIT_WRAP_CARRY_CHECKS_SECS" in ...` (1333) |
| `wrap-merge.sh` | KIT_WRAP_SETTLE_SECS (1832) and `case "$KIT_WRAP_SETTLE_SECS" in ...` (1833) |
| `wrap-deploy.sh` | DEPLOY_POLL_SECS (3244) |
| `wrap-rebase.sh` | _RB_GENERATED, _RB_GENERATOR (3364-3365); _RB_CHANGELOG (3367) |
| `wrap-scan.sh`, `wrap-pull.sh`, `wrap-land.sh`, `wrap-start.sh`, `wrap-log.sh` | none |

**Load order.** The module top-level statements have no inter-dependency: each right side reads a literal or an environment default `${X:-d}`, where X is its own name, or WRAP_ORIGIN_DELETE_CHUNK for _ORIGIN_DELETE_CHUNK (no `lib/wrap` line assigns it). Each `case` reads only the variable assigned on the line above it. No statement reads a value another module sets at source time. Checked by extracting every `$name` reference from each top-level line past line 119. CI_JQ_DEFS is also read by `_autoland_carry` (line 1395) and `_pr_gate` (line 1803), at call time only. The `wrap.sh` block (81-118) keeps its own order and still runs before every module, as today.

**`_usage` stays in `wrap.sh`.** It prints lines 2-31 of `${BASH_SOURCE[0]}`. Moved into a module it would print that module's header. The header block keeps its line numbers because the source loop goes below line 118.

**Rejected: one executable per verb.** `apply` calls `cmd_merge` (autoland) and `cmd_land` calls pull and ci helpers. Separate executables would need those calls rewritten as subprocess calls, which changes globals (FAILURES, MODE, CI_PRELABEL_KEYS out-params) and exit codes. That is a behavior change.

**Rejected: keep one file.** The file grew with every verb, and test selection cannot narrow below the whole suite while one file holds all verbs.

**Test side.** `tests/lib/wrap-stub.sh` holds today's lines 15 and 17-287 verbatim (set, WRAP, chk/chk_has/chk_no, TMPD and its trap, config and ledger pins, the gh stub, gitc/build_remote/make_clone/set_stub, the three remotes, PR7). It also holds the definitions two suites share, moved verbatim: LAB_BASE, LAB_LOCAL, LAB_REMOTE, `build_union_repo`, `advance_union_repo`, LAB_STRAY, `al_run`, `al_orphan`, `build_land`, and the PD_ON/PD_PROJ block. Each suite keeps its own copy of line 16 (KIT_DIR, which resolves from `BASH_SOURCE[0]`) and then sources the stub. Each suite ends with today's tail, its own name in place of `test-wrap`.

| Suite | Today's sections (line of `echo "==="`) |
|---|---|
| test-wrap-scan.sh | 289, 306, 316, 321, 340 |
| test-wrap-apply.sh | 360-683 (11 sections), 825, 4297, 4433, 5559, 5782 |
| test-wrap-pull.sh | 703, 1277 |
| test-wrap-carry.sh | 847, 936, 1096 |
| test-wrap-merge.sh | 1603, 1617, 1641, 1667-1825 (retry and gate cases), 2090, 2167, 2290, 2344, 2544, 2631, 2662 |
| test-wrap-ci.sh | 1831, 2884 |
| test-wrap-land.sh | 2810, 3149, 3434 |
| test-wrap-start.sh | 3588, 3696 |
| test-wrap-log.sh | 3816, 3927, 3977, 4023, 4115 |
| test-wrap-deploy.sh | 3797, 4546, 4732 |
| test-wrap-rebase.sh | 5268 |
| test-wrap-report-lint.sh | 4884 |
| test-wrap-cli.sh | 4274, 4862 |

**Seeds.** Sections share fixture state, not only helpers, and mutate it cumulatively. `$TMPD/clone-scan-main` is built by the scan loop (`make_clone "scan-$def" ...` at line 294, then `set_stub`) and read by 19 sections in five suites. Later sections commit on it and push it into `$TMPD/bare-rmain` (lines 1634, 1638, 1680, 1847, 2103). The gh stub appends every call to `$GH_STUB_CALLS`, which only some sections truncate. MERGE_CUR (line 1629) and MERGE_URL (line 1658) are read by the ci section. A seed of setup lines alone can let a `chk_no` pass vacuously: the forbidden string stays absent because the state that would print it never formed. So each suite's seed reproduces the exact state each of its sections sees in the monolith run. That includes every earlier mutation the suite depends on, also those made by another suite's sections that ran between two of its sections. The seed copies those lines verbatim or runs the needed earlier sections' setup. Seeds are the only added test lines besides the source line and the KIT_DIR copy.

**Runner.** `tests/test-wrap.sh` becomes a loop over `tests/test-wrap-*.sh`. It relays each suite's output, sums the counts, prints today's final line (`test-wrap: all N passed` or `test-wrap: P passed, F FAILED of T`), and exits 1 on any failure. It carries a `# runner:` header. `tests/run-all.sh` skips a `# runner:` file in its glob loop (today it would run every wrap assert twice). About 90 docs/verification records cite `bash tests/test-wrap.sh`; they stay reproducible.

**`bin/test-affected`.** Two changes. (1) Selection: for `lib/wrap/<stem>.sh` with `tests/test-wrap-${stem#wrap-}.sh` present, pick that suite (`report-lint.sh` resolves to test-wrap-report-lint.sh by the same rule). For any other `lib/wrap/*.sh`, that is `wrap.sh` and `wrap-common.sh`, pick the runner `tests/test-wrap.sh`. Both replace the `tests/test-wrap*.sh` glob for lib/wrap only; every other module keeps the glob (a generic stem rule would narrow 25 other files, measured). (2) Cache key: add `tests/lib/*.sh` to the source universe, and let `cache_key` also scan each `tests/lib/*.sh` the suite names. The stub carries one comment line naming every `lib/wrap/*.sh`, so a suite's cached PASS dies when any module or the stub changes. The runner names `tests/lib/wrap-stub.sh` in its header, so its key moves the same way. Without (2) a module edit leaves its suite's key unchanged and serves a stale PASS. The `wrap-` prefix keeps basenames unique: `merge.sh` would substring-match `premerge.sh` in refs_any.

A module change runs its own suite only. A regression that reaches another module's asserts through a cross-module call shows in the runner, which T4's proof and CI run.

## Invariants
- Every assert keeps its text. Total asserts stay 1,581: 1,579 PASS plus the 2 baseline FAILs named in Grounding, both before and after.
- `bin/wrap` output is byte-identical on every existing case, `--help` included (test-bin-forwarders line 142 greps `wrap.sh scan` from it).
- No file under `hooks/` changes (`hooks/codex-hooks.json` and `lib/adopt/known-hashes.sh` pin hook hashes; neither names lib/wrap).
- Function bodies move verbatim: `git diff --color-moved=zebra --color-moved-ws=no origin/master -- lib/wrap tests` shows moved blocks plus only the source loop, module header comments, the stub's module-list comment line, the runner, the run-all `# runner:` skip, KIT_DIR copies, seeds, suite tails, and the path edit at today's test line 5736.

## External references
| Reference | Change |
|---|---|
| tests/test-wrap.sh:5736 `sed -n '/^_absorbed() {/,/^}/p' .../lib/wrap/wrap.sh` | path becomes `lib/wrap/wrap-apply.sh` (moves to test-wrap-apply.sh) |
| lib/config/module-registry.md:338 (`_add_under`/`_expand_bare_under` in wrap.sh) | `lib/wrap/wrap-scan.sh` |
| lib/config/module-registry.md:349 (`cmd_follow_mode` in wrap.sh) | `lib/wrap/wrap-deploy.sh` |
| lib/gate/default-branch-warn.sh:38, bin/test-affected:41 (comments on `_default_branch`) | name `lib/wrap/wrap-common.sh` |
| lib/board/backlog.sh:43 (comment, union re-merge) | name `wrap-merge.sh` |
| lib/gate/boundary-lint.sh:19 (comment, fixture text in test-wrap.sh) | name `tests/test-wrap-*.sh` |
| bin/wrap:21, lib/gate/premerge.sh:35 (exec/call wrap.sh) | none: dispatcher path unchanged |
| tests/test-bin-forwarders.sh:139-142, tests/test-gitattributes-union.sh:79, tests/test-config-seams.sh:16 | none |
| docs/FEATURES.md `/kit:wrap` row (Specs, Tests columns are token greps) | regenerate: this spec and the new suites move it |
| tests/test-meta.sh | no wrap.sh pin; its FEATURES freshness check needs the regen above |
| commands/wrap.md:200, docs/test-value-audit.md:36,69, dated line anchors in docs/verification/wrap-stray-commit-carry.md:100, docs/verification/estate-seams.md:39, docs/implementation-notes/wrap-carry-autoland.md:7 | none: dated records, already stale |

## Task Breakdown
- [ ] T1 code split: create the 12 modules and the source loop per the Module map, moves only. Done when: the 98-function count holds across `lib/wrap/*.sh` minus report-lint.sh, each name defined once, `bash -n` passes on every module, `grep -nE '^(set |exit|#!)' lib/wrap/wrap-*.sh` prints nothing, the guard grep in Verification prints `guard ci`, `guard carry`, `guard merge`, the top-level diff in Verification shows only the added source loop line, `bin/wrap --help` output is byte-identical to origin/master, and the old monolithic `bash tests/test-wrap.sh` reports 1,579 passed, 2 FAILED of 1,581.
- [ ] T2 test split: extract `tests/lib/wrap-stub.sh`, the 13 suites per the Suite table with seeds, the runner, the line 5736 path edit, the run-all `# runner:` skip. Done when: each suite passes standalone except the 2 baseline FAILs (in test-wrap-deploy.sh and test-wrap-report-lint.sh), the suite totals sum to 1,581, the runner prints `1579 passed, 2 FAILED of 1581`, and the sorted assert-line diff in Verification is empty. Per suite, the suite loop in Verification prints no `comm` line: every PASS and FAIL line the suite prints standalone appears with the same status in the monolith run. Together with the runner diff this makes each suite's PASS list identical to the same asserts in the monolith. In each suite that holds a `chk_no` (all but start and cli, which hold none), one `chk_no` that depends on seeded state goes red under a deliberate break of that state; the proof records the edit and the red line.
- [ ] T3 test-affected and references: the selection and cache-key changes, every row of External references. Done when: `bin/test-affected --list` on a one-line change to `lib/wrap/wrap-rebase.sh` lists only tests/test-wrap-rebase.sh and tests/test-meta.sh, the same on `lib/wrap/wrap-common.sh` lists only tests/test-wrap.sh and tests/test-meta.sh, a stub edit lists every suite, and the cache sequence in Verification prints PASS, then CACHED, then PASS again for tests/test-wrap-rebase.sh.
- [ ] T4 FEATURES regen and proof: `bash lib/registry/feature-registry.sh check --fix`, then the Verification block, recorded in `docs/verification/wrap-split.md`. Done when: every Verification command matches its expected output.

## Verification
```
B="$TMPDIR/ws-base"; git worktree add --detach "$B" a9f0c9dc
P='^  .\[0;3[12]m(PASS|FAIL)'
TL='/^[a-zA-Z_][a-zA-Z0-9_]*\(\) *\{/{if($0!~/\}[[:space:]]*$/)f=1;next} f{if(/^\}/)f=0;next} !/^[[:space:]]*(#|$)/'
awk "$TL" "$B"/lib/wrap/wrap.sh | wc -l                                      # 52
diff <(awk "$TL" "$B"/lib/wrap/wrap.sh | sort) <(awk "$TL" lib/wrap/wrap*.sh | sort)  # only "> for _m in ... unset _m"
grep -nE '^(set |exit|#!)' lib/wrap/wrap-*.sh                                # nothing
for p in ci:CI_GRACE carry:CARRY_CHECKS merge:SETTLE; do grep -qF "case \"\$KIT_WRAP_${p#*:}_SECS\" in" "lib/wrap/wrap-${p%%:*}.sh" && echo "guard ${p%%:*}"; done
bash "$B"/tests/test-wrap.sh > before.out 2>&1; tail -1 before.out  # 1579 passed, 2 FAILED of 1581
bash tests/test-wrap.sh > after.out 2>&1; tail -1 after.out                 # same line
diff <(grep -aE "$P" before.out | sort) <(grep -aE "$P" after.out | sort)  # empty
for t in tests/test-wrap-*.sh; do o="$(bash "$t" 2>&1)"; echo "$? $t"; printf '%s\n' "$o" | grep -aE "$P" | sort | comm -23 - <(grep -aE "$P" before.out | sort); done  # 0 except deploy, report-lint; no other line
bash tests/test-meta.sh && bash tests/test-bin-forwarders.sh && bash tests/test-gitattributes-union.sh
bash lib/registry/feature-registry.sh check                                 # fresh
git diff --quiet origin/master -- hooks/ && echo hooks-untouched            # repin check
diff <(bash "$B"/bin/wrap --help) <(bin/wrap --help) && echo help-identical
printf '# x\n' >> lib/wrap/wrap-rebase.sh; bin/test-affected --list; bin/test-affected  # rebase + meta; PASS tests/test-wrap-rebase.sh
bin/test-affected                                                            # CACHED tests/test-wrap-rebase.sh
printf '# y\n' >> lib/wrap/wrap-rebase.sh; bin/test-affected                 # PASS tests/test-wrap-rebase.sh: key moved, re-run
git checkout -- lib/wrap/wrap-rebase.sh
printf '# x\n' >> lib/wrap/wrap-common.sh; bin/test-affected --list; git checkout -- lib/wrap/wrap-common.sh  # test-wrap.sh + meta only
git worktree remove "$B"
```
Negative control: add `return 1` as the first body line of `_rb_changelog_merge` in `lib/wrap/wrap-rebase.sh`. Run every `tests/test-wrap-*.sh`: only test-wrap-rebase.sh goes red beyond the baseline (assert "rebase: pure-addition CHANGELOG exits 0", today's line 5336), and the runner exits 1. Restore with `git checkout -- lib/wrap/wrap-rebase.sh`.

## Grounding
- Base: worktree at origin/master a9f0c9dc. `wc -l`: wrap.sh 3,616, test-wrap.sh 5,987, bin/test-affected 208.
- Functions: `grep -c` of definitions = 98. Call graph built from function bodies (comments stripped); modules above follow it. Top-level code outside functions: the 52 lines the Verification awk prints, listed per file in Design. The awk skips a one-line function and a multi-line body up to its column-0 `}`. The file has 87 such closers, which is 98 definitions minus 11 one-liners. Beside assignments, the 52 lines hold `set`, `export`, the GIT_* scrub (its `[ -n ] ||` fallback, loop and `unset`), two `source` guards, three `case` guards and `main "$@"`.
- Asserts: `time bash tests/test-wrap.sh` printed `test-wrap: 1579 passed, 2 FAILED of 1581`, 7:42.90 total. Baseline FAILs (commands/wrap.md prose pins, red before this spec): "step 10 re-sizes the real diff before landing" (line 4823), "commands/wrap.md classifies each candidate's lane" (line 5050).
- Test coupling, measured: helpers used across future suites (build_union_repo, advance_union_repo, al_run, al_orphan, build_land) and variables (LAB_*, CW_*, PD_*, MERGE_CUR, MERGE_URL, FOREIGN_*, LAG_*); `$TMPD/clone-scan-main` read in 19 sections, `$TMPD/bare-rmain` in 9.
- References: `grep -rn 'wrap\.sh\|test-wrap'` over lib tests hooks commands bin docs/FEATURES.md lib/registry, plus `grep -rnE 'wrap\.sh:[0-9]|test-wrap\.sh:[0-9]'` repo-wide (3 dated hits). No hooks/ file and no test-meta pin names either file. FEATURES matches the token `wrap` (`token_pat`), so the spec itself moves the `/kit:wrap` Specs column.
- test-affected: the lib/<mod> glob rule (lines 133-141) and `cache_key` (lines 178-186, test file only) read live. A generic stem rule would change selection for 25 files in 10 other modules (board, gate, spec, mega and others), measured with a loop over `lib/*/*.sh`.
- Negative control dry trace: `return 1` in `_rb_changelog_merge` makes `_rb_stop` treat the CHANGELOG conflict as unsafe, so `cmd_rebase` aborts and exits non-zero; line 5336 `chk "rebase: pure-addition CHANGELOG exits 0" "$rc"` fails. Only `_rb_stop` calls `_rb_changelog_merge`, and only the rebase section runs `wrap rebase`.

## Out of Scope
- Any behavior change, rename, reorder of logic, or message edit. The user-facing `wrap.sh <verb>:` prefixes in error messages stay.
- The 2 baseline FAILs (commands/wrap.md prose drift). Flag to a separate fix.
- Dead code: none found. Every function has a caller in a function body (scan with comments stripped). Flagged, not changed: `lib/gate/mutation-smoke.sh:169` globs `tests/test-*.sh` and will run the wrap asserts twice through the runner.
- Splitting `commands/wrap.md` or `lib/wrap/report-lint.sh`.
