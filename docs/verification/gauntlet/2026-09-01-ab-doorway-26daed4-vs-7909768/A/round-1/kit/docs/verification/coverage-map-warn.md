# Proof of done -- coverage-map-warn (ID-466)

Behavioral change: `proof-gate.sh coverage` subcommand + ship-gate advisory when a spec's
`## Test plan` matrix rows are not mapped in the proof doc's `## Test plan coverage` section.
Advisory only; no blocking path added or changed.

## 2026-08-10 PASS -- coverage-map-warn [green]
- Command: `bash tests/test-ship-gate-coverage-map.sh`
- Exit: 0
- Output (excerpt):
  ```
  ok - coverage: partial map -> UNMAPPED: 2 3
  ok - coverage: all rows mapped -> OK (critique table not counted)
  ok - (a) plan + mapless proof -> advisory emitted, exit 0 (not blocked)
  ok - (b) all rows mapped -> no coverage advisory, exit 0
  ok - (c) no test plan -> no coverage advisory, exit 0
  ok - (d) partial map -> advisory names unmapped row 2, exit 0
  PASS=10 FAIL=0
  ```
- Verdict: PASS
- Note: covers all three required cases -- (a) plan + mapless proof warns without blocking, (b) fully mapped emits no warning, (c) no test plan emits no warning -- plus unit coverage of both matrix dialects and the `## Test plan critique` exclusion.

## 2026-08-10 RED-as-expected -- coverage-map-warn [NEGATIVE CONTROL]
- Command: `bash <copy>/tests/test-ship-gate-coverage-map.sh` where `<copy>` is a scratch copy of this branch with `hooks/ship-gate.sh` and `lib/gate/proof-gate.sh` restored from master (the change reverted; the shared checkout untouched)
- Exit: 1
- Output (excerpt):
  ```
  usage: proof-gate.sh {class "<desc>"|requirement "<desc>"|contract "<desc>"|classes}
  NOT ok - mapless proof should report NO-MAP
  NOT ok - (a) expected exit 0 + coverage advisory; got exit 0, stderr: [advisory] delivery-ratio: ...
  PASS=2 FAIL=8
  ```
- Verdict: RED-as-expected
- Note: 8/10 fail without the change. Cases (b) and (c) assert the ABSENCE of a warning, so they are trivially green on the reverted code; the presence cases (a)/(d) and all six unit cases go RED.

## 2026-08-10 PASS -- existing suites stay green
- Command: `bash tests/test-hooks.sh && bash tests/test-ship-gate-fail-closed.sh && bash tests/test-ship-gate-profiles.sh && bash tests/test-docs-wiring.sh`
- Exit: 0
- Output (excerpt):
  ```
  Passed: 492 / 492            (test-hooks.sh)
  PASS=5 FAIL=0                (test-ship-gate-fail-closed.sh)
  ALL PASS (3 profiles x allow+block)
  === 22/22 passed ===         (test-docs-wiring.sh)
  ```
- Verdict: PASS
- Note: `tests/test-meta.sh` reports 799/809 on this branch AND on master (same 10 pre-existing failures: command-count tables, FEATURES.md freshness); the delta from this branch is zero.

Reversibility: pure git revert; the advisory writes nothing and never changes an exit code.
