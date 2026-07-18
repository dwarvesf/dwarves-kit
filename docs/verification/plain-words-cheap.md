# Proof of done: plain-words rename (verify-counts + SDD), ID-291 first slice

**Change class:** behavioral (`lib/gate/gate.sh`, the renamed `lib/gate/verify-counts.sh`).

**Claim.** Two zero-risk items of the ID-291 plain-words cluster land:
1. `lib/gate/verif-counts.sh` -> `lib/gate/verify-counts.sh` (the coordinator-emphasized
   file rename), with every LIVE reference swept (the `gate` dispatch, its `--help` text,
   the module registry, both READMEs, the `docs/verification/COUNTS.md` generator pointer,
   and the `test-meta.sh` existence assertion), and `verif-counts` kept as a legacy verb
   alias for one release (ID-292 precedent).
2. `SDD` spelled out on first use (`spec-driven development (SDD)`) in the two onboarding
   docs where it first appears (`AGENTS.md`, `docs/PHILOSOPHY.md`).

Historical records (research, specs, `_meta/megagoals/_archive`, CHANGELOG, audits,
implementation-notes, shipped verification records) are left untouched per the ID-292
precedent: they document the name-at-the-time.

## Scope note (honest first slice)

The remaining ID-291 cluster items proved code/command/config-entangled after the
2026-07-16..18 wave merges (#269-#274) embedded these terms in code, so the inventory's
"docs/cfg cheap" estimate is stale. They are deferred to dedicated PRs (see the batch
report): `spoke` (semantic in `lib/sync/*.py`), `grill` (a command + 6 test files),
`spine` (install.sh `KIT_SPINE_HOOKS` + config), `cockpit` (`lib/sync/cockpit.py` + verb),
`brownfield` (a `lane-classify` anchor), `wave`/`tier`/`posture` (config keys with no
generic alias resolver), `RID` (the `rid` identifier in 8 test suites).

## Review disposition (review-team + fable advisor)

| Finding | Lens | Applied? |
|---|---|---|
| The `gate.sh` dispatcher routing (both `verify-counts` and legacy `verif-counts`) had no automated coverage; the alias claim rested on a manual grep | test-coverage (MEDIUM/LOW) | Applied, added a stubbed dispatch-routing test in `test-meta.sh` (both verbs), CI-enforced |
| Deferring the code-entangled remainder is correct; the honest-slice warning should also reach the ID-291 backlog row | fable | Reported to the board scribe (I do not edit the board) |
| COUNTS.md freshness is unenforced (it sat stale at 368/164) | fable | Pre-existing gap; regenerated here to the true count, and reported as a follow-up (a live-count assertion would slow every meta run, so it is its own item) |
| The `(one release)` alias has no removal tracking (no kit release cadence) | fable | Matches the standing CONTRIBUTING.md "Plain words rule" §3 convention (architecture lens confirmed); alias-removal reported to the scribe as a follow-up row |
| Security / architecture | both | 10/10 clean, no change requested |

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | `verify-counts.sh` exists + executable; old path gone | PASS |
| 2 | Both `gate verify-counts` and legacy `gate verif-counts` route to the new file | PASS |
| 3 | No live (non-doc) reference to the old filename remains (only the intentional alias) | PASS |
| 4 | `SDD` defined on first use in AGENTS.md + PHILOSOPHY.md | PASS |
| 5 | Full meta suite green | PASS (717/717) |

## Confirmation run

```
Command: [ -x lib/gate/verify-counts.sh ] && [ ! -f lib/gate/verif-counts.sh ] && echo OK
Exit: 0        # OK: renamed, executable, old path gone
Command: grep -n 'verify-counts|verif-counts) exec bash "$GATE_DIR/verify-counts.sh"' lib/gate/gate.sh
Exit: 0        # both verbs wired to the new file
Command: rg -n 'verif-counts' lib/ tests/ --glob '!*.md' | grep -v 'legacy alias'
Exit: 1        # no live non-doc refs to the old name remain
Command: bash tests/test-meta.sh
Exit: 0        # Passed: 717 / 717
Verdict: PASS
```

## NEGATIVE CONTROL

The `test-meta.sh` assertion `lib/gate/verify-counts.sh exists and is executable` is
load-bearing on the ref sweep: had the rename been done WITHOUT updating that assertion
(or without updating `gate.sh`'s exec path), meta would be RED (it would look for the file
at the old path). Reverting only the `git mv` while keeping the swept references
reproduces the failure:

```
# revert the file move but keep the swept test assertion:
mv lib/gate/verify-counts.sh lib/gate/verif-counts.sh
bash tests/test-meta.sh   -> FAIL "lib/gate/verify-counts.sh exists and is executable"  (RED)
# restore:
mv lib/gate/verif-counts.sh lib/gate/verify-counts.sh
bash tests/test-meta.sh   -> 717/717  (GREEN)
```

**Verdict: PASS.**

## Reproduce

```
bash tests/test-meta.sh                 # 717/717
bash lib/gate/gate.sh verify-counts     # regenerates docs/verification/COUNTS.md (runs the suites)
bash lib/gate/gate.sh verif-counts      # legacy alias, same target
```

**Rollback:** `git revert` this commit restores the old filename + `SDD` shorthand; no
state or data step (a file rename + doc-string edits).
