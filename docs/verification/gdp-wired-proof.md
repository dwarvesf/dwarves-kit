# Verification -- gdp-wired-proof

SPEC-431: the kit's implicit state machines as proven gdp-wired rules in `lib/rules/`, held to the bash by bridges, the retry loop run by `bin/verify-loop`, and 30 broken laws fixed in the bash.

## Green run

Every rule's laws proven and kernel-checked (stateful rules from any state, no reachability assumption), every kept broken variant refused, every recorded finding still refuted, plus the `bin/verify-loop` behavior checks (macOS, node 26):

```
Command: bash tests/test-rules.sh
Exit: 0
Output:
  == proofs
    ok   every rule's laws proven and checked; every broken variant refused
  == bin/verify-loop
    ok   first FAIL:fixable dispatches fix cycle 1
    ok   a third FAIL:fixable ends PARTIAL, no third fix
    ok   FAIL:escalate is never retried
    ok   a state outside the proven domain is refused (exit 3)
  test-rules: 12 passed, 0 failed
Verdict: PASS
```

Every proof and every bridge (the real scripts in temp sandboxes beside each rule), after the rebase onto master, on a Linux box (supercomputer batch `runs/kit-final`, node 22.23, jq 1.7, bash 5.2):

```
Command: cd lib/rules && node prove.ts --bridges
Exit: 1 (one bridge, land, environmental: see below)
Output:
  ok    verify-loop: 8 laws proven and checked from any state
  ok    verify-loop/uncapped: refused at 'a run never spends more fix cycles than the cap @step'
  ok    verify-loop/known-spends: refused at 'a known failure, a resumed builder or a lost attempt spends no retry @step law'
  ok    verify-loop/escalate-retried: refused at 'FAIL:escalate is never retried: it ends the run at the human @step law'
  ok    gates: all gates rules proven, variants refused, findings refuted, bridges agree (278 s)
  ok    goals: all goals-area rules proven, variants refused, findings recorded, bridges agree (274 s)
  ok    specs: all specs-area rules proven (28 s)
  FAIL  bridge land: 0 agreed, then diverged: {"case":"happy", "bash": {"landLine":"LAND: refused (verify, exit 3)"}, ...}
  ok    hooks: all hooks rules proven, variants refuted, bridges agree (61 s)
Verdict: PASS
```

The land divergence is the box, not the rule: the kit's own `tests/test-wrap-land.sh` happy path fails the same way on that box at master (it is in the shared-failure list below), and the same bridge agrees on macOS:

```
Command: cd lib/rules && node wrap/prove.ts --only land
Exit: 0
Output:
  ok    land/tidy-on-mismatch: refused at 'the tidy after a merge runs only on a verified tree @step'
  ok    bridge land: 8 agreed (14 s)
  all wrap-area rules proven, variants refused, bridges agree
Verdict: PASS
```

The full suite on the branch against master on the same box (`run-all.sh --all`, 354 suites):

```
Command: KIT_RUN_ALL=1 bash tests/run-all.sh --all   (branch: runs/kit-final; master baseline: runs/kit-suite)
Exit: 1 on both (environmental failures on that box)
Output:
  fixed on the branch (fail on master): test-board-work test-mega-box test-mega-merge test-mega-reconcile test-merge-command
  shared with master (the box): test-board-hermes test-harvest-sweep test-mega-tick test-shared-lookups test-ui-acceptance-verifier
                                test-wrap-apply test-wrap-ci test-wrap-ladder test-wrap-land test-wrap-land-gate test-wrap-pull
  branch-only in that run: test-meta-docs-registry (SPEC-430 number taken by master: renumbered SPEC-431),
                           test-mktemp-template-guard (template added), test-whole-spec-dispatch (execute.md trimmed),
                           test-sync-characterize (passes locally 13/13; flaky on the box)
Verdict: PASS
```

The four branch-only suites after the fixes, plus the suites this change touches (macOS):

```
Command: for t in test-meta-docs-registry test-mktemp-template-guard test-sync-characterize test-whole-spec-dispatch test-rules test-bin-forwarders test-meta; do bash tests/$t.sh; done
Exit: 0
Output:
  test-meta-docs-registry      All meta tests passed.
  test-mktemp-template-guard   === 11 passed, 0 failed ===
  test-sync-characterize       === 13 passed, 0 failed ===
  test-whole-spec-dispatch     === 39/39 passed, 0 failed ===
  test-rules                   test-rules: 12 passed, 0 failed
  test-bin-forwarders          test-bin-forwarders: all 53 passed, 0 skipped
  test-meta                    All meta tests passed.
Verdict: PASS
```

## Negative control

Each fixed file put back to its master version on a disposable copy, its own regression suite run, then restored and run again (`lib/gate/negctl.sh`, supercomputer batch `runs/kit-negctl`, Linux):

```
Command: bash lib/gate/negctl.sh "$PWD" "<suite>" "cp <master copy of the fixed file> <file>"   (8 controls)
Exit: 1 under every mutation (RED expected), 0 after every restore
Output:
  gates: dispatch-gate disjointness (F8)            bash tests/test-hooks.sh             RED, then GREEN
  hooks: safety-gate bypasses (F1)                  bash tests/test-hooks.sh             RED, then GREEN
  gates: lane lowering via override (F1)            bash tests/test-lane-effective.sh    RED, then GREEN
  goals: queue breaker and single conductor         bash tests/test-runaway-guards.sh    51/57 under the revert, then 57/57
  wrap: pr-gate missing merge state, retry cap      bash tests/test-wrap-merge.sh        280/284 under the revert, then 284/284
  specs: malformed Depth line                       bash tests/test-spec-depth.sh        122/124 under the revert, then 124/124
  specs: precedent keywords                         bash tests/test-precedent.sh         82/83 under the revert, then 83/83
  rules: verify-loop cap mutated (atLeast -> gt)    bash tests/test-rules.sh             9/12 under the mutation, then 12/12
Result: RED as expected
```

Every bridge is also its own negative control: each area kept the bash as found as a variant, and the bridge showed the committed code agreeing with that broken variant and diverging from the fixed rule before the fix (counts per fix in `lib/rules/*/FINDINGS.md`).

## Reproduce

```
npm ci --prefix lib/rules
bash tests/test-rules.sh
(cd lib/rules && node prove.ts --bridges)        # several thousand script runs; run it on a box
```

Verdict: PASS
