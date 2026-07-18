# Proof of done: repo-scoped proof-of-done override log (ID-299)

**Change class:** behavioral (`lib/gate/proof-ledger.sh`).

**Claim:** the proof-of-done override log (`proof-overrides.log`, machine-local, read
by the ship-gate via `lib/gate/proof-ledger.sh`) now keys each entry by **repo +
slug** instead of slug alone. An override logged in one repo can no longer
short-circuit the ship-gate for the same branch slug in an unrelated repo (the
family-office `backlog-reconcile` override that hid a real proof on a console-labs
push on the same slug). Migration: legacy entries with no repo field match no repo's
lookup, so a stale global override fails **closed** (worst case: re-log the override
in the repo that needs it; a wrongful cross-repo PASS can no longer happen).

## Design

- `_repo_id(dir)` resolves the git toplevel path (always available, collision-proof
  between distinct checkouts) and slugifies it. Non-git dir falls back to the dir
  path, so an override is still scoped, never global.
- `override <slug> <reason>` derives the repo from cwd (the repo the operator is
  overriding for) and writes `<ts> | <repo> | <slug> | OVERRIDE | <reason>`.
- `is_overridden <slug> [root]` resolves the repo from `root` (the ship-gate passes
  the pushed repo's root) and matches `| <repo> | <slug> |`, repo-scoped only.
- `check()` passes its `$root` into `is_overridden`, so the write (cwd) and the
  lookup (ship-gate root) resolve to the same toplevel.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | An override applies in the repo it was logged | PASS |
| 2 | Repo A's override does NOT excuse the same slug in repo B | PASS |
| 3 | A repo's OWN override applies to it (scoping is per-repo, not a global block) | PASS |
| 4 | A legacy unqualified entry fails closed (matches no repo) | PASS |
| 5 | Existing override behavior preserved (cc-hyg-04 source-reject, deploy-inert pass, blanket-reason reject) | PASS |
| 6 | Full suites green | PASS |

## Coverage (branch enumeration)

Bash has no line-coverage tool here, so coverage is by enumeration. The changed
decision paths and their exercising tests (in `tests/test-hooks.sh`, ID-299 block):
override-match-same-repo (AC1/AC3), no-match-other-repo (AC2), legacy-no-repo-field
fail-closed (AC4), plus the five pre-existing override tests re-run under the new
scoping (AC5). Every changed branch is covered.

## Confirmation run

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Hook suite (incl. 5 new ID-299 assertions) | `bash tests/test-hooks.sh` | 0 | PASS (485/485) |
| Ledger-durability (override AC5/AC6) | `bash tests/test-ledger-durability.sh` | 0 | PASS (37/37) |
| Meta suite | `bash tests/test-meta.sh` | 0 | PASS (698/698) |

## Run detail

```
PASS ledger: override on SOURCE -> still REJECTED (cc-hyg-04)
PASS ledger: override on deploy-inert -> PASS (cc-hyg-04)
PASS ID-299: an override applies in the repo it was logged (A)
PASS ID-299: repo A's override does NOT excuse the same slug in repo B
PASS ID-299: a fresh repo with the same slug still BLOCKs pre-override
PASS ID-299: a repo's OWN override applies to it
PASS ID-299: a legacy unqualified override fails CLOSED (matches no repo)
...
Passed: 485 / 485
```

## NEGATIVE CONTROL

Log an override for slug `recon` in repo A, then check the same slug from repo B:

```
log: 2026-07-18T00:00:00Z | <repoA> | recon | OVERRIDE | A reason

# PRE-FIX global match (grep '| recon |'), repo B:
RED: B matches A's override -> ship-gate short-circuited (bug reproduced)

# POST-FIX repo-scoped match (grep '| <repoB> | recon |'), repo B:
GREEN: B does NOT match -> collision fixed
```

The pre-fix global-match logic matches A's override from repo B (the exact
collision ID-299 describes); the repo-scoped match does not. The AC2 test asserts
exit 1 (B blocked), which is RED against the pre-fix code and GREEN against the fix,
so the test is load-bearing on the change.

## Reproduce

```
bash tests/test-hooks.sh            # 485/485, includes the ID-299 block
bash tests/test-ledger-durability.sh
bash tests/test-meta.sh
```

**Rollback:** `git revert` this commit restores the slug-only global match; no state
or schema migration is involved (the log is machine-local and append-only, and old
entries remain readable, they simply no longer match under the new scoped lookup).
