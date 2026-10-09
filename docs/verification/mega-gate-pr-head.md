# Proof of done: mega gate on the PR head

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 [NC] | Head mode runs the floor on the given commit | `head-mode-floor-hits` in `tests/test-mega-gate-head.sh`: `gate rid normal --head P` from the `main` checkout exits 1 and names `hard path (auth: src/auth/login.ts`; the same gate with no `--head` exits 0 | PASS |
| AC2 [NC] | Head mode refuses a bad SHA, a non-repo root and a missing merge base | `head-mode-bad-sha` (unknown 40 hex, `abc`, bad `--base-tip`, a root that is not a repo) and `head-mode-no-base` (no default-branch ref, then an unrelated `--base-tip`): each exits 1 with `BLOCKED: mega gate:`, the no-base legs name `no merge base`; `head-mode-usage` pins exit 64 for `--base-tip` alone and for a flag with no value | PASS |
| AC3 | Head mode finds the spec in the commit's tree | `head-mode-large-spec`: a large spec only in `P`'s tree refuses with `is large`, the message names the in-tree path, no scratch file is left in `$TMPDIR`; a hyphenated slug and a co-located spec match; a small spec and a non-numeric co-located id pass | PASS |
| AC4 | No `--head` keeps hook parity | `tests/test-mega-gate-parity.sh` unchanged | PASS |
| AC5 [NC] | `merge` fetches the PR head and gates on it | `merge-floor-sees-pr-head`: origin carries `refs/pull/7/head` = `P`; `merge 7 rid normal --execute` from the `main` checkout is refused with the auth message and the fake `gh` records no `pr merge` | PASS |
| AC6 [NC] | A fetch that fails or returns another commit refuses | `merge-fetch-mismatch`: another commit at `refs/pull/7/head` refuses with `head moved after it was pinned`; an unreachable origin refuses with `cannot fetch PR #7`; `merge-fetch-timeout`: a fetch that hangs is killed after `MEGA_MERGE_FETCH_TIMEOUT` and refuses | PASS |
| AC7 | A clean PR still merges | `merge-clean-pr-head`: the fake `gh` records `pr merge 9 --squash --delete-branch --match-head-commit <C>` | PASS |
| AC8 | Docs match | `docs-match` legs: registry rows, the CHANGELOG line, `SECURITY.md` line 14 and its two new residuals, `commands/mega.md`, the `merge()` comment; `test-meta.sh` and `doc-projection-check.sh` pass | PASS |
| AC9 [NC] | A wave PR is diffed against its own base branch | `merge-mega-base`: PR 8 on `mega/x` (which carries `db/migrations/0001.sql`) merges; with the base stub saying `main` the same PR is refused on the migration | PASS |

Extra legs from the validate round: `merge-base-read` (unreadable base, a name `check-ref-format` rejects, a base branch missing on origin), `merge-base-retarget` (the base read again before `gh pr merge` differs), `merge-fetch-override` (a stub that prints a non-SHA, a non-commit or fails), and the private `refs/kit/pr-<n>/` refs are gone after every merge and every refusal.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-mega-gate-head.sh` | 0 | PASS=44 FAIL=0 |
| `bash tests/test-mega-merge.sh` | 0 | 55/55 passed |
| `bash tests/test-mega-reconcile.sh` | 0 | 35/35 passed |
| `bash tests/test-mega-gate-parity.sh` | 0 | PASS=12 FAIL=0 |
| `bash tests/test-meta.sh` | 0 | 902/902 passed |
| `bash lib/gate/doc-projection-check.sh .` | 0 | no drift |
| `bash tests/test-goal-dispatch.sh` | 0 | 20/20 passed |
| `bash tests/test-lane-classify.sh` | 0 | 38/38 passed |
| `bash tests/test-ledger-durability.sh` | 0 | 37/37 passed |
| `bash tests/test-orchestrate-gate-dispatch.sh` | 0 | ALL PASS |

## End-to-end leg

`bash docs/verification/mega-gate-pr-head-e2e.sh` runs the real `mega-merge.sh`, the real `gate-ledger.sh` (in a temp log dir, a normal-lane run with every normal gate recorded) and the real `git fetch` from a local bare origin. Origin carries `refs/heads/main`, `refs/heads/mega/x` (one commit adding a migration), `refs/pull/7/head` (adds `src/auth/login.ts`, base `main`) and `refs/pull/8/head` (README only, base `mega/x`). Only `gh` is faked: it answers the head, base, state and file-list reads and records `pr merge`. The checkout stays on `main`.

```
checkout on: main; origin carries: refs/heads/main refs/heads/mega/x refs/pull/7/head refs/pull/8/head
ok - PR 7 touches src/auth, base main: refused on the hard path (exit 1, merged=0)
    |   BLOCKED: ship-gate. This diff touches a hard path (auth: src/auth/login.ts); the full lane's gates apply whatever the spec's Lane says:
ok - PR 8 README-only on mega/x: merges despite mega/x's earlier migration (exit 0, merged=1)
    | EXECUTING: gh pr merge 8 --squash --delete-branch --match-head-commit 708a2badf58ab6ba2881e8e109dfa5ab2eea0510
private refs left: []
ok - PR 8 head moves after the pin: refused (exit 1, merged=0)
    | BLOCKED: PR #8 head moved after it was pinned (708a2badf58ab6ba2881e8e109dfa5ab2eea0510); refusing auto-merge, rerun to pin the new head.
```

## Negative controls

The new cases were committed against the old code first. Against the code before this change, 13 of the 17 head-mode cases and 14 of the 18 merge cases went RED (extra `gate` arguments were ignored and `merge` gated on the local `HEAD`), then GREEN after the fix. The cases that stayed green on the old code are the positive controls (no `--head` passes, a small spec passes, a stub that prints a real tip merges).

One control through `lib/gate/negctl.sh`: the mutation makes head mode run the floor on the local `HEAD` instead of the given commit. Four cases go RED: `head-mode-floor-hits`, `merge-floor-sees-pr-head`, `merge-mega-base` and `merge-mega-base against main`.

```
Command: bash tests/test-mega-gate-head.sh
Exit: 0 (green before mutation)
  PASS=44 FAIL=0

Mutation: sed -i '' '/^_ship_rules_gate_head()/,/^}/ s/ship_rule_floor "$root" "$base" "$head"/ship_rule_floor "$root" "$base" HEAD/' lib/goal/mega-merge.sh
Changed: lib/goal/mega-merge.sh
Exit: 1 (under mutation, RED expected)
  PASS=40 FAIL=4

Restore: git checkout HEAD -- lib/goal/mega-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Security review fixes

A review found five holes in head mode. Each got a test first, run against the pre-fix `lib/` (commit `2429794d`), then green after the fix.

| # | Hole | Fix | Case |
|---|------|-----|------|
| 1 | Config read at the author-chosen merge base | Read at the base-branch tip; the base only scopes the diff | `head-mode-config-at-tip` |
| 2 | `extra_hard_paths` from the working tree only | Also union the copy committed at the tip | `head-mode-extras-at-tip` |
| 3 | Base equal to head makes the floor vacuous | Refuse when `merge-base == H` | `head-mode-base-is-head` |
| 4 | Unvalidated `MEGA_MERGE_FETCH_TIMEOUT` reaches `$(( ))` | Digits only, checked before the fetch | `merge-fetch-timeout-value` |
| 5 | Criss-cross merges have several bases | Refuse when `merge-base --all` returns more than one | `head-mode-criss-cross` |

```
Command: git checkout 2429794d -- lib && bash tests/test-mega-gate-head.sh   (new cases, old code)
Exit: 1 (RED expected)
  NOT ok - head-mode-config-at-tip: got 0|
  NOT ok - head-mode-extras-at-tip: got 0|
  NOT ok - head-mode-base-is-head same: got 0|
  NOT ok - head-mode-base-is-head ancestor: got 0|
  NOT ok - head-mode-criss-cross: got 0|
  NOT ok - merge-fetch-timeout-value 'abc': got 1|<worktree>
  NOT ok - merge-fetch-timeout-value '-5': got 1|BLOCKED: cannot fetch PR #7 head or base from origin; failing c
  NOT ok - merge-fetch-timeout-value '1.5': got 1|<worktree>
  NOT ok - merge-fetch-timeout-value '1 2': got 1|<worktree>
  NOT ok - merge-fetch-timeout-value 'a[$(touch /var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T/tmp.ZCD6lnkiXa/
  NOT ok - merge-clean-pr-head: left refs
  PASS=46 FAIL=11

Restore: git checkout HEAD -- lib
Command: bash tests/test-mega-gate-head.sh
Exit: 0 (green after the fixes)
  PASS=57 FAIL=0

Command: bash tests/test-mega-merge.sh          Exit: 0   === 55/55 passed, 0 failed ===
Command: bash tests/test-mega-reconcile.sh      Exit: 0   === 35/35 passed, 0 failed ===
Command: bash tests/test-mega-gate-parity.sh    Exit: 0   PASS=12 FAIL=0
Command: bash tests/test-lanes-data.sh          Exit: 0   83 PASS lines, no FAIL
Command: bash tests/test-lane-classify.sh       Exit: 0   === 38/38 passed, 0 failed ===
Verdict: PASS
```

The no-`--head` hook path is unchanged: `ship_rule_floor` is called with six arguments and the classifier reads `${KIT_FLOOR_CONFIG_AT:-$base}` with the variable set to empty, so `test-mega-gate-parity.sh` stays green. `hooks/` did not change, so `hooks/codex-hooks.json` is not repinned.

## Not proven

- GitHub's own behavior: that `refs/pull/<n>/head` exists for a fork PR and is current a moment after a push rests on GitHub's documented behavior and the SPEC grounding sample; no test talks to a real PR. A merge right after a push can refuse with "head moved"; a rerun pins the new head.
- A refusal for "head moved" returns 1 from `merge`; in the wave converge loop (`lib/queue/orchestrate.sh`) that stops the whole wave until a rerun. Not exercised here.
- The fetch timeout kills `git`, not its helper children, and is tested only with a fake `git` that hangs.
- A base retarget between the second base read and GitHub's merge is not covered (SECURITY.md).
- The large-spec rule reads the spec the PR itself chooses, the same as the hook on push (SECURITY.md).
- Other merge paths (`stack-merge.sh`, `wrap-land.sh`, `wrap merge --apply`, a direct `gh pr merge`) stay unguarded (out of scope).

## Reproduce

```
bash tests/test-mega-gate-head.sh && bash tests/test-mega-merge.sh && bash tests/test-mega-reconcile.sh && bash tests/test-mega-gate-parity.sh && bash tests/test-meta.sh && bash lib/gate/doc-projection-check.sh . && bash docs/verification/mega-gate-pr-head-e2e.sh
```
