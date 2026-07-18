# Proof of done: repo-scoped proof-of-done override log (ID-299)

**Change class:** behavioral (`lib/gate/proof-ledger.sh`).

**Claim:** the proof-of-done override log (`proof-overrides.log`, machine-local, read
by the ship-gate via `lib/gate/proof-ledger.sh`) now keys each entry by **repo +
slug** instead of slug alone. An override logged in one repo can no longer
short-circuit the ship-gate for the same branch slug in an unrelated repo (the
family-office `backlog-reconcile` override that hid a real proof on a console-labs
push on the same slug).

## Design (as shipped, after review)

- `_repo_id(dir)` = the **git common dir's parent** (`git rev-parse --git-common-dir`,
  made absolute, `/.git` stripped). Keying on this (not `--show-toplevel`) means all
  worktrees of one repo share a key, which matters under the kit's own always-worktree
  policy. The **raw absolute path** is the key (not a lossy slug: `tr '/ ' '--'`
  collapsed `foo/bar` and `foo-bar` onto the same id); only `|` is stripped for
  delimiter safety. Non-git dir falls back to the absolute cwd (`pwd -P`).
- `override <slug> <reason>` derives the repo from cwd and writes
  `<ts> | <repo> | <slug> | OVERRIDE | <reason>`. It **refuses when cwd is not a git
  repo** so a misdirected override never logs a dead entry (the write twin of check()'s
  explicit `$root` read; also closes the cwd-ambiguity class recorded in
  `_meta/megagoals/_archive/kit-north-star/FEEDBACK.md`).
- `is_overridden <slug> [root]` matches by **field position** with awk (FS `|`, trimmed):
  `$2==repo && $3==slug && $4=="OVERRIDE"`. A substring `grep` let a crafted `reason`
  embedding `| <victim-repo> | <victim-slug> |` forge a match; field-anchoring puts the
  reason at field 5+, so it can never shift or forge fields 2-4.
- `check()` passes its `$root` into `is_overridden`, and on a block prints a hint when an
  override for the slug exists but is scoped to a different repo (so an operator does not
  re-log and see it "still do nothing").

## Migration (backward compat)

Legacy entries carry no repo field (their `$4` is not `OVERRIDE`), so they match **no**
repo's lookup and fail **closed** (worst case: re-log the override in the repo that needs
it; a wrongful cross-repo PASS can no longer happen).

## Review disposition (review-team + fable advisor)

| Finding | Lens | Applied? |
|---|---|---|
| `grep -qF` substring lets a pipe-bearing `reason` forge a cross-repo match (CRITICAL) | security | Applied, field-anchored awk match + a forge test |
| `test-deployable-done.sh` regressed 16/17 (override not run from the fixture; proof never ran that suite) | architecture | Applied, cd the override calls; suite added to CI + confirmation table |
| Cross-repo AC2 used a SOURCE file → cc-hyg-04 blocks it regardless of scoping → not load-bearing | test-coverage | Applied, AC2 now uses a deploy-inert change (the real bug shape) |
| `--show-toplevel` breaks under always-worktree policy | fable + architecture | Applied, key on `--git-common-dir` (unifies worktrees) + a worktree repro |
| slugify collapses `/`↔`-` (collision) + non-git fallback relative | security + architecture | Applied, raw absolute path key, `pwd -P` fallback |
| `override` silently cwd-dependent (footgun) | fable + architecture | Applied, refuses on non-git cwd; contract documented |
| Silent fail-closed block (no "why") | fable | Applied, block prints a scoped-elsewhere hint |
| Stale downstream schema doc (3-field → 4-field) | architecture | Applied, `lib/stats/docs/ledger-event-schema.md` updated |
| No subdir-override coverage | test-coverage | Applied, subdir-override test added |

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | An override applies in the repo it was logged (incl. from a subdir) | PASS |
| 2 | Repo A's override does NOT excuse the same DEPLOY-INERT slug in repo B (load-bearing) | PASS |
| 3 | A repo's OWN override applies to it | PASS |
| 4 | A legacy unqualified entry fails closed | PASS |
| 5 | A pipe-bearing `reason` cannot forge a cross-repo override | PASS |
| 6 | Worktrees of one repo share a key; `override` refuses outside a git repo | PASS (repro below) |
| 7 | Existing behavior preserved (cc-hyg-04, deployable-done, blanket-reason) | PASS |

## Confirmation run

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Hook suite (incl. 7 ID-299 assertions) | `bash tests/test-hooks.sh` | 0 | PASS (487/487) |
| Deployable-done (override AC4/AC4b) | `bash tests/test-deployable-done.sh` | 0 | PASS (17/17) |
| Ledger-durability (override AC5/AC6) | `bash tests/test-ledger-durability.sh` | 0 | PASS (37/37) |
| Meta suite | `bash tests/test-meta.sh` | 0 | PASS (698/698) |

Recorded run (verbatim):

```
Command: bash tests/test-hooks.sh
Exit: 0        # Passed: 487 / 487
Command: bash tests/test-deployable-done.sh
Exit: 0        # 17/17 passed
Command: bash tests/test-ledger-durability.sh
Exit: 0        # 37/37 passed
Command: bash tests/test-meta.sh
Exit: 0        # Passed: 698 / 698
Verdict: PASS
```

## Coverage (branch enumeration)

Every changed decision path is exercised: same-repo match (AC1), cross-repo no-match on
the load-bearing deploy-inert shape (AC2), own-override (AC3), legacy fail-closed (AC4),
reason-forge blocked (AC5), subdir override (AC1 subdir). Worktree unification and the
non-git `override` refusal are shown in the repro below.

## NEGATIVE CONTROL

Field-anchored match vs the pre-fix substring, and the deploy-inert cross-repo shape:

```
# forge attempt: override in repo I with reason "ok | <repoV> | forge |"
# pre-fix grep -qF "| <repoV> | forge |"  -> MATCH (forged, VULNERABLE)
# post-fix awk $2/$3/$4 field match        -> no match (injection blocked)

# cross-repo deploy-inert: A has an override for slug 'recon'; B (deploy-inert, same slug)
# pre-fix global match  -> B passes on A's override (the family-office->console-labs bug)
# post-fix repo-scoped  -> B blocks (exit 1)   [AC2, load-bearing]
```

Live repro (worktree unification + non-git refusal):

```
override in repo A -> is-overridden A = 0, is-overridden B = 1 (no collision)
worktree of A (.claude/worktrees/wt1) -> is-overridden = 0 (shares A's key)
override from a non-git dir -> "cwd is not a git repo ... nothing logged", exit 66
```

**Verdict: PASS.**

## Reproduce

```
bash tests/test-hooks.sh            # 487/487, ID-299 block
bash tests/test-deployable-done.sh  # 17/17
bash tests/test-ledger-durability.sh
bash tests/test-meta.sh
```

**Rollback:** `git revert` this commit restores the slug-only global match; no state or
schema migration (the log is machine-local and append-only; old entries stay readable and
simply match no repo under the new scoped lookup).
