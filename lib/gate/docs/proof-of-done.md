# Proof of Done: gate

**Feature:** the module's front door (`lib/gate/README.md`) + its own acceptance record, closing two of the four `lib/gate/*` / `lib/learn/*` IOUs in `tests/kit-contract-known-gaps.txt`.
**Date:** 2026-07-15 · **Lane:** docs · **Host:** dev laptop (macOS 26.5, bash 3.2, Python 3.13) · **Branch:** `feat/retro-propose`

`gate` is the Check stage's engine (formerly "Govern leg", ADR-0034). It is the most heavily specced module in the kit (fourteen
numbered SPECs, five ADRs) and one of the best tested (119 assertions across six suites), and it
had **no module-level README and no proof of its own**. The specs describe each gate; nothing
described the *module*: which of its nine scripts can actually block you, which only advise, and
what the ledger's marker discipline guarantees.

This change is **documentation only**. No line of any `lib/gate/*` script was touched. The
evidence below is therefore not "the new code works", it is "the existing behavior is what the new
README says it is", plus a control proving the contract lint now really watches this module.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | The module has a README front door: what it IS, its callables, where its specs live, where its tests live | task; C3 |
| A2 | The module has its own `docs/proof-of-done.md` | task; C3 |
| A3 | Every behavioral claim the README makes is backed by a real run or a code cite, not restated from a spec | house rule: read the code before writing about it |
| A4 | `bash tests/test-kit-contract.sh` stays green at 24, and the two closed IOUs are gone from the gaps file | task |
| A5 | The contract lint genuinely watches `lib/gate` (not merely green because it skips it) | NEGATIVE CONTROL |
| A6 | Behavior unchanged (docs only) | scope fence |

## Implementation

| Piece | What | Where |
|---|---|---|
| README | Front door: the two walls vs the advisors, the callable table, the ledger line grammar + the additive-marker invariant, specs, tests, three pitfalls | `lib/gate/README.md` |
| Proof | this file | `lib/gate/docs/proof-of-done.md` |
| Gaps closed | `lib/gate/README.md` + `lib/gate/docs/proof-of-done.md` removed from the IOU list | `tests/kit-contract-known-gaps.txt` |
| Gap kept | `lib/gate/SPEC` stays: C3 accepts a spec only INSIDE the module dir, and gate's specs are all repo-root numbered ones | `tests/kit-contract-known-gaps.txt` |

The README's three pitfalls are not invented for the doc. Each is read off the source:

| Pitfall | Where the code says so |
|---|---|
| A `skipped`-with-reason phase shows as done in `progress()` but does **not** satisfy `check()` | `check()` matches `$4=="ran"\|\|$4=="override"`; `progress()`/`descent()` dispose on `$4!="skipped" \|\| (NF>=5 && $5!="")` (`gate-ledger.sh:437,482,538`) |
| The lane gate fails CLOSED, the proof gate fails OPEN | `check()` refuses an unknown lane rather than read an empty required-list (`gate-ledger.sh:429`); `proof-ledger.sh:23,201` return 0 on a bad base |
| An override needs a per-gate reason, and never excuses source | blanket-reason reject exit 65 (`gate-ledger.sh:404`); source-remainder reject (`proof-ledger.sh:230`) |

## Confirmation run-table

| # | Check | Command | Expected | Result |
|---|---|---|---|---|
| 1 | Outcome markers + the additive property (A3) | `bash tests/test-gate-outcome.sh` | 22/22, exit 0 | PASS |
| 2 | Every required gate name has a command that records it (A3) | `bash tests/test-gate-vocab-recording.sh` | 17/17, exit 0 | PASS |
| 3 | Durable root, override guard, ledger forgery (A3) | `bash tests/test-ledger-durability.sh` | 37/37, exit 0 | PASS |
| 4 | The one append substrate (A3) | `bash tests/test-ledger-substrate.sh` | 9/9, exit 0 | PASS |
| 5 | Quiz-gate: grounded questions, anti-fatigue, never must-pass (A3) | `bash tests/test-quiz-gate.sh` | 29/29, exit 0 | PASS |
| 6 | Ship-gate fail-closed (A3) | `bash tests/test-ship-gate-fail-closed.sh` | 5/5, exit 0 | PASS |
| 7 | Kit contract green, IOUs closed (A4) | `bash tests/test-kit-contract.sh` | 24 passed, 0 failed | PASS |
| 8 | **NEGATIVE CONTROL**: the lint really watches `lib/gate` (A5) | yank `README.md`, re-run the contract | C3 goes RED naming `lib/gate/README.md` | PASS |
| 9 | **NEGATIVE CONTROL**: a required gate really is required (A3) | `test-gate-vocab-recording.sh` AC5 | dropping `build` re-blocks `check full` | PASS |
| 10 | Behavior unchanged (A6) | `git diff --stat lib/gate/*.sh lib/gate/*.py` | no source file in the diff | PASS |

## Run detail

The gate suites, verbatim summary lines (each run to completion, `Exit: 0`):

```
$ bash tests/test-gate-outcome.sh | tail -2; echo "Exit: $?"
=== 22/22 passed, 0 failed ===
Exit: 0

$ bash tests/test-gate-vocab-recording.sh | tail -2; echo "Exit: $?"
=== Summary: 17/17 passed ===
Exit: 0

$ bash tests/test-ledger-durability.sh | tail -2; echo "Exit: $?"
=== 37/37 passed, 0 failed ===
Exit: 0

$ bash tests/test-ledger-substrate.sh | tail -2; echo "Exit: $?"
== 9 passed, 0 failed ==
Exit: 0

$ bash tests/test-quiz-gate.sh | tail -3; echo "Exit: $?"
  TOTAL: 29   PASS: 29   FAIL: 0
Exit: 0

$ bash tests/test-ship-gate-fail-closed.sh | tail -2; echo "Exit: $?"
PASS=5 FAIL=0
Exit: 0
```

The two invariants the README leans on hardest, in full. First, the **additive-marker property**:
a TOKENS / DEBT / OUTCOME / MUTATION line can never fake or mask a gate. `test-gate-outcome.sh`
pins it against every reader at once:

```
$ bash tests/test-gate-outcome.sh; echo "Exit: $?"
=== gate-outcome (SPEC-129 AC1-AC9) ===
  PASS AC1 round-trip: reads back phase+caught+dur_s
  PASS AC1 duration derivable (dur_s>=1 after a 1s bracket)
  PASS AC2 caught=true recorded on a non-pass
  PASS AC2 caught=false recorded on a clean pass
  PASS AC3 caught defaults to false when omitted
  PASS AC4 bad caught value rejected (rc 64)
  PASS AC4 rejected end wrote no line
  PASS AC4 bad event rejected (rc 64)
  PASS AC5 unbracketed end succeeds (rc 0)
  PASS AC5 unbracketed end -> dur_s=0 (honest)
  PASS AC6 start-without-end reads as incomplete
  PASS AC7 check() byte-identical with OUTCOME present
  PASS AC7 descent() byte-identical with OUTCOME present
  PASS AC7 progress() byte-identical with OUTCOME present
  PASS AC7 _rows()/lane-telemetry byte-identical with OUTCOME present
  PASS AC7 show() preserves every pre-existing line
  PASS AC7b descent() unchanged by OUTCOME via the real verb (additive property; negative-control target)
  PASS AC8 gate-ledger.sh free of BSD-only date/stat/sed constructs
  PASS AC8 duration uses portable date +%s
  PASS AC9 ship-gate emits OUTCOME start at its gate boundary
  PASS AC9 ship-gate emits caught=true on block
  PASS AC9 ship-gate emits caught=false on clean pass

=== 22/22 passed, 0 failed ===
Exit: 0
```

Second, the ledger-forgery guard, which is why `oneline()` exists. From
`test-ledger-durability.sh`, the two assertions that matter:

```
  PASS SEC-1: reason newline collapsed to ONE ledger line
  PASS SEC-1: forged 'build | ran' does NOT satisfy check() (still reported missing)
```

A reason carrying an embedded newline would otherwise split into a second physical line that
`check()` cannot distinguish from a real `| GATE | build | ran |` record. That is a
prompt-injection to ledger-forgery to gate-bypass chain, and it is closed at the write path.

## NEGATIVE CONTROL

Adding two markdown files and watching a suite stay green proves nothing: **a lint that skips the
module would also stay green.** The claim under test is "C3 now watches `lib/gate`". The way to
prove it is to break it on purpose.

Yank the README and the contract must go red, naming the exact missing artifact:

```
$ mv lib/gate/README.md /tmp/gate-readme.bak
$ bash tests/test-kit-contract.sh
== C3 docs: README + SPEC + proof-of-done per module ==
  FAIL every module has README + a spec + docs/proof-of-done.md (no NEW gaps) (offenders: lib/gate/README.md )
=== kit-contract: 23 passed, 1 failed ===
Exit: 1

$ mv /tmp/gate-readme.bak lib/gate/README.md   # restore
$ bash tests/test-kit-contract.sh | tail -1
=== kit-contract: 24 passed, 0 failed ===
Exit: 0
```

Before this change that same deletion was a no-op in the other direction: the path was listed in
`tests/kit-contract-known-gaps.txt`, so C3 counted it as a known gap and stayed green whether the
file existed or not. Removing the IOU line is what arms the check. The module is now inside the
lint's teeth, not merely adjacent to them.

### A second control, on the gate mechanism itself

The README claims a required gate is genuinely required. `test-gate-vocab-recording.sh` AC5 proves
it by removing exactly one recorded gate (`build`, `/kit:execute`'s own) from an otherwise complete
full-lane run, and the same `check` that passed must now fail and name it:

```
=== AC4: a command-driven full-lane run (all 12 gates recorded by literal name) reaches ship ===
  PASS check full <rid> passes with all 12 gates recorded (exit 0)

=== AC5: NEGATIVE CONTROL -- drop just 'build' (execute.md's own gate), the same run re-blocks ===
  PASS check full <rid> FAILS when build is not recorded (exit != 0)
  PASS the check names 'build' as the missing gate
```

Passing because every gate ran, and passing because the check never looked, are indistinguishable
without that control. This is the same reason the run-table above lists it as a row.

## Reproduce

```bash
bash tests/test-gate-outcome.sh           # 22/22
bash tests/test-gate-vocab-recording.sh   # 17/17
bash tests/test-ledger-durability.sh      # 37/37
bash tests/test-ledger-substrate.sh       #  9/9
bash tests/test-quiz-gate.sh              # 29/29
bash tests/test-ship-gate-fail-closed.sh  #  5/5
bash tests/test-kit-contract.sh           # 24 passed, 0 failed

# the negative control
mv lib/gate/README.md /tmp/gate-readme.bak
bash tests/test-kit-contract.sh           # C3 RED, names lib/gate/README.md
mv /tmp/gate-readme.bak lib/gate/README.md

git diff --stat lib/gate/                 # only README.md + docs/proof-of-done.md: behavior unchanged
```
