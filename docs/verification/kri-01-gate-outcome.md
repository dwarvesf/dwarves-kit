# Proof of done , kri-01-gate-outcome (SPEC-129 gate-outcome emit: caught= + START/END timing)

Behavioral change: `gate-ledger.sh outcome` verb + `outcome-read` reader (a third ADDITIVE
`| OUTCOME |` marker beside TOKENS + DEBT) + a live emit at `hooks/ship-gate.sh`'s check
boundary. Spec: `docs/specs/SPEC-129-gate-outcome-emit.md`. Branch: `feat/kri-01-gate-outcome`.

## Acceptance criteria -> confirmation

| # | Acceptance criterion | Evidence | Verdict |
|---|---|---|---|
| 1 | round-trip: emit start/end -> read back caught + duration for a rid | AC1: `outcome-read` returns `ship caught=true dur_s>=1` after a 1s bracket | PASS |
| 2 | `caught=true` on a non-pass, `caught=false` on a clean pass | AC2: both recorded + read back | PASS |
| 3 | `caught` defaults to false when omitted (safe default) | AC3 | PASS |
| 4 | bad `caught` value + bad `event` rejected (rc 64), no line written | AC4 | PASS |
| 5 | an `end` with no prior `start` is honest (dur_s=0, not an error) | AC5 | PASS |
| 6 | incomplete bracket (start, no end) reads back as `incomplete` | AC6 | PASS |
| 7 | ADDITIVE-EQUIVALENCE: check()/descent()/progress()/_rows() byte-identical with OUTCOME present | AC7 (hardcoded interleave) + AC7b (via the real verb) | PASS |
| 8 | PORTABILITY: no `date -d`/`date -r`/`stat -f`/`sed -i ''`; duration via `date +%s` | AC8 | PASS |
| 9 | LIVE PATH: ship-gate emits an OUTCOME bracket on block (caught=true) + pass (caught=false) | AC9 (wiring) + e2e run-table below | PASS |

## Confirmation run-table

| Command | Exit | Verdict | Detail |
|---|---|---|---|
| `bash tests/test-gate-outcome.sh` | 0 | PASS | 22/22 assertions green (AC1-AC9 + AC7b) |
| `bash tests/test-hooks.sh` | 0 | PASS | ship-gate + hook suite green (my ship-gate emit did not disturb it) |
| `bash tests/test-meta.sh` | 0 | PASS | meta-integrity suite green |
| `bash tests/test-ledger-durability.sh` | 0 | PASS | 35/35; TOKENS/DEBT sibling markers intact |
| `bash tests/test-lane-telemetry.sh` | 0 | PASS | 25/25; `_rows()`/`_token_agg()` tolerate the new marker |
| `bash tests/test-tier4-close.sh` | 0 | PASS | no-orphan / TIER-4 suite green |
| ship-gate e2e (isolated repo, incomplete ledger) | 2 (block) | PASS | emitted `OUTCOME | ship | end | ... caught=true dur_s=0`; read back `ship caught=true` |
| ship-gate e2e (isolated repo, complete ledger) | 0 (pass) | PASS | emitted `caught=false`; read back `ship caught=false`. Exit codes UNCHANGED by the emit (block still 2, pass still 0). |

Full CI-listed suite (27 suites) green locally; PR #158 CI green on BOTH ubuntu-latest +
macos-latest.

## Run detail

**Green** , `bash tests/test-gate-outcome.sh` , Exit 0 , `=== 22/22 passed, 0 failed ===`.
Covers the round-trip (AC1), both caught values + default (AC2/AC3), input validation (AC4),
honesty edges (AC5/AC6), additive-equivalence across every existing reader (AC7 via
hardcoded interleave + AC7b via the real verb), portability (AC8), and the live ship-gate
emit (AC9).

**Negative control (load-bearing property = ADDITIVE-EQUIVALENCE)** , the proof must be able
to observe a FAILURE. Break: flip the emitted marker's field-2 from `OUTCOME` to `GATE` in
`lib/gate/gate-ledger.sh`'s two `outcome()` write lines, so existing `$2=="GATE"` readers wrongly
pick up the outcome lines. Re-run the suite:

```
===== NEGATIVE CONTROL: marker field-2 flipped OUTCOME->GATE =====
exit=1
  FAIL AC1 round-trip: reads back phase+caught+dur_s (got '')
  FAIL AC1 duration derivable (got dur_s='')
  FAIL AC2 caught=true recorded on a non-pass
  FAIL AC2 caught=false recorded on a clean pass
  FAIL AC3 caught defaults to false when omitted
  FAIL AC5 unbracketed end -> dur_s=0 (honest)
  FAIL AC6 start-without-end reads as incomplete
  FAIL AC7b descent() unchanged by OUTCOME via the real verb (BEFORE!=AFTER)
=== 14/22 passed, 8 failed ===
```

The load-bearing assertion (AC7b) goes RED, and the actual corruption is directly
observable , `descent()` (a `$2=="GATE"` reader) now manufactures a bogus violation from the
outcome line:

```
descent BEFORE outcome emit:   (8 build-before-<phase> lines)
descent AFTER outcome emit (corrupted by GATE-flip):
  ... same 8 lines ...
  DESCENT: think recorded before grill disposed   <-- BOGUS: an OUTCOME line seen as a GATE
```

The seven other RED assertions (AC1/2/3/5/6) fail because `outcome-read` (which keys on
`$2=="OUTCOME"`) can no longer find the now-`GATE`-marked lines , independent evidence that
the marker identity is load-bearing. This proves the suite can SEE a non-additive marker;
the additive-equivalence PASS is therefore meaningful, not vacuous.

**Restore** , `git checkout lib/gate/gate-ledger.sh` , re-run , `=== 22/22 passed, 0 failed ===`,
exit 0. The test is sensitive to the marker identity; the OUTCOME field-2 is what keeps it
green.

**No regression** , test-hooks / test-meta / test-ledger-durability / test-lane-telemetry /
test-tier4-close all exit 0. The `| OUTCOME |` marker is ignored by every existing reader
(they key on `$2==GATE|START|START-AMEND|TOKENS|ACTION|DEBT`); the ship-gate emit is
best-effort + rid-ledger-only, so it never changes the hook's fail-open exit/output.

**Cross-platform** , duration is an integer subtraction of two `date +%s` epochs carried on
the start/end lines; no `date -d`/`date -r`/`stat -f`/`sed -i ''` (AC8 guard). CI green on
ubuntu-latest + macos-latest (PR #158).

## Reproduce

```
cd <clone>/dwarves-kit          # branch feat/kri-01-gate-outcome
bash tests/test-gate-outcome.sh                 # 22/22 (incl. AC7b additive-equivalence via the real verb)
# negative control:
#   edit lib/gate/gate-ledger.sh: outcome() two printf lines  | OUTCOME |  ->  | GATE |
bash tests/test-gate-outcome.sh                 # 14/22: AC7b (+ AC1/2/3/5/6) go RED
git checkout lib/gate/gate-ledger.sh
bash tests/test-gate-outcome.sh                 # 22/22 again
bash tests/test-hooks.sh && bash tests/test-ledger-durability.sh   # no regression
```

Final Verdict: PASS
