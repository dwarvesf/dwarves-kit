# Wrap, land and session: rules, proofs, bridges, findings

Area: `lib/wrap/`, `lib/session/handoffs.sh`, `lib/reflect/`, `lib/telemetry/`, `lib/sync/adapters.sh`, `lib/config/`,
`lib/registry/feature-registry.sh`, `lib/repohygiene/repohygiene.sh`. Native gdp-wired rules from what the bash does,
laws from the docs, kept broken variants refused, bridges against the real scripts in temp sandboxes.

Run `cd lib/rules && node wrap/prove.ts` (`--no-bridges`, `--only <rule>`). State machines are proven with
`proveSteps {from: 'any'}`, decisions with `proveDecision`, every verdict `proven && checked && !assumes`;
deploy-wait's "every wait ends" with `proveLeadsTo` (assuming `DEPLOY_POLL_SECS >= 1`). 45 broken variants, all refused.
`bridge-util.ts` runs scripts from a file, not `bash -c` (Linux caps one argument at 128 KiB).

## Rules

| Rule | Source | Laws | Broken variants (all refused) | Bridge |
|---|---|---|---|---|
| merge-retry | wrap-common.sh:_gh_merge_retry | 5, any state | unvalidated-max, retry-refusal, no-cap | 1472 agree |
| merge-dispatch | wrap-common.sh:_merge_pr | 6 decisions | fallback-on-unreadable, slug-runs-project | 16 agree |
| merge-command | merge-command.sh:kit_merge_command | 9 decisions (one two-run) | quoted-header-unset, bad-skipped, working-tree-read, nonexistent-path | 432 agree |
| merge-cycle | wrap-common.sh:_merge_verify_push | 14, any state | push-on-red-verify, skip-gate, stuck-downgraded | 22 agree (real git) |
| check-verdict | wrap-merge.sh:_pr_gate (which run stands for a check) | 5, any state | latest-wins | via pr-gate's bridge |
| pr-gate | wrap-merge.sh:_pr_gate | 10 decisions | absent-is-clean, draft-late, empty-rollup-ok | 3000 agree |
| land | wrap-land.sh:_land_run | 23, any state | push-before-gate, draft-merges, tidy-on-mismatch | 8 agree on macOS (the kit's own land happy path also fails on the Linux box at HEAD) |
| land-many | wrap-land.sh:cmd_land | 4, any state | continue-after-fail | 120 agree |
| worktree-sweep | wrap-apply.sh:_apply_worktrees (+ run, _write_guard) | 8 decisions | dirty-not-rechecked, dry-run-writes, lock-ignored | 13 agree (macOS), 12 (box) |
| deploy-wait | wrap-deploy.sh:_deploy_wait_poll | 9, any state, + liveness | skipped-passes, missing-passes | 150 agree |
| config-precedence | kit-config.sh:kit_config_get/_root, config.sh:_resolve | 8 decisions | first-dot-split, root-only-reads-project | 48 agree |
| module-switch | config/hook-module.sh | 7 decisions | first-line-decides, opt-in-default-on, kit-root-wins | 948 agree |
| gate-policy | gate/gate-policy.sh:enabled ([gate] defaults) | 7 decisions | dirty-false-applies, unknown-key-off | 576 agree |
| handoff-archive | session/handoffs.sh:cmd_archive | 8, any state | overwrite-archive, default-branch-moves | 156 agree |
| handoff-liveness | session/handoffs.sh:handoff_liveness | 3, any state | missing-is-closed | 120 agree |
| throttle | reflect/hook-util.sh:hu_throttled | 6, any state | skip-refreshes, off-still-throttles | 720 agree (stubbed clock) |
| kit-migrate | telemetry/kit-migrate.sh:_kit_migrate_corpus | 6, any state | sentinel-on-failure, follow-symlink | 150 agree |
| debt-disposition | reflect/weekend-batch.sh:_disposition, cmd_mark_paid | 5 proven; 1 promised law refuted (finding 5) | engage-ignored | 258 agree |

Key laws: at most max(1, WRAP_MERGE_RETRY_MAX) gh calls and a real refusal is never retried; a set or unreadable
`[merge] command` never falls back to the plain squash (precedence project > operator > kit-root; the working tree
never changes the answer); nothing is pushed or merged before the ship gate passes, a red `--verify` never pushes,
`--draft` never merges, a worktree is removed only after the tree is verified and kept on a refusal or TREE MISMATCH;
a draft is never eligible and any failing or pending check blocks; a sweep never removes a dirty, unproven,
live-locked or busy worktree and its dry run never writes; DEPLOYED only on all-success and every wait ends; an opt-in
module is off unless set literally true; archive never deletes and a handoff is consumed at most once; a skipped
throttle call never refreshes the stamp; nothing is migrated through a symlink.

## Findings (promised law refuted by the faithful rule and reproduced on the real bash)

1. **Non-numeric `WRAP_MERGE_RETRY_MAX` retried forever (fixed).** `WRAP_MERGE_RETRY_MAX=five` (or `3.5`) with a gh
   that keeps answering `HTTP 502`: `[ "$attempt" -ge five ]` errors, reads as false, and the loop never stops (299 calls
   in 5 s). Fix: a non-numeric value falls back to 3 (same for the sleep). Bridge: the committed code agreed with the
   `unvalidated-max` variant; 1472 agree after. Test: `test-wrap-merge.sh` SPEC-300 "non-numeric WRAP_MERGE_RETRY_MAX
   … bounded at three merge calls". Note (not fixed): `MAX=0` still makes one call, as the law allows.
2. **`_pr_gate` read a missing mergeStateStatus as CLEAN (fixed).** The gate's own comment says anything but a clean
   state fails closed. A rollup with no `mergeStateStatus` answered OK. Fix: `(.mergeStateStatus // "")`. Bridge:
   diverged after 769; 3000 agree after. Test: `test-wrap-merge.sh` "a missing merge state … is never eligible".
3. **`config get` read no layer for keys with two dots (fixed).** `_resolve` split `lane.normal.phases` at the first
   dot while `kit_config_get` splits at the last, so ten registry rows (`lane.*.phases|light`) printed the registry
   default. Fix: `section="${tomlkey%.*}"; key="${tomlkey##*.}"`. Bridge: diverged after 17; 48 agree after. Test:
   `test-config-registry.sh` "lane.normal.phases" get and explain.
4. **A quoted table name `["merge"]` read as "no merge command", so the kit merged the plain way (fixed).** The docs
   say these forms never read as not set. `_kit_mc_shape` unquoted the header and passed it; `_kit_toml_get` matched no
   section; wrap land/merge ran the plain squash and skipped the repo's merge script. Fix: refuse a header that differs
   from `[merge]` before unquoting, and cut a header comment at the first `#` as the reader does. Bridge: the committed
   code agreed with the `quoted-header-unset` variant; 432 agree with the shipped rule after. Tests: `test-merge-command.sh`
   "double-quoted table name", "single-quoted table name".
4b. **No base ref and no key refused instead of merging plain on hosts with a `/nonexistent` directory (fixed).**
   `kit_merge_command` resolved `/nonexistent`, a real directory on Debian (the home of `nobody`), and awk failed on it:
   exit 2 "refusing to merge". Fix: resolve `""`. The existing check "base unresolvable, no key anywhere: still unset
   (exit 1)" failed on the box at HEAD and passes now. (Outside this area, harmless unless `/nonexistent/.kit.toml`
   exists: `lib/gate/gate-policy.sh`, `lib/gate/proof-ledger.sh` and `lib/adopt.sh` use `KIT_PROJECT_ROOT=/nonexistent`.)
5. **"PAID, never re-collected" holds only until the next debt line (not fixed).** `debt verdict=log response=engage`,
   then `debt verdict=log`, and the rid is collected again as `logged` (reproduced with `gate-ledger debt`,
   `weekend-batch mark-paid r1`, a new `debt r1 verdict=log`, `list` → `r1 logged`). The reader reads the last line by
   design; whether a re-classification after payment is new debt is a policy decision, and the writer
   (`lib/gate/gate-ledger.sh`) belongs to the gates area. `prove.ts` asserts the law stays refuted and prints the run.

## Smaller issues (no promised law broken)

- kit-migrate: if a refused symlink is later removed, the fresh-install path leaves `.migrate-refused` beside
  `.migrated`; nothing reads that marker.
- land: a ship-gate refusal reports `LAND: refused (guard, exit 2)` because `_LAND_STEP` is not moved before the gate.
- wrap scan is documented "never writes" but runs `git fetch --prune`, which moves remote-tracking refs.

## Implicit machines found but not modelled

| Machine | Why not |
|---|---|
| `_mvp_trap` signal path | in the rule as a `signal` event, not bridged: needs a kill timed to a chosen step |
| `_pr_head_resync`, `_stacked_rebase`, `_squash_fallback` | need a model of GitHub PR state over time |
| `_pr_detail_settled`, `_pr_detail_at_head`, `_ci_checks_wait`, `_ci_label_sync` | same bounded-poll shape as deploy-wait (modelled); their knobs are validated |
| `_autoland_carry`, `_carry_stray*`, wrap start / ship | compositions of modelled rules |
| `_pull_default`, `cmd_rebase` / `_rb_resolve` | decisions over sets of file paths and per-path conflict classes |
| `_apply_archive_*`, wrap-log | glob and path rules over strings; better held by table tests |
| `_apply_origin_branches` | needs GitHub's merged-PR list as state |
| `_adopt_preflight` / `_adopt_one` | independent checks, no state between calls |
| report-lint | a Markdown grammar, not a request machine |
| egress-fail, lane-telemetry, adapters, feature-registry, repohygiene | stateless append or read-only reports |
| drain.sh | execs Python |
