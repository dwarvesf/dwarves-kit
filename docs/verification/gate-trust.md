# Proof of done: the ship-gate cross-checks the review verdict, and a lane amend can only raise

Acceptance: (1) `hooks/ship-gate.sh` exits 2 on `git push` and `gh pr create` when the spec's last `## Review` verdict differs from the last verdict a review recorded in the run ledger, under the existing `[gate] review_verdict` key; a run with no ledger verdict behaves as before. (2) `gate-ledger.sh start --amend` refuses (exit 65, nothing written) to lower a run's lane unless `--lower --reason "<text>"` is given, which also appends a `GATE | lane-lower | override` line. Lane: normal (the diff touches `hooks/` and `lib/gate/`; the classifier said normal). Files: `hooks/ship-gate.sh`, `lib/gate/ship-rules.sh`, `lib/gate/gate-ledger.sh`, `docs/hard-rules.tsv`, `commands/{review,review-team,battery}.md`, `lib/gate/README.md`, tests.

## The gap this closes

| Risk | Before | After |
|---|---|---|
| Gates that only detect | A branch edited `### Verdict: DO NOT SHIP` to `SHIP` in its own spec and the push passed | The spec verdict must equal the last ledger verdict; a difference blocks and names both |
| Ledger trust | Any writer ran `start --amend <rid> tiny ...` on a full run and ship-gate dropped the full gates | The same call exits 65; only `--lower --reason` lowers, and it leaves an override line |

## Green run

| Suite | Command | Result |
|---|---|---|
| amend guard + verdict reader (new) | `bash tests/test-gate-ledger-amend.sh` | 39/39 |
| ship-gate verdict rule + ledger cross-check | `bash tests/test-ship-gate-review-verdict.sh` | pass=54 fail=0  |
| ship-gate lane resolution with amend | `bash tests/test-ship-gate-fail-closed.sh` | PASS=12 FAIL=0 |
| hard-claim registry | `bash tests/test-meta-hard-claims.sh` | 25/25 |
| docs and feature registry freshness | `bash tests/test-meta-docs-registry.sh` | 120/120 |
| gate-ledger usage text | `bash tests/test-gate-ledger-usage.sh` | 12/12 |
| lane escalation re-plan | `bash tests/test-lane-escalation.sh` | 24/24 |
| lanes as data | `bash tests/test-lanes-data.sh` | rc=0 (83 PASS lines) |
| implementation-notes rule | `bash tests/test-ship-gate-impl-notes.sh` | rc=0 (19 ok lines) |
| hooks | `bash tests/test-hooks.sh` | Passed: 813, rc=0 |
| lane telemetry, meta runner | `bash tests/test-lane-telemetry.sh`, `bash tests/test-meta.sh` | rc=0 each |

```
Command: bash tests/test-gate-ledger-amend.sh
Exit: 0
Output:
  PASS full -> tiny: exit 65
  PASS full -> tiny with --lower --reason: accepted
  PASS an override-style line records from, to and the reason
  PASS the last record wins: FIX THEN SHIP
  gate-ledger amend: 39/39 passed
Verdict: PASS

Command: bash tests/test-ship-gate-review-verdict.sh
Exit: 0
Output:
  ok - ledger DO NOT SHIP, spec edited to SHIP: blocks and names both
  ok - ledger and spec agree on SHIP: passes
  ok - no ledger verdict (unparseable record only): spec alone decides, SHIP passes
  ok - key off: the ledger cross-check is off too
  pass=54 fail=0
Verdict: PASS
```

One suite is red on master and is not touched by this branch: `tests/test-outcome-emit-sweep.sh` reports `ORPHAN: debug.md (debug)`; it fails the same way with this branch's changes stashed.

## Negative control

The three code files are reverted to the merge base, the new suites run, then the files are restored (`lib/gate/negctl.sh`, run after the commit).

```
Command: bash tests/test-gate-ledger-amend.sh
Mutation: git checkout 83083b13 -- lib/gate/gate-ledger.sh lib/gate/ship-rules.sh hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)   gate-ledger amend: 13/33 passed
Restore: git checkout HEAD -- hooks/ship-gate.sh lib/gate/gate-ledger.sh lib/gate/ship-rules.sh
Exit: 0 (green after restore)
Verdict: PASS

Command: bash tests/test-ship-gate-review-verdict.sh
Mutation: same three files at the merge base
Exit: 1 (under mutation, RED expected)   pass=45 fail=8
Restore: same
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
bash tests/test-gate-ledger-amend.sh
bash tests/test-ship-gate-review-verdict.sh
bash tests/test-meta-hard-claims.sh
```

## Rollback

Revert the PR. Nothing is migrated: the ledger format gains one optional `GATE | lane-lower | override` line and no existing line changes, so ledgers written before or after the revert read the same. To turn only the cross-check off on a repo, set `review_verdict = false` under `[gate]` in a committed `.kit.toml`; there is no switch for the amend guard, because a refused amend writes nothing and `--lower --reason` is the sanctioned way through.
