# SPEC-117: token capture under delegation (stream-to-FILE, conductor stays lean)

Status: SHIPPED
Lane: full
Type: spec-feature

## Problem

ADR-0032 commits the kit to a DELEGATE run mode (default for mega-goals > 4 sub-goals): the `/goal`
conductor is a thin driver that makes ONE fresh `claude -p` call per sub-goal and absorbs only a
terse box-flip result, never the child transcript. ADR-0032 §1 makes that a HARD RULE: delegate
uses plain `claude -p`, NEVER `--stream`/`--verbose` piped TO THE CONDUCTOR (that dumps the child
transcript into the parent context , the exact accumulation trap the whole mode exists to avoid).

This collides with the token ledger (SPEC-110). Token capture needs stream-json (usage lives in the
per-assistant-turn `usage` blocks), but under delegation there is today NO LEAN way to get it:

- `orchestrate.sh run <dir> --stream` captures usage to `.orchestrate/<id>.stream.jsonl` BUT
  `tee`s the full stream-json to the conductor's stdout (`_run_one_session` L621) , the forbidden
  bloat path. `test-orchestrate.sh` TEST 10 even asserts this tee happens.
- The only existing SILENT stream-to-FILE capture (`> "$slog"`, `_run_one_session` L623) is
  reachable ONLY by enabling `DETERMINISTIC_HANDOFF=1` , a heavier, unrelated feature (handoff
  regeneration). An operator who wants token capture on a plain delegate run should not have to
  turn on handoff regeneration to get it.

ADR-0032 §5 lists "Token-capture stream-to-file (item 3)" as a gap the ADR obliges the kit to
close. Result: a delegate mega-goal cannot be priced (median tokens-to-done, cache efficiency per
SPEC-110) without bloating the conductor, so operators run blind or bloat the parent. This spec
closes that gap and OVER-TESTS the two load-bearing properties.

## Solution

Reconcile per ADR-0032 §3: the delegated child streams to a FILE, usage is extracted FROM the file,
the token ledger records it, and the conductor reads ONLY the box-flip. Reuse the entire SPEC-110
extraction+ledger chain; add ONE decoupled trigger so the LEAN capture is first-class.

1. **`CAPTURE_TOKENS` env (default 0), read as a script GLOBAL, plus a `--capture-tokens` flag that
   just sets that same global** , a decoupled opt-in that makes `_run_one_session` take the EXISTING
   silent `> "$slog"` stream-to-FILE branch purely for usage extraction. Independent of `--stream`
   (which stays the live-tail-to-conductor bloat path) and of `DETERMINISTIC_HANDOFF` (which stays
   the handoff-regen path). The mechanism is pinned to the SAME shape as `DETERMINISTIC_HANDOFF`: a
   global read inside `_run_one_session` (orchestrate.sh:612), NOT a new positional arg. This is
   deliberate , a positional would force a signature change and a touch at `_wave_run`'s hardcoded
   5-arg call site (orchestrate.sh:821); a global inherits into the wave subshell on fork with zero
   call-site churn. `--capture-tokens` sets `CAPTURE_TOKENS=1` in `cmd_run`'s parser (flag arm placed
   BEFORE the `--*)` unknown-flag catchall, or it is rejected); the flag is scripted/interactive sugar
   over the env.
2. **No new file, marker, extractor, or ledger.** The child stream lands in the existing
   `.orchestrate/<id>.stream.jsonl` (ADR-0032's "child.jsonl" is the concept, this is the instance).
   Usage extraction reuses `handoff_gen.py sum-usage`; the record reuses `gate-ledger.sh tokens`
   (the `| TOKENS |` marker, SPEC-110 SG-03). The downstream token hook in `cmd_run` (orchestrate.sh
   ~L1245) is UNCHANGED , it is already gated on `$slog` non-empty, so a SERIAL-path capture from
   the new trigger flows through it with no hook change.
3. **Default path byte-identical.** With neither flag/env nor `--stream`/`DETERMINISTIC_HANDOFF`
   set, `_run_one_session` takes the plain `claude -p` branch (no `--output-format stream-json`, no
   redirect, no tee). The conductor reads only claude's terse final result (the box-flip line) and
   the run honestly reports `usage=?` (SPEC-087 default-invocation pin intact).
4. **Scope: the SERIAL delegate path (the ADR-0032 §3 canonical single child).** ADR-0032 §3's form
   is one delegated `claude -p --stream > child.jsonl`. The SERIAL per-sub-goal path in `cmd_run`
   carries the token hook and is what this spec closes + over-tests. The WAVE path (`_wave_run`,
   SPEC-106 concurrency) has NO token hook today , it never has (SPEC-110 captured tokens only on the
   serial path). Under `CAPTURE_TOKENS=1` the wave subshell STILL writes each child's
   `.orchestrate/<id>.stream.jsonl` lean-to-file (the global inherits on fork, the redirect stays
   silent , the leanness property holds there too), but the per-sub-goal LEDGER extraction from those
   files is a DECLARED GAP, disclosed exactly like SPEC-110's watchdog-path gap, and filed as the next
   increment (the reap loop at orchestrate.sh:862 is the single wiring point). For dependency-chained
   or `## Touches`-less mega-goals (the dominant hardening-roadmap shape, incl. this one) the ready set
   is size-1 and everything runs the SERIAL path anyway, so the closed path is the load-bearing one.

## Design

The whole design turns on ONE distinction inside `_run_one_session`: a `| tee "$slog"` (stdout AND
file) versus a `> "$slog"` (file only). The bloat is entirely the `tee`.

```
                 orchestrate.sh run <dir>   (the thin conductor; holds roadmap + results only)
                          |
       trigger?  ---------+--------------------------------------------------
       |                  |                          |                       |
   (none)             --capture-tokens            --stream            DETERMINISTIC_HANDOFF=1
   plain -p           / CAPTURE_TOKENS=1          (live tail)         (handoff regen)
       |                  |                          |                       |
  claude -p          claude -p --stream         claude -p --stream     claude -p --stream
  (terse result       > child.jsonl             | tee child.jsonl      > child.jsonl
   to conductor)      (FILE ONLY)               (FILE + CONDUCTOR)     (FILE ONLY)
       |                  |                          |                       |
   conductor          conductor sees            conductor ABSORBS      conductor sees
   sees box-flip      box-flip only             full child stream      box-flip only
   usage=?            (LEAN) ✓                   (BLOAT) ✗ forbidden    (LEAN) ✓
                          |                                                  |
                          +--------------------- both -----------------------+
                                                 |
                    child.jsonl  --sum-usage-->  in/out/cache tokens  --gate-ledger tokens-->
                                                 <rid>.log  | TOKENS |  (SPEC-110 SG-03 marker)
```

**Stream-to-file path + file lifecycle.** The child's stream-json is redirected to
`$dir/.orchestrate/<id>.stream.jsonl` (existing naming, existing dir; `_run_one_session` already
mkdir's `.orchestrate`). Lifecycle: written per sub-goal session, overwritten on a re-run of the
same sub-goal (`>` truncates), read once by the post-session token hook, then left on disk as the
run artifact (same as `--stream` today , no new cleanup path, no new lifecycle to reason about).
It lives in the mega-goal dir, NOT in the conductor's context.

**Usage extraction.** Reuse `handoff_gen.py sum-usage <file>` verbatim: it sums assistant-only
`usage` blocks (input/output/cache_read/cache_creation), skipping the final cumulative
`type:"result"` event so totals are not double-counted (SPEC-110). Its output
`in=N out=N cache_read=N cache_create=N` feeds `gate-ledger.sh tokens <rid> ...` unchanged.

**How the conductor stays lean.** The child's `--output-format stream-json` transcript is written
to stdout by `claude -p`, and in the capture-tokens branch that stdout is redirected `> "$slog"`
(the FILE), so the TRANSCRIPT , the accumulation trap ADR-0032 §1 forbids , never reaches
`_run_one_session`'s stdout, which is what `cmd_run` forwards to the conductor. `--verbose` on the
child is therefore NOT an ADR-0032 §1 violation: the rule forbids the transcript piped TO THE
CONDUCTOR, and here it goes to the file. The conductor's stdout carries only the driver's own `_say`
telemetry lines and (on the plain path) claude's terse result. The grounded-completion signal is the
ROADMAP box flip read from disk (`_subgoals ... $3==1`), never parsed from stdout, so nothing about
lean-mode weakens completion detection. `--verbose` diagnostics on the child's STDERR are not the
transcript (they carry no `usage`/turn content) and the driver is non-LLM bash, so they are not an
accumulation vector; the test proves the property that matters , the transcript (fd1) is provably
absent from the forwarded stream , by capturing the child's stdout and stderr SEPARATELY rather than
merged. (Redirecting the child's stderr too is a possible future hardening for a stdout+stderr-merging
conductor invocation; deferred as it would also silence real error output on this opt-in path.)

**Why the tee is the whole bloat.** `--stream`'s `| tee "$slog"` writes the stream-json to BOTH the
file and stdout; the stdout copy is what floods the conductor. `--capture-tokens` reuses the same
`claude -p --stream` child invocation but drops the tee for a plain redirect , identical capture,
zero conductor cost. This is the reconciliation: capture needs the stream, the conductor must not
see it, so the stream goes to a file and only a file.

**False-bloat negative control.** The design is only meaningful if the forbidden path is
demonstrably worse. The test runs the SAME child (emitting a bulky stream-json body with a unique
sentinel) twice: once `--stream` (tee) , the sentinel MUST appear in the conductor's captured
stdout (bloat proven); once `--capture-tokens` , the sentinel MUST NOT appear in the conductor's
stdout but MUST appear in `child.jsonl` (lean proven), and both MUST record an identical TOKENS
line (capture correctness holds on the lean path).

## Test plan

Coverage matrix over the acceptance criteria, driven by the `CLAUDE_CMD` mock seam
(`tests/test-token-capture.sh`). A COVERAGE-DELTA row (covered + explicitly-uncovered) lands in the
proof-of-done.

| # | Category | Case | Assertion |
|---|----------|------|-----------|
| C1 | capture-correctness | `--capture-tokens` serial run, mock emits real-shape stream-json to stdout | a `\| TOKENS \|` line is recorded for the run's rid AND its `in/out/cache_read/cache_create` equals `sum-usage` of the written `child.jsonl` (matches the child's own totals) |
| C2 | conductor-stays-lean | same run | the child transcript sentinel is ABSENT from the conductor's captured STDOUT and PRESENT in `.orchestrate/<id>.stream.jsonl` |
| C3 | false-bloat NC | SAME child under `--stream` (tee) vs `--capture-tokens` (redirect) | sentinel PRESENT in conductor stdout under `--stream` (bloat proven) and ABSENT under `--capture-tokens` (lean proven), with both recording an identical TOKENS line |
| C4 | stderr-separation | capture run, child writes diagnostics to stderr | with stdout/stderr captured SEPARATELY, the transcript sentinel is absent from fd1 (the forwarded stream); the leanness claim is fd1-rigorous, not merged-capture-hand-wavy |
| C5 | env parity | `CAPTURE_TOKENS=1` env, no flag | identical behavior to `--capture-tokens` (TOKENS recorded, conductor lean) , proves the flag is sugar over the global and the global inherits |
| C6 | flag accepted | `orchestrate.sh run <dir> --capture-tokens` | NOT rejected as `unknown flag` (exit != 64 on the flag itself) |
| C7 | default NC | no flag, no env, no `--stream`/`DETERMINISTIC_HANDOFF` | NO stream-json child invocation, NO TOKENS line (honest `usage=?`), default invocation byte-unchanged |
| C8 | regression | full `tests/test-orchestrate.sh` | existing `--stream` capture + SPEC-110 token wiring + no-capture NC all still green |

**COVERAGE-DELTA , explicitly UNCOVERED (with reason):**
- **Wave-path per-sub-goal ledger extraction** , declared gap (`_wave_run` has no token hook; the
  child.jsonl is still written lean-to-file under waves). Not tested here; single wiring point filed.
- **Watchdog-path capture** , pre-existing SPEC-110 gap; unchanged, untested here.
- **Live LLM run** , mock seam only (deterministic + free); a live `claude -p` is not exercised.
- **stderr-redirect hardening** , the child's stderr is not redirected away from the conductor
  (deferred); C4 proves the fd1 transcript is clean, which is the load-bearing property.

## Verification

```bash
cd dwarves-kit
# The three load-bearing properties + the false-bloat NC, all via the CLAUDE_CMD mock seam:
bash tests/test-token-capture.sh
#   (a) capture correctness: a --capture-tokens delegate run records a TOKENS line whose usage
#       equals sum-usage of the child.jsonl the child emitted (matches the child's own totals).
#   (b) conductor-stays-lean: the child stream-json body (sentinel) is ABSENT from the conductor's
#       stdout under --capture-tokens, PRESENT in child.jsonl.
#   (c) false-bloat NC: the SAME child under --stream PUTS the sentinel in the conductor stdout
#       (bloat), while --capture-tokens leaves it out (lean) , the anti-pattern is proven worse.
#   (d) default-path NC: no flag/env -> no stream-json child, no TOKENS line (usage=?), byte-unchanged.
# Regression: the existing capture + token wiring still green.
bash tests/test-orchestrate.sh
```

## After state

- `lib/orchestrate.sh`: `CAPTURE_TOKENS` global (default 0) as a third trigger for the silent
  `> "$slog"` stream-to-FILE branch inside `_run_one_session` (no signature change); `--capture-tokens`
  flag arm in `cmd_run` (before the `--*)` catchall) that sets that global; the usage header, `main()`
  usage string, and `--dry-run` advisory list `--capture-tokens`. Default path byte-identical; serial
  token hook unchanged (already `$slog`-gated); `--stream` tee path unchanged (it is the NC's forbidden
  path); `_wave_run` untouched.
- `tests/test-token-capture.sh`: new; the three properties + false-bloat NC + default NC, with a
  COVERAGE-DELTA row (covered + explicitly-uncovered).
- `docs/verification/token-capture-delegate.md`: run-table with the green run, the COVERAGE-DELTA
  row, and the NC evidence.
- `docs/implementation-notes/token-capture-delegate.md`: the delta log (reuse-over-rebuild).

## Scope edges

**In:** the `--capture-tokens`/`CAPTURE_TOKENS` decoupled trigger for the existing silent
stream-to-file branch, the conductor-stays-lean guarantee, the tests + coverage-delta + false-bloat NC.
**Out:** the model routing (sub-goal 01); the TIER-4 mega close (03); the multiplexer panes (04);
the docs pass (05); flipping the SPEC-087 default path to json (SACRED pin).
**Not:** piping the child transcript (`--stream` tee) to the conductor (the forbidden bloat path ,
the NC guards it); inventing a second token-marker or a second capture file convention (reuse
SPEC-110's `| TOKENS |` + `.orchestrate/<id>.stream.jsonl`); rebuilding the token ledger, `sum-usage`,
or the telemetry aggregation (this feeds them under delegation, unchanged); the watchdog-path capture
(a declared SPEC-110 gap, still a gap); the WAVE-path per-sub-goal ledger extraction (`_wave_run` has
no token hook and never did; the child.jsonl is still written lean-to-file under waves, only the
extraction is deferred , declared gap, single wiring point at orchestrate.sh:862, filed as the next
increment); changing the signature of `_run_one_session` or touching `_wave_run`'s call site (the
global mechanism avoids both).

## Open questions

The proof uses the kit's standard MOCK `CLAUDE_CMD` (the test-orchestrate seam) emitting a
real-shape stream-json, exercising the REAL orchestrate -> silent-capture -> sum-usage ->
gate-ledger-tokens path deterministically, without a live LLM call. If SPEC-110's canonical
ledger-observatory schema for the `| TOKENS |` marker ever diverges from `sum-usage`'s output,
defer to that schema (this spec reuses, never redefines it).
