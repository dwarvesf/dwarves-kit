# Proof of done: fold the mega engine into lib/mega/ (ID-287, sanctioned slice)

**Change class:** behavioral (moved `.sh`/`.py` + repointed callers in `bin/`, `lib/`, `tests/`).

**Claim.** The three loose mega-goal scripts move from `lib/` root into a cohesive
`lib/mega/` module as a unit, with every live reference repointed and every
root-assuming internal anchor re-anchored one level up:

- `lib/mega.sh` -> `lib/mega/mega.sh`
- `lib/mega-report.py` -> `lib/mega/mega-report.py`
- `lib/mega-review.py` -> `lib/mega/mega-review.py`

## Why this slice (and not the other loose files)

`lib/config/module-registry.md` already registers a **`mega` module** (row :49
"mega | Build (Execute) | spine machinery") and ADR-0034 explicitly names
`lib/mega/mega.sh` + `bin/mega` as the promotion target, so this move is sanctioned
and the three files must move together (they call each other by same-dir path). The
other four loose files (`adopt.sh`, `explain.sh`, `pitch.sh`, `precedent.sh`) are
labeled **"deliberate orphans, no cluster"** by both `lib/README.md` and
`docs/decisions/0034` (bin-less, command-invoked, not module CLIs). Foldering them
into single-file dirs conflicts with that ADR, a source-of-truth question a human
must settle, so they are deferred to a follow-up with that ruling. `onboard-detect.sh`
has no obvious module home either (lib/session vs a new lib/onboard). See the batch
report.

## Internal anchor edits (root-assuming -> one-level-deeper)

- `mega.sh`: `source "$self_dir/telemetry/..."` -> `"$self_dir/../telemetry/..."` (x2).
  The `$self_dir/mega-review.py` / `mega-report.py` calls stay (same-dir, co-moved).
- `mega-review.py`: `os.path.join(_SELF_DIR, "gate"...)` and `"learn"...` gain a `".."`;
  the `mega.sh` join stays (same-dir).
- `mega-report.py`: no internal path anchor (arg-driven), no edit.

## Repointed live references

`bin/mega:12` (the stable forwarder), `lib/board/board.sh:183` (computed
`$BOARD_DIR/../mega/mega.sh`), `lib/queue/orchestrate.sh:1745` + WARN string,
`tests/test-mega.sh`, `tests/test-mega-review.sh`, `tests/test-mega-report.sh`,
`lib/config/module-registry.md:113,284`, and a `lib/mega/` row added to
`lib/README.md`. Comment references in the moved files + `board.sh` + `test-tier4-close.sh`
updated for accuracy. Historical records left untouched.

## Review disposition (review-team + fable advisor)

| Finding | Lens | Applied? |
|---|---|---|
| `cmd_report`'s re-anchored telemetry `source` had zero red-on-wrong coverage (the mega-report tests call python directly; the one `bin/mega report` call passed no slug) | test-coverage (HIGH) | Applied, added an end-to-end `bin/mega report demo` launcher assertion in `test-mega-report.sh`; verified load-bearing (broken anchor -> 15/17, restored -> 17/17) |
| `docs/consumer-contract.md:64` `bin/mega -> lib/mega.sh` stale post-move (a live onboarding ref, not historical) | architecture (LOW) | Applied -> `lib/mega/mega.sh` |
| `mega.sh` header still framed the file as a deliberate orphan awaiting promotion; `mega-review.py:53` `_SELF_DIR` comment said "lib/ ... orphan file" | architecture (MEDIUM/LOW) + fable + security | Applied, both rewritten to describe the `lib/mega/` module |
| Re-anchoring complete/correct; taxonomy right (mega is a distinct `mega` module, not `goal`); orphan deferral correct (not over-reading ADR-0034) | architecture 8/10, fable, security 10/10 | Confirmed, no change |
| `onboard-detect.sh` absent from `lib/README.md` root-orphans row | fable/architecture | Pre-existing gap, reported for the orphan follow-up (not this branch's regression) |

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | The three files live in `lib/mega/`; old `lib/mega.sh` path gone | PASS |
| 2 | `bin/mega` forwarder reaches the engine at the new path | PASS (30/30 forwarders) |
| 3 | Internal anchors resolve telemetry/gate/learn siblings from the new depth | PASS (mega suites green) |
| 4 | No live (non-doc) reference to an old `lib/mega*.{sh,py}` path remains | PASS |
| 5 | All affected suites green | PASS |

## Confirmation run

```
Command: [ ! -f lib/mega.sh ] && ls lib/mega/
Exit: 0        # mega.sh mega-report.py mega-review.py
Command: rg 'lib/mega\.sh|lib/mega-report\.py|lib/mega-review\.py' bin/ lib/ tests/ --glob '!*.md' | grep -v 'lib/mega/'
Exit: 1        # no un-repointed live ref remains
Command: bash tests/test-mega.sh
Exit: 0
Command: bash tests/test-mega-review.sh
Exit: 0        # 26 passed
Command: bash tests/test-mega-report.sh
Exit: 0
Command: bash tests/test-bin-forwarders.sh
Exit: 0        # all 30 passed
Command: bash tests/test-tier4-close.sh
Exit: 0
Command: bash tests/test-meta.sh
Exit: 0        # Passed: 717 / 717
Command: bash tests/test-hooks.sh
Exit: 0        # Passed: 487 / 487
Verdict: PASS
```

## NEGATIVE CONTROL

The `bin/mega` repoint is load-bearing. Revert only it to the old path and the
forwarder can no longer reach the engine:

```
# revert bin/mega:12 to ../lib/mega.sh (old path):
bash tests/test-bin-forwarders.sh
  -> FAIL: mega forwarder reaches mega.sh   (29 passed, 1 FAILED)   [RED]
# restore ../lib/mega/mega.sh:
bash tests/test-bin-forwarders.sh
  -> all 30 passed, 0 skipped                                        [GREEN]
```

**Verdict: PASS.**

## Reproduce

```
bash tests/test-mega.sh tests/test-mega-review.sh tests/test-mega-report.sh
bash tests/test-bin-forwarders.sh    # 30/30 (the bin/mega forwarder)
bash tests/test-meta.sh              # 717/717
bash tests/test-hooks.sh             # 487/487
```

**Rollback:** `git revert` this commit (`git mv` back + restore the anchors/refs); no
state or data step.
