# Proof of done: mega-merge-mark (SPEC-104 / ID-089)

The SPEC-100 merge-guard loop is closed **for the `commands/mega.md`-driven PR-open path**:
mega.md opens gate/gated-final PRs marked (draft + `do-not-merge`), and the shipped
`_merge_exclusion` guard refuses exactly that state. Scope note (TIER-4): ID-089 also named the
bounded `/goal` loop's own gated-final PR-open step; that path is not auto-wired to `mark` here
(it currently relies on the human/loop calling `mark`, as this wave's own final PR does). The
durable close for every PR-open site is a `mega-merge sweep` follow-up (mega-goal NOTES
`## Proposed additions`), not this sub-goal.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | `lib/goal/mega-merge.sh mark` opens a held PR as draft + `do-not-merge` (label ensured idempotently) | PASS |
| 2 | Fed the state `mark` produces, `_merge_exclusion` refuses even with a passing gate (the halves meet) | PASS |
| 3 | A normal `auto` PR is un-marked and the guard clears it | PASS |
| 4 | `commands/mega.md` calls `mega-merge.sh mark` at the held-PR open step | PASS |
| 5 | `mark` VERIFIES the mark landed (reuses `_merge_exclusion`); WARNs + exits nonzero on a silent no-op (TIER-4 security fix) | PASS |
| 6 | `tests/test-mega-merge.sh` (30/30, bash 5 + 3.2) + `test-meta` + `test-hooks` + `test-e2e` green | PASS |

## Implementation

- `lib/goal/mega-merge.sh`: new `mark <pr> [repo]` verb -- ensure `do-not-merge` label (idempotent),
  convert to draft (`gh pr ready --undo`), add the label; gh via `MEGA_MERGE_GH`.
- `commands/mega.md`: held-PR step calls `mega-merge.sh mark <pr>`.
- `README.md` + `MANUAL.md`: document the mark verb / behavior.
- 8 pins added to `tests/test-mega-merge.sh`.

## Confirmation run-table

| Check | Command | Expected | Observed |
|---|---|---|---|
| mark issues the calls | `MEGA_MERGE_GH=mock mega-merge.sh mark 77` | label create + `pr ready 77 --undo` + `pr edit 77 --add-label do-not-merge` | all three issued |
| mark<->guard meet | feed the draft state to `merge 77 ... --execute` | BLOCKED (never calls gh merge) | `BLOCKED: ... PR #77 is a draft` |
| negative control | un-marked auto PR -> `merge` | clears + reaches the merge cmd | `gh pr merge 1` (dry-run) |
| suites | `test-mega-merge` / `test-meta` / `test-hooks` / `test-e2e` | all pass | 28/28 mega-merge; all green |

## Run detail (captured 2026-07-02)

```
$ MEGA_MERGE_GH=mock bash lib/goal/mega-merge.sh mark 77
marked PR #77 held: draft + do-not-merge
gh calls:
  gh label create do-not-merge --color B60205 --description held: do not auto-merge (mega gate/gated-final)
  gh pr ready 77 --undo
  gh pr edit 77 --add-label do-not-merge

$ merge 77 (fed the produced draft state, passing gate, --execute)
BLOCKED: refusing to auto-merge PR #77 -- PR #77 is a draft. Gated / held-final PRs are merged by a human, not the loop (mega-merge exclusion).
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-mega-merge.sh    # the mark pins + mark<->guard end-to-end + negative control
```

The mark is idempotent (all steps `|| true`); a normal `auto` PR is left un-marked so the guard
clears it. The SPEC-100 guard is byte-unchanged; this is the mark half only.
