# Verification -- task-gate-inherit

`gate-ledger.sh inherit <rid> full --from <spec-rid>` writes one `override` line per spec-level gate for a task branch, and only when the spec rid's ledger ends each of those phases in `ran` (`docs/specs/SPEC-393-task-gate-inherit.md`).

| Check | Command | Result |
|---|---|---|
| New suite | `bash tests/test-gate-ledger-inherit.sh` | 82/82 at `87c3eb0e` |
| Sibling suite | `bash tests/test-gate-ledger-plan-record.sh` | 41/41 |
| Changed-only regression | `bash tests/run-all.sh --changed --time` | at `a1614e3d`: 72/73 suites ok; 1 red, a pre-existing pin (see Not proven). The later commits touch only `inherit()` and its suite. |
| Real flow, live ledger | `inherit proof-inherit-probe full --from watch-hub-spec` | refuses, exit 1, nothing written |
| Real flow, temp copy | `inherit wh-demo full --from watch-hub-spec`, then per-branch gates, then `check full --kit-lanes` | 7 lines, check exit 0 |
| Negative controls | `lib/gate/negctl.sh`, NC-1 to NC-9 | 9/9 RED under mutation, green after restore |
| Review | fresh-context `kit:code-reviewer` (Opus), correctness and forgery lens | FIX THEN SHIP: one MEDIUM finding, fixed in `e719ad16`, pinned by NC-9 |

## Green run
```
Command: bash tests/test-gate-ledger-inherit.sh
Exit: 0
Output:
  PASS AC-11 check full --kit-lanes exits 0
  PASS FAILCLOSED (malformed lane table) exits 1
  PASS FAILCLOSED (malformed lane table) writes nothing
  PASS FAILCLOSED (empty lane table) exits 1
  PASS FAILCLOSED (empty lane table) writes nothing

inherit: 82/82 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1
Output:
test-gate-ledger-inherit                       ok (27s)
test-gate-ledger-plan-record                   ok (34s)
test-ship-gate-impl-notes                      FAIL (rc=1) (53s)
      | PASS=15 FAIL=1
run-all: FAILED -> test-ship-gate-impl-notes
run-all: 73 suites run, 0 skipped for missing tooling
Verdict: 72/73 ok; the one red is case 8 of test-ship-gate-impl-notes ("NOT ok - 8 gate-ledger.sh changed")
```

## Real primary flow

Against the live ledger root (read only: the verb refused, and `runs/proof-inherit-probe.log` does not exist before or after):
```
Command: bash lib/gate/gate-ledger.sh inherit proof-inherit-probe full --from watch-hub-spec
Exit: 1
Output:
inherit: parent 'watch-hub-spec' does not hold last state ran for every spec-level gate; nothing written:
  think: last state override, not ran
  design: last state override, not ran
  design-critique: last state override, not ran
  spec: last state override, not ran
Verdict: PASS (Edge Case 2: the parent's four spec-level gates were backfilled as overrides, so the verb refuses)
```

Against a temp copy of the same ledger, with `ran` lines appended for those four phases:
```
Command: inherit wh-demo full --from watch-hub-spec; check full wh-demo --kit-lanes; record build|review|docs ran; override ship|reflect; check full wh-demo --kit-lanes; inherit (re-run)
Exit: 0, then 1, then 0, then 0
Output:
think inherited from watch-hub-spec
... design, design-critique, spec, validate, design-record ...
test-plan inherited from watch-hub-spec
MISSING-GATE: build (required for lane 'full'; no ran/override entry in the ledger)
MISSING-GATE: review ...   MISSING-GATE: docs ...   MISSING-GATE: ship ...   MISSING-GATE: reflect ...
(check after per-branch gates) Exit: 0
think already inherited from watch-hub-spec
... seven "already" lines ...
2026-10-04T16:42:28Z | GATE | think | override | inherited from watch-hub-spec: think ran there at 2026-10-04T17:00:00Z
Verdict: PASS
```

## Negative control

Each control ran under `bash lib/gate/negctl.sh "$PWD" "<suite wrapper>" "<mutation>"`. NC-1 to NC-8 ran at `e719ad16` (82-case suite); NC-9 ran at `87c3eb0e`. `gate-ledger.sh` is byte-identical between the two. The suite wrapper runs `tests/test-gate-ledger-inherit.sh` and prints its FAIL lines.

| NC | Mutation | Under mutation | Named case red | negctl |
|---|---|---|---|---|
| NC-1 | `none)` branch collects no failure | 76/82 | AC-3 both fixtures | PASS |
| NC-2 | `ran)` becomes `ran\|override)` | 74/82 | AC-4, AC-6 | PASS |
| NC-3 | awk stops updating a phase once it saw `ran` | 71/82 | AC-5 ran-then-skipped | PASS |
| NC-4 | `build` added to `INHERITABLE` | 55/82 | AC-2 "check lists build", "child holds no per-branch line" | PASS |
| NC-5 | conflict check replaced by `if false` | 72/82 | AC-7 both prefix directions | PASS |
| NC-6 | `ran)` branch writes its override while judging | 68/82 | AC-3 (test-plan missing) child ledger stays absent | PASS |
| NC-7 | token loses `: ` | 72/82 | AC-7 child from watch-hub-spec, call watch-hub: exits 65 | PASS |
| NC-8 | `return "$rc"` becomes `continue` | 81/82 | AC-8 exits 65 | PASS |
| NC-9 | judge rows split on `\t` again instead of `\037` | 80/82 | EMPTYSTATE: the verb writes `validate` from a forged `ran \| GATE \| validate \|  \| <ts>` line | PASS |

```
Command: bash .../nc/suite.sh
Exit: 0 (green before mutation)
Mutation: bash .../nc/nc9.sh
Changed: lib/gate/gate-ledger.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL EMPTYSTATE exits 1 naming validate (out: think inherited from p
    FAIL EMPTYSTATE nothing written (out: think inherited from p
  inherit: 80/82 passed
Restore: git checkout HEAD -- lib/gate/gate-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Every restore left the tree clean (`git status --short` empty), and the suite printed 82/82 afterwards.

## Not proven

- `tests/test-ship-gate-impl-notes.sh` case 8 asserts `lib/gate/gate-ledger.sh` is byte-identical to `origin/master`. Any unmerged branch that edits that file fails it, and it passes again once merged. This branch edits the file on purpose. The test was left untouched, because weakening a guard is a lead call.
- The live `watch-hub-spec` parent cannot be inherited from as it stands: its think, design, design-critique and spec gates end in `override`. Inheriting from it needs `ran` lines with evidence on the parent, or the children keep their hand overrides for those four.
- Concurrent writers on one child rid are not tested (accepted in the implementation notes).
