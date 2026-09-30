# Implementation notes: wrap split

Delta from `docs/specs/SPEC-374-wrap-split.md` only: decisions the spec did not
make, deviations, and tradeoffs. The spec is the contract; this log is what the
build itself learned.

## Step 0: spec fold

Folded the round-2 lead decisions and flipped `Status:` to VALIDATED:

- `bin/test-affected` maps `lib/wrap/wrap.sh` and `lib/wrap/wrap-common.sh` to
  every `tests/test-wrap-*.sh` suite, never the runner. `tests/run-all.sh` skips
  a `# runner:` file, so a runner mapping would make `run-all --changed` run no
  wrap suite at all, and the runner takes about 7m40s, over test-affected's 300s
  timeout. Folded into the Picture, the Design paragraph, T3's Done-when, and
  the Verification comment.
- Picture now says the suites cover 11 of 12 modules plus report-lint and cli:
  there is no `test-wrap-common.sh`.
- The `chk_no` red proof in T2 now breaks the code under test so it prints the
  forbidden string; a `chk_no` fails only when the string appears, so breaking
  seed state alone cannot turn it red.
- Verification order: the T1 commit lands before any `git checkout --` restore
  in the cache sequence or the negative control, because a restore fails on an
  untracked module file. The negative control asserts the named rebase assert
  goes red; the runner's exit code does not discriminate since the baseline
  already carries 2 FAILs.
- The Sourcing paragraph now states the reason plainly: the fixed order is a
  determinism pick, safe because module top-levels carry no inter-assignment
  dependency.

## T1: code split

Decisions the spec did not make:

- Boundary blanks. Spec ranges leave four orphan blank lines (today's 254, 384,
  438, 1648). Each was folded into the following module, so every original line
  lands in exactly one file and a byte-level reconstruction is possible.
- Module headers. Each `lib/wrap/wrap-<m>.sh` opens with one comment line
  (`# wrap-<m>.sh -- <what>; sourced by lib/wrap/wrap.sh.`) plus a blank line:
  the spec's allowed "module header comments". No shebang, no `set`, no `exit`.
- `wrap.sh` carries the source loop as the spec's exact line with no extra
  comment, keeping the added-lines diff to the loop alone.
- Vacuous-pass caveat, temporary: `tests/test-wrap.sh:5736` greps `_absorbed`
  out of `lib/wrap/wrap.sh`. After T1 that sed extracts nothing, so the two
  descriptor-exhaustion asserts pass vacuously until T2 repaths the sed to
  `wrap-apply.sh`. Totals stay 1,581 either way; the asserts go live again in
  T2.

Checks (run on this worktree, baseline = detached worktree at a9f0c9dc):

- Rebuild proof: concatenating the pieces back in original order reproduces
  wrap.sh byte-identically (3,616 lines, `diff` empty). Stronger than the
  spec's sorted top-level diff: every line, not only top-level statements.
- `bash -n` on all 13 files: ok.
- Function defs across `lib/wrap/wrap*.sh`: 98, `uniq -d` empty.
- `grep -nE '^(set |exit|#!)' lib/wrap/wrap-*.sh`: no output (exit 1).
- Guard grep: prints `guard ci`, `guard carry`, `guard merge`.
- Top-level awk: baseline prints 52; sorted diff vs `lib/wrap/wrap*.sh` adds
  only the `for _m in ... unset _m` source loop.
- `git diff` new-lines audit: the only added lines absent from the original
  file are the 12 module headers and the loop; no removed original line fails
  to reappear.
- `bin/wrap --help` vs baseline: identical.
- `bash lib/codex/repin.sh check`: the two master-baseline stale pins
  (safety-gate.sh, ship-gate.sh), no new ones.
- `bash tests/test-wrap.sh` vs baseline monolith run: both print
  `test-wrap: 1579 passed, 2 FAILED of 1581`; the sorted PASS/FAIL line diff
  is empty (1,581 lines each side). The 2 FAILs are the baseline wording ones
  ("step 10 re-sizes the real diff before landing", "commands/wrap.md
  classifies each candidate's lane").

Deviations:

- The split commit briefly wrote `wrap.sh` at mode 644 (original 755); a
  follow-up commit restored the bit. Module files stay 644: sourced, never
  executed, and the spec's "no shebang" matches that mode.



## Build notes: T2

Test split. `tests/test-wrap.sh` (5,987 lines, 1,581 asserts) became a thin
`# runner:` file plus 13 standalone `tests/test-wrap-<module>.sh` suites that
all source the shared harness `tests/lib/wrap-stub.sh` (monolith lines 15,
17-287: chk/chk_has/chk_no, TMPD setup, WRAP, config+ledger env, the gh stub,
`gitc`, `build_remote`, `make_clone`, `set_stub`, the LAB_* union fixtures,
`al_run`/`al_orphan`, `build_land`, the PD_* pull-dirty fixture). The stub
header names every `lib/wrap/*.sh` module so `bin/test-affected`'s cache key
covers them. `KIT_DIR` stayed out of the stub: `BASH_SOURCE[0]` would resolve
to `tests/lib`, so each suite assigns it before sourcing.

Suite map (monolith line ranges): scan 289-359; apply 360-683, 825, 4297,
4433, 5559, 5782; pull 703, 1277; carry 847, 936, 1096; merge 1603-1825,
2090-2662; ci 1831, 2884; land 2810, 3149, 3434; start 3588, 3696; log
3816-4115; deploy 3797, 4546, 4732; rebase 5268; report-lint 4884; cli 4274,
4862.

Seeds (each reproduces the exact state the section saw in the monolith):

- apply: rebuilds the `clone-scan-{main,master,develop}` + `bare-r*` fixtures
  (scan's build loop, lines 291-304 with an explicit `done`) because apply
  sections mutate the same clones; `_absorbed` extraction repathed from
  `lib/wrap/wrap.sh` to `lib/wrap/wrap-apply.sh` (the spec's allowed edit).
- pull: PD_* fixture rebuilt per monolith 1277 context.
- carry/merge: clone fixtures plus the merge pusher blocks replayed verbatim
  via `sed` slices (literal push text in the builder tripped the branch
  guard); merge seeds carry the `MERGE_CUR`/`MERGE_URL` exports its later
  sections read.
- ci: reseeds merge's fixture mutations (MERGE_CUR/MERGE_URL, bare-r* state)
  because its sections run after merge's in the monolith.
- land/start/log/deploy/rebase/report-lint/cli: self-contained fixture
  builders copied verbatim; only shared helpers come from the stub.
- Coverage audit: every monolith line 17-5984 lands exactly once across
  stub+suites, plus the intentional seed copies (scan fixture into
  apply/merge/ci/deploy, merge pusher into ci) and the two cut-boundary blank
  lines the stub emits itself.

Verification (baseline = the pre-split monolith in this worktree):

- `bash tests/test-wrap.sh` before split: `1579 passed, 2 FAILED of 1581`
  (baseline reds: "step 10 re-sizes the real diff before landing",
  "commands/wrap.md classifies each candidate's lane").
- After split, the runner prints the identical summary; the sorted assert-line
  diff vs baseline is empty (1,581 lines each side, `DIFF-EMPTY`).
- Standalone: scan 41, apply 242, pull 120, carry 135, merge 212, ci 127,
  land 126, start 59, log 114, deploy 146, rebase 102, report-lint 135, cli
  22 = 1,581 total. Only deploy (145/146) and report-lint (134/135) fail, on
  exactly the two baseline reds. Every suite's assert list is a `comm -23`
  subset of the baseline list.
- `tests/run-all.sh` now skips files carrying the `# runner:` header, so CI
  runs each suite once.
- `bash tests/test-meta.sh` 887/887 after regenerating `docs/FEATURES.md`
  (token counts shifted with the new files; mechanical regen kept),
  `test-bin-forwarders.sh` 48/48, `test-gitattributes-union.sh` 27/27.

Vacuous-pass proof (temporary module edits, all restored via git checkout):

- scan: `echo "plain-dir"` in `cmd_scan` -> FAIL `under: the plain directory
  is skipped silently` (40+1F of 41).
- apply: `echo "delete main"` in `cmd_apply` -> FAIL `apply --apply never
  touched the default branch` (241+1F of 242).
- pull: `echo "FAILED pull --ff-only"` in `_pull_default` -> FAILs `union
  carry: the pull did not fail`, `knob on: ...`, `union carry+stash: ...`
  (117+3F of 120).
- carry: `echo "FAILED"` in `_carry_stray_commits` -> FAILs `stray commits
  --apply: the pull did not fail`, `stray commits rerun: nothing left ahead`,
  `autoland adopt: nothing failed`, `autoland commits: nothing failed`
  (131+4F of 135).
- merge: `echo "eligible #32"` in `cmd_merge` -> FAIL `merge: a PR authored by
  someone else is not eligible` (211+1F of 212).
- ci: `CI_WAIT_END=0; return 0` at the top of `_ci_checks_wait` -> 22 FAILs
  incl. `ci-wait T3b: never merges on pre-label checks alone` (105+22F of
  127).
- land: `--base main` on both `gh pr create` calls (the `--body-file` branch
  alone is not on the happy path; first attempt there was a silent miss) ->
  FAIL `the create call never names a base` (125+1F of 126).
- deploy: `echo "DEPLOYED ..."` on the failure branch of `_deploy_wait_poll`
  -> FAIL `deploy-wait never claims DEPLOYED on a failure` plus the sibling
  "names the failed check" asserts and the baseline red (141+5F of 146).
- log: `echo "index.lock held by another writer"` in `cmd_knowledge_root` ->
  FAIL `knowledge-root: non-git repo never prints the index.lock message`
  (113+1F of 114). The `default branch` warns live in
  lib/gate/default-branch-warn.sh, not the module, so a module-native string
  was used.
- report-lint: dropped the `BLOCKER_RE` guard on the self-runnable warn ->
  FAIL `a stated blocker clears the warn` (133+2F incl. baseline red of 135).
- rebase: `return 1` as the first body line of `_rb_changelog_merge` (the
  spec's exact control) -> FAIL `rebase: pure-addition CHANGELOG exits 0`
  plus two siblings (99+3F of 102).
- `git status --short lib/` after all restores: empty.

`bin/test-affected` mapping (T3 pre-work landed here because the spec's
selection contract names the split files):

- Source universe and `is_source` now include `tests/lib/*.sh`, so the stub
  feeds every suite's cache key (the `source "$KIT_DIR/tests/lib/..."` line
  is `refs_exact`-visible) and a stub edit selects all 13 suites.
- `lib/wrap/wrap-<stem>.sh` selects only `tests/test-wrap-<stem>.sh`;
  `lib/wrap/report-lint.sh` selects `tests/test-wrap-report-lint.sh`;
  `lib/wrap/wrap.sh` / `wrap-common.sh` fan out to every `test-wrap-*.sh`
  (the runner `test-wrap.sh` never matches that glob). The generic
  `lib/<mod>` rule still covers other lib trees.
- The runner names the stub and the module list only in comments: enough for
  the raw `grep -oFf` cache key, never a refs-selection, so a stub change
  does not double-run the suites through the runner.
