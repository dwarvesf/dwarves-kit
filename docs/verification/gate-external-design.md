# Verification: gate-external-design

One gate-ledger entry cites a design record in another GitHub repo and satisfies the design-side full-lane gates (think, design, design-critique, spec, validate, design-record). Spec: `docs/specs/SPEC-414-gate-external-design.md`.

## Green runs

Run 1, the proof of done: a console-workers-shaped auth diff through the real ship-gate hook. A scratch adopted repo (`docs/verification/README.md`, `[gate] lane_gates = true`) carries branch `feat/relay-seal` adding `workers/playdate-relay/src/auth.ts`, the hard path the real relay PRs hit (`lane-classify.sh floor ~/workspace/consolelabs/console-workers 0f308e1~1 99009ec` prints `full auth: workers/playdate-relay/src/auth.ts`). The ledger holds `ran` lines for test-plan, build, review, docs, ship and reflect. The hook is the real `hooks/ship-gate.sh`, and `gh` is the real CLI against the real `consolelabs/playdate-agent`; no stub. The kit checkout path shows as `<kit-root>`.

```
Command: bash proof.sh <kit-root>
Exit: 0
Output:
$ lane-classify floor (the diff):
full auth: workers/playdate-relay/src/auth.ts

== 1. no design entry: ship-gate blocks ==
BLOCKED: ship-gate. This diff touches a hard path (auth: workers/playdate-relay/src/auth.ts); the full lane's gates apply whatever the spec's Lane says:
(no spec found for 'relay-seal'; a hard-path diff owes the full lane's gates with or without one)
  MISSING-GATE: think (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: design (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: design-critique (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: spec (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: validate (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: design-record (required for lane 'full'; no ran/override entry in the ledger)
Run the missing gate(s), or log an explicit override (recorded for audit):
  bash "<kit-root>/lib/gate/gate-ledger.sh" override relay-seal <phase> "<reason>"
Design gates (think design design-critique spec validate design-record) can rest on one design record in another GitHub repo, checked at push:
  bash "<kit-root>/lib/gate/gate-ledger.sh" external-design relay-seal <owner>/<repo>@<40-hex commit>:<path> "<reason>"   (or a merged PR URL)
hook exit=2

== 2. bare string: refused, nothing written ==
external-design: 'playdate-agent SPEC-005 and ADR 0008' is not a citation; use <owner>/<repo>@<40-hex commit>:<path> or https://github.com/<owner>/<repo>/pull/<n>; nothing written
verb exit=64

== 3. bogus citation (path missing at the commit): refused by the verb ==
external-design: consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-099-nope.md did not verify: gh api failed (exit 1): {"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/contents#get-repository-content","status":"404"} gh: Not Found (HTTP 404); nothing written
verb exit=1

== 4. bogus citation appended by hand: ship-gate re-verifies and blocks ==
BLOCKED: ship-gate. This diff touches a hard path (auth: workers/playdate-relay/src/auth.ts); the full lane's gates apply whatever the spec's Lane says:
(no spec found for 'relay-seal'; a hard-path diff owes the full lane's gates with or without one)
  MISSING-GATE: think (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: design (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: design-critique (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: spec (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: validate (required for lane 'full'; no ran/override entry in the ledger)
  MISSING-GATE: design-record (required for lane 'full'; no ran/override entry in the ledger)
  EXTERNAL-DESIGN: consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-099-nope.md did not verify: gh api failed (exit 1): {"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/contents#get-repository-content","status":"404"} gh: Not Found (HTTP 404)
Run the missing gate(s), or log an explicit override (recorded for audit):
  bash "<kit-root>/lib/gate/gate-ledger.sh" override relay-seal <phase> "<reason>"
Design gates (think design design-critique spec validate design-record) can rest on one design record in another GitHub repo, checked at push:
  bash "<kit-root>/lib/gate/gate-ledger.sh" external-design relay-seal <owner>/<repo>@<40-hex commit>:<path> "<reason>"   (or a merged PR URL)
hook exit=2

== 5. one real external-design entry: ship-gate passes ==
cited consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-005-relay-link-and-seal.md: covers think design design-critique spec validate design-record
verb exit=0
hook exit=0

== ledger ==
2026-10-29T18:04:00Z | GATE | test-plan | ran | relay test-plan evidence
2026-10-29T18:04:00Z | GATE | build | ran | relay build evidence
2026-10-29T18:04:00Z | GATE | review | ran | relay review evidence
2026-10-29T18:04:00Z | GATE | docs | ran | relay docs evidence
2026-10-29T18:04:00Z | GATE | ship | ran | relay ship evidence
2026-10-29T18:04:00Z | GATE | reflect | ran | relay reflect evidence
2026-10-29T18:04:01Z | GATE | external-design | cite | consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-099-nope.md | forged by hand
2026-10-29T18:04:03Z | GATE | external-design | cite | consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-005-relay-link-and-seal.md | re
Verdict: PASS
```

Reading: step 1 blocks (exit 2) and names the new verb. Steps 2 and 3: the verb refuses a bare string (64) and a path missing at the commit (1), writing nothing. Step 4: a hand-appended bogus cite line does not pass on its text; the push re-verifies and blocks (exit 2) with the `EXTERNAL-DESIGN:` reason in the gap list. Step 5: one real entry, and the same push exits 0. The six per-gate overrides the relay branches needed are gone.

Run 2, the new suite (stubbed `gh` through `GH_CMD`, no network), also green under macOS `/bin/bash` 3.2:

```
Command: bash tests/test-gate-external-design.sh
Exit: 0
Output:
external-design: 71/71 passed
Verdict: PASS
```

Run 3, the dev loop:

```
Command: bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
run-all: all 91 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

(An earlier pass of Run 3 failed `test-no-personal-paths` on this file's home path. The path is now `<kit-root>`, and the output above is from the rerun after the review fixes.)

## Negative control

Mutation: `_ext_covered` accepts the first citation without calling `_ext_verify`. A second hand mutation, `EXTERNAL_COVERS="$INHERITABLE"` (test-plan added to the covered set), turned `check: test-plan is never covered` and `pin: the covered set is exactly the six design-side gates` red, and was reverted.

## Negative control (negctl)
## Negative control (negctl)
Command: bash tests/test-gate-external-design.sh
Exit: 0 (green before mutation)
Output:
    PASS ship-gate: the hint sits after the override line
    PASS ship-gate: one external-design entry passes the auth diff
    PASS ship-gate: a second push re-verifies (the stub now answers 404, the push blocks)
    PASS ship-gate: the EXTERNAL-DESIGN line sits in the indented gap list after the MISSING-GATE lines
    PASS ship-gate: a bogus citation blocks the auth diff
    PASS ship-gate: the lane-check block names the external-design verb
    PASS ship-gate: a merged-PR citation passes the full-lane spec plus auth diff
    PASS ship-gate: six per-gate overrides still pass
  
  external-design: 71/71 passed

Mutation: perl -pi -e 's/^    why="\$\(_ext_verify "\$c" 2>&1\)" && return 0/    return 0/' lib/gate/gate-ledger.sh
Changed: lib/gate/gate-ledger.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS ship-gate: one external-design entry passes the auth diff
    FAIL ship-gate: a second push re-verifies (the stub now answers 404, the push blocks) (rc: 0 out: cited consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-005-relay-link-and-seal.md: covers think design design-critique spec validate design-record err: )
  tests/test-gate-external-design.sh: line 21: [: : integer expected
    FAIL ship-gate: the EXTERNAL-DESIGN line sits in the indented gap list after the MISSING-GATE lines (rc: 0 out: cited consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-005-relay-link-and-seal.md: covers think design design-critique spec validate design-record err: )
    FAIL ship-gate: a bogus citation blocks the auth diff (rc: 0 out: cited consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-005-relay-link-and-seal.md: covers think design design-critique spec validate design-record err: )
    PASS ship-gate: the lane-check block names the external-design verb
    PASS ship-gate: a merged-PR citation passes the full-lane spec plus auth diff
    PASS ship-gate: six per-gate overrides still pass
  
  external-design: 58/71 passed

Restore: git checkout HEAD -- lib/gate/gate-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS

## Test plan coverage

The spec carries no `## Test plan` section; TASK-006 names the cases. Edge cases 1 to 17 map to named cases in `tests/test-gate-external-design.sh` (refuse rows for 1, 2, 3, 4, 5, 9, 10, 11; check rows for 6, 7, 8, 12, 13; the hook rows for 15; the timeout rows for 16; the progress and descent rows for 17). Edge case 14 (owner case) is declared harmless in the spec and has no case.
