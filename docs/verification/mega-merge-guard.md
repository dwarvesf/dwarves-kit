# Proof of done: mega-merge code-level exclusion (SPEC-100, kit-telemetry SG-05)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 [positive control] | clear + gate-passing PR still merges (dry-run) | `test-mega-merge.sh`: PR#1 -> "gh pr merge 1", exit 0 | PASS |
| AC2 [NC] | hold-labelled PR refused even with a passing gate | PR#2 (`do-not-merge`) -> BLOCKED, names the label, exit != 0 | PASS |
| AC3 [NC] | draft PR refused | PR#3 (draft) -> "is a draft" BLOCKED | PASS |
| AC4 [NC] | bracketed-title-marker PR refused | PR#4 (`[HOLD]`) -> "title carries a hold marker" BLOCKED | PASS |
| AC5 [NC, fail-closed] | unreadable state refused, no merge cmd printed | PR#5 (gh error) -> "cannot read PR" BLOCKED, exit != 0, no `gh pr merge` | PASS |
| AC6 | hold label among multiple labels still blocks | PR#6 (`ci-red,gated-final`) -> BLOCKED on `gated-final` | PASS |
| AC7 [gate preserved] | clear PR + failing gate still blocked by the gate | PR#1 + failing gate-ledger -> "ship-gate not satisfied" | PASS |
| AC8 [no regression] | sibling + full suites green | `test-mega-reconcile` 35/35, `test-meta` 578/578, `test-hooks` 438/438 | PASS |

## Implementation

- `lib/mega-merge.sh` -- `_pr_info` (PR state via `gh pr view --json`, US-delimited,
  test-injectable via `MEGA_MERGE_PR_INFO_CMD`) + `_merge_exclusion` (draft / hold-label /
  title-marker -> refuse; unreadable -> fail-closed) wired into `merge()` BEFORE the gate.
  Header comment updated (the hole is now closed in code, defense-in-depth over mega.md).
- `tests/test-mega-merge.sh` (new) -- 12 pins, fully offline (injected gate-ledger + PR-state).
- `tests/test-mega-reconcile.sh` -- clear PR-state stub so its fake-PR merge tests keep
  exercising the gate/posture path.
- `.github/workflows/test.yml` -- new suite wired into CI.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-mega-merge.sh` | 0 | 12/12 passed |
| `bash tests/test-mega-reconcile.sh` | 0 | 35/35 passed |
| `bash tests/test-meta.sh` | 0 | 578/578 passed |
| `bash tests/test-hooks.sh` | 0 | 438/438 passed |

## Run detail (the load-bearing exclusion negative controls)

```
# injected: gate-ledger always passes; PR-state selected by PR number
pr=1 (clear)             -> DRY-RUN gh pr merge 1        (would merge)
pr=2 (do-not-merge)      -> BLOCKED: carries the hold label 'do-not-merge'
pr=3 (draft)             -> BLOCKED: is a draft
pr=4 ([HOLD] title)      -> BLOCKED: title carries a hold marker
pr=5 (gh error)          -> BLOCKED: cannot read PR state (fail-closed)
pr=6 (ci-red,gated-final)-> BLOCKED: carries the hold label 'gated-final'
```
The exclusion runs even when the gate PASSES (AC2), and a clear PR with a FAILING gate is
still blocked by the gate (AC7) -- the guard adds a refusal, it never loosens one.

## Reproduce

```
bash tests/test-mega-merge.sh
```
