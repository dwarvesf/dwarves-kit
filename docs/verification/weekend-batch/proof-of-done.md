# Proof of done: weekend-batch (SPEC-126)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | Collects the week's deferred+waved debt-ledger items + resolves impl-notes/explainers (both naming conventions) | PASS (5/5 sub-checks) | `bash tests/test-weekend-batch.sh` AC1a-e |
| AC2 | The dotfiles skill routes through `learning-day-process` + `learning-ledger` + `deep-understand` + a privacy-stripped `til` flush | PASS (5/5) | AC2a-e, grepped against `~/workspace/<owner>/dotfiles/home/dot_claude/skills/weekend-debt-paydown/SKILL.md` (present on this machine; SKIPS gracefully in CI where that path is absent, same precedent as SPEC-107) |
| AC3a | **NEGATIVE CONTROL:** an already-engaged (paid) item is not re-collected | PASS (2/2) | seeded a `tap`, ran the REAL `mark-paid` codepath, re-ran `list`, confirmed absence |
| AC3b | **NEGATIVE CONTROL:** a non-significant change (present in the raw ledger) never enters the collectible view; the still-open pending tap is also excluded | PASS (3/3) | AC3b + bonus |
| AC3c | Window scoping (`--days`) | PASS (2/2) | 30-day-old item excluded by default, included at `--days 400` |
| AC3d | Repo scoping (`--repo` / `--all-repos`) | PASS (2/2) | other-repo item excluded by default, included with `--all-repos` |
| AC4 | **NEGATIVE CONTROL (reuse):** the skill invokes, never forks a second dedup/ledger/quiz engine | PASS (2/2) | grepped for a fork-tell (absent) + an explicit no-fork statement (present) |
| CD | Coverage delta | PASS | 0 -> 21 weekend-batch-specific assertions |

**Total: 22/22 PASS, 0 FAIL, 0 SKIP** (all checks ran; the dotfiles path happened to be present on
this run).

## Implementation

- `lib/queue/weekend-batch.sh` (new): `list` / `collect` / `mark-paid`, reads `$LOG_DIR/runs/*.log`
  (SPEC-097's resolver), writes only via the existing `gate-ledger.sh debt`.
- `lib/gate/gate-ledger.sh`: `debt()` gains the additive, optional `response=<engage|defer|wave>` key.
- `tests/test-weekend-batch.sh` (new): the run-table above.
- (dotfiles repo, branch `feat/ug-05-weekend-batch`, local commit, not pushed):
  `home/dot_claude/skills/weekend-debt-paydown/SKILL.md`.

## Confirmation run (green)

```
$ bash tests/test-weekend-batch.sh
...
=== Coverage delta ===
  PASS coverage delta: weekend-batch checks went from 0 to 21 in this suite

  ---------------------------------------------
  TOTAL: 22   PASS: 22   FAIL: 0   SKIP: 0
```

## Negative control (load-bearing, confirmed RED then reverted)

A targeted breakage of `lib/queue/weekend-batch.sh`'s disposition filter (accepting `paid` /
`not-significant` / `pending` as collectible, not just `waved`/`deferred`) was applied in-place,
the suite re-run, and the change reverted immediately after capturing the RED output:

```
$ bash tests/test-weekend-batch.sh   # (disposition filter neutered)
...
  FAIL AC3a [NC] ug-12-paid-item ABSENT from list after mark-paid
  ...
  FAIL AC3b [NC] ug-13-nonsig-item ABSENT from list (never collectible)
  FAIL AC3b [NC, bonus] the still-open ug-16-pending-item (tap, no response) is ALSO absent
  ---------------------------------------------
  TOTAL: 22   PASS: 19   FAIL: 3   SKIP: 0
```

Exactly the three negative-control assertions flip red (AC3a's exclusion check + both AC3b
checks); every other assertion (AC1, AC2, AC3c, AC3d, AC4) is unaffected, confirming they test
independent behavior. The file was restored immediately after (`lib/queue/weekend-batch.sh` verified
byte-identical to its pre-breakage state), and the suite re-confirmed GREEN (22/22).

## Also verified: no regression to sibling suites

```
$ bash tests/test-significance-classify.sh
=== 25/25 passed, 0 failed ===   # unaffected by the additive gate-ledger.sh response= field

$ bash tests/test-meta.sh
Passed: 665 / 665
All meta tests passed.
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-weekend-batch.sh
bash tests/test-significance-classify.sh
bash tests/test-meta.sh
```

For the negative control: edit `lib/queue/weekend-batch.sh`'s `_collectible_files()` case statement from
`case "$disp" in waved|deferred) ;; *) continue ;; esac` to also accept `paid|not-significant|
pending|unknown`, re-run `bash tests/test-weekend-batch.sh`, observe the 3 failures above, then
revert.
