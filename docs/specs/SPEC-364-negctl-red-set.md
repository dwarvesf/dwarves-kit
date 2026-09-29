# Spec: negctl records which cases went red, and can assert the red set

Generated: 2026-09-29
Status: DRAFT (round 1 NEEDS REVISION folded: 3 criticals, all warnings)
Lane: full (lane-classify: the change edits `lib/gate/`, the proof-of-done enforcement surface)
Type: spec-feature
File: `docs/specs/SPEC-364-negctl-red-set.md`
References: `lib/gate/negctl.sh` (the tool this extends; its `NEGCTL_RED_ATTEMPTS` knob and `--at` flag loop are the shape to imitate for a new option, and its `--at` export's `mktemp "${tmp_base%/}/negctl-at.XXXXXX"` is the temp-file form to copy), `lib/gate/proof-ledger.sh` `check()` lines 295-360 (the parser whose grammar must not move), `tests/test-proof-negctl.sh` (the suite this extends, and its line-anchored mutations that must keep resolving)

## Problem

`lib/gate/negctl.sh` runs every test command with `>/dev/null 2>&1` (`run_test`, line 189; the base-ref run, line 132). Its proof block records one exit code for the whole suite under the mutation. Two gaps follow:

1. A proof never shows which cases went red. A reader sees `Exit: 1 (under mutation, RED expected)` and nothing else.
2. A mutation that reddens an unrelated case still reports `Verdict: PASS`. The control proves "something broke", not "the case that guards this change broke".

Workers in one session worked around this four or more times: per-label wrapper scripts, separate logs, and a manual rerun of the red state to read the FAIL lines. `commands/wrap.md` already names the same loop, hand-rolled four times, as the reason negctl exists.

## Change

negctl writes each red attempt's combined output to a temp log, parses failing case labels from the log of the attempt that ends the red step, and prints one new line in its block, directly after the red `Exit:` line:

```
Red: <label>, <label>, ... (+N more)
```

A new opt-in flag, `--expect-red "<label>[,<label>...]"`, turns the red set into an assertion. The verdict FAILs when the observed set differs from the expected set, ranked below every existing failure reason. Mutate mode (including `--at`) and `--base-ref` mode get both behaviors.

Every existing line keeps its bytes. With no `--expect-red`, the only new output is the `Red:` line. A red log that cannot be created or written stops negctl with exit 1 before it can read a capture failure as RED.

## Design

Design-bearing: a new CLI flag on a proof tool, a new line in a parsed block, a new fail-closed path, and two viable matching rules. Approaches below; the picture follows.

### Picture

```
negctl.sh [--expect-red L1,L2] [--at sha ...] root test-cmd mutate-cmd
   |
   | helpers defined first (before the base-ref block): _red_labels, _expect_red_check, _cap_list
   | --expect-red parsed + validated in the flag loop (empty / control char -> exit 64)
   |
   | red_log = mktemp "${TMPDIR:-/tmp}/negctl-red.XXXXXX"   (under root? -> /tmp/negctl-red.XXXXXX)
   |           failure -> "negctl: red-log capture failed", exit 1   (BEFORE step 2, nothing mutated)
   |
   | step 2  run_test ----------------------------------> /dev/null   (unchanged)
   | step 3  mutate
   | step 4  per attempt:  : >"$red_log"  (fail -> "red-log capture failed", exit 1; EXIT trap restores)
   |                       run_test ---------------------> red_log     (fresh content each attempt)
   |         after the loop:
   |           Exit: <rc> (under mutation, RED expected)          (unchanged bytes)
   |           _red_labels red_log  -> red_labels[]   (prints nothing)
   |           caller prints  "Red: <_cap_list red_labels>"
   |           caller prints  "Expect red: <list>"            (flag only)
   |           _expect_red_check    -> red_mismatch   (prints nothing; reason held, not yet failed)
   |           vacuous check (rc_red = 0) -> fail "test stayed green ..."   (unchanged, first)
   | step 5  restore()   body also: rm -f "$red_log"
   | step 6  run_test ----------------------------------> /dev/null   (unchanged)
   |         restore/tree/green-after failures -> fail(...)         (unchanged)
   |         red_mismatch set -> fail "red set differs ..."          (LAST, just before Verdict)
   v
 Verdict: PASS | FAIL: <first reason>

 --base-ref: log created before the base-ref run (same fail-closed exit), cleanup() body also
 removes it; Red:/Expect red: after its Exit: line; own verdict: "passed at <ref>" first,
 then the red-set mismatch.
```

### Approaches considered

1. Parse FAIL lines from the red run, print `Red:`, optional boundary-prefix `--expect-red` (chosen). One executable file changes. Callers and the gate see one extra line.
2. Exact string equality for `--expect-red` (rejected). Kit suites put interpolated detail after the label (`no "rc=$RC out=$OUT"`, `--- FAIL: TestX (0.00s)`), so an exact label changes every run and the operator cannot write it in advance.
3. Plain prefix match (rejected). `T1` would match `T10`, so a wrong case going red would pass.
4. A sibling script or a per-suite label adapter (rejected). The lead's precedent rule is to extend negctl. An adapter per suite is the hand-rolled wrapper this spec removes.
5. Capture into a shell variable with `$(...)` instead of a temp file (rejected). `$(...)` waits for every holder of stdout to close, so a test that backgrounds a process inheriting stdout would hang negctl. A redirect to a file never waits.
6. `mktemp -t negctl-red.XXXXXX` for the log (rejected, see Grounding). On macOS it ignores `TMPDIR`, so neither the unwritable-TMPDIR test nor the under-root fallback can be exercised there. The explicit-template form already used by `--at` honors `TMPDIR` on both platforms.

### Interfaces (I/O contract)

- New flag: `--expect-red <list>`, accepted in the leading flag loop beside `--at`/`--path`/`--setup`, in any order among them, so it works in all three modes. `<list>` is comma-separated; each entry is trimmed of surrounding spaces. Exit 64 with a usage line when: the value is missing or empty, an entry is empty after trimming, or an entry contains a control character (`[[:cntrl:]]` under `LC_ALL=C`).
- Match rule (fixed strings only): entry `E` matches label `L` when `[ "$L" = "$E" ]`, or `L` starts with the literal `E` followed by one `[[:space:]]` or `:` character (`case "$L" in "$E"[[:space:]]*|"$E":*)`, `$E` quoted so `[38]` is never a glob). Every entry must match at least one label (else "missing"); every label must be matched by at least one entry (else "unexpected").
- Label parse, one linear pass, `LC_ALL=C sed -nE '...' "$log" | awk '!seen[$0]++'` (a final line with no newline is kept):
  1. strip ANSI SGR sequences (`ESC[...m`) and a trailing CR;
  2. drop Go's package summary line, `FAIL<TAB><pkg><TAB><duration>s` or `FAIL<TAB><pkg><TAB>[...]`, and TAP directive lines, `not ok ... # TODO|# SKIP` (case-insensitive);
  3. a line is a failure line when it matches `^[[:space:]]*(FAIL:?|FAILED|--- FAIL:|not ok( <n>)?( -)?|✗|✘|✕|✖|×)[[:space:]]+([^[:space:]].*)$` (`not ok` case-insensitive); the label is the last group, so it starts with a non-space;
  4. strip every remaining C0 byte and DEL from the label.
  Dedup keeps the first occurrence and the order.
- Helpers print nothing. `_red_labels <log>` fills the global array `red_labels` (initialized empty at the top of the script) and returns 0. `_expect_red_check` fills the global `red_mismatch` with the reason (empty on a match) and returns 1 on a mismatch. `_cap_list` formats a list into the global `capped`. The caller prints every line. Their header lines are pinned as `^_red_labels() {$` and `^_expect_red_check() {$` (the negative controls mutate them).
- New output lines, after the red `Exit:` line, in this order:
  - `Red: <label>, <label>` or `Red: <none parsed>`. `_cap_list`: at most 20 items, each cut to 100 chars with `...`; a longer list appends ` (+N more)`.
  - With `--expect-red` only: `Expect red: <entries, trimmed, comma-space joined>`.
- Verdict on a mismatch: `Verdict: FAIL: red set differs from --expect-red: missing <list>; unexpected <list>`, each list through `_cap_list`, only the non-empty half printed.
- Verdict precedence (mutate mode): every existing reason ranks first, the mismatch last. `fail()` keeps the first reason, and the mismatch `fail` call sits directly before `echo "Verdict: $verdict"`. Base-ref mode: "the check passed at <ref>" first, then the mismatch.
- Fail-closed capture: `negctl: red-log capture failed` on stderr and exit 1 when `mktemp` fails or a per-attempt `: >"$red_log"` fails. No `Verdict:` line prints on that path.
- Log placement: if the resolved log directory (`cd -P`) equals `<root>` or sits under it, negctl removes that log and creates one with `mktemp /tmp/negctl-red.XXXXXX` instead, so the step-2/step-6 snapshot never sees it.
- Log removal: one body line in `restore()` (after its `trap '' INT TERM HUP` line) and one in base-ref's `cleanup()`. No new `trap` line: the suite splices `restore() {` .. `trap restore EXIT` by line anchor.
- Invariants: `Command:`, every `Exit:` line, `Verdict:`, `Mutation:`, `Changed:`, `Restore:`, `Side effect:`, `Base ref:`, `At:`, `Export:`, `Setup:` keep their exact bytes and order. The script stays bash 3.2 safe: every array expansion that can be empty sits behind a `${#arr[@]} -gt 0` guard.

## Failure modes

| Failure class | Detection signal | Mitigation |
|---|---|---|
| The red log cannot be created or written (`TMPDIR` missing or read-only, disk full) | `mktemp` or `: >"$red_log"` fails | `negctl: red-log capture failed`, exit 1, no `Verdict:` line. Without this, `run_test >""` returns 1 without running the test, and a vacuous mutation reads as RED and PASSes |
| `TMPDIR` points inside `<root>` | Resolved log dir equals or sits under `<root>` | Log moves to `/tmp`; the tree snapshot never sees it |
| Labels copy test output into a proof file that gets committed | A label carries a path, a token, or a customer string | 20-label and 100-char caps bound the copy; C0 bytes stripped; the operator reviews the proof before commit and the kit's secret hooks scan the commit; documented in the header comment and `docs/verification/README.md` |
| Suite prints failures in a shape the regex does not know | `Red: <none parsed>` on a red run | The line says so plainly; `--expect-red` then FAILs as "missing", never a silent PASS |
| A summary line looks like a failure (`FAIL: 3 of 40 failed`) | A count appears as a label | Named in the docs; `--expect-red` reports it as "unexpected", which is fail-closed |
| Label carries a huge interpolated payload (`out=$OUT`) | A multi-kilobyte line | Only that one line is the label; `_cap_list` cuts it to 100 chars in `Red:` and in the Verdict; comparison uses the full text |
| A stale label from an earlier green retry attempt | Label from attempt 1 shows under attempt 2 | Each attempt truncates the log first; only the last attempt's output is parsed (case [50]) |
| Red log left behind after an interrupt mid-run | A stray `negctl-red.*` file in `$TMPDIR` | `restore()` removes it on every EXIT-trap path; residue only if the process is killed with SIGKILL |
| An edit shifts a line the suite anchors a mutation on | Cases [25]-[32] resolve `ln` to the wrong line | New code adds no line containing `  if [ "${#beyond[@]}" -gt 0 ]; then`, `    if [ "${#baseline_diff[@]}" ...`, `  restore_done=1`, or `  trap '' INT TERM HUP` before their current first occurrence; helpers use other variable names |
| A label contains a comma | `--expect-red` cannot name it whole | The boundary rule lets the entry stop before the comma; documented |

## Grounding

Sampled read-only on 2026-09-29 in this worktree, base `917a2754` unless a row says otherwise.

| Claim | Command | Excerpt |
|---|---|---|
| Today the red run's output is discarded and the block carries one exit code | `bash lib/gate/negctl.sh --at HEAD "$PWD" "bash tests/test-proof-visual-evidence.sh" "sed -i.bak 's/^_has_committed_image() {\$/_has_committed_image() { return 0/' lib/gate/proof-ledger.sh && rm -f lib/gate/proof-ledger.sh.bak"` | `Exit: 1 (under mutation, RED expected)` / `Restore: git checkout HEAD -- lib/gate/proof-ledger.sh` / `Exit: 0 (green after restore)` / `Verdict: PASS`; no case is named |
| The same mutation reddens two cases, one of them unrelated to "dangling image" | the same mutation applied by hand in that export, `bash tests/test-proof-visual-evidence.sh` | `FAIL dangling image should BLOCK but ACCEPTED`, `FAIL no evidence should BLOCK but ACCEPTED`, `2 FAILED`, rc=1. A worker proving the dangling-image fix gets `PASS` for a control that also broke the no-evidence case |
| Kit suites print failures as `FAIL <label>`, `  FAIL: <label>`, `NOT ok - <label>`, or ANSI-coloured `FAIL` | `grep -hE '^\s*(fail\|no\|bad)\s*\(\)' tests/*.sh \| sort \| uniq -c` | `12 fail() { echo "FAIL $*"; ...}`, `11 no() { ...; echo "NOT ok - $1"; }`, `10 bad() { ...; echo -e " ${RED}FAIL${NC} $1"; }`, `5 no(){ echo "  FAIL: $*" >&2; ...}` |
| The parse regex extracts those shapes and skips summaries | the regex run over sample lines with BSD sed, `LC_ALL=C` | in: `FAIL add-2-2`, `  FAIL: add-0-0`, `ESC[0;31mFAILESC[0m add-neg`, `not ok 4 - add-tap`, `NOT ok - add-cap`, `✗ add-check`, `--- FAIL: TestAdd (0.00s)`, `FAILED tests/test_x.py::test_add - AssertionError`, `FAILS: 3`, `2 FAILED`, `ok: mul`, `test-x: 1 passed, 1 FAILED`, `FAIL crlf\r`; out: the first eight labels plus `crlf`; the four summary/pass lines produce nothing |
| Go's package summary line is droppable by its tab shape; a final line with no newline survives sed + awk | `printf 'FAIL\tgithub.com/x/pkg\t0.012s\n' \| LC_ALL=C sed -nE $'/^FAIL\t[^\t]+\t([0-9.]+s\|\\[[^]]*\\])$/d; s/^FAIL[[:space:]]+([^[:space:]].*)$/\\1/p'`; `printf 'FAIL a\nFAIL last' \| LC_ALL=C sed -nE 's/^FAIL (.+)$/\1/p' \| awk '!seen[$0]++' \| od -c` | first: no output; second: `a \n l a s t \n` |
| macOS `mktemp -t` ignores `TMPDIR`; the explicit template honors it | `TMPDIR=/nonexistent/x mktemp -t negctl-red.XXXXXX`; `mktemp /nonexistent/x/negctl-red.XXXXXX` | first: `/var/folders/.../T/negctl-red.XXXXXX.VhukmZBlpa`, rc=0 (TMPDIR ignored); second: `mkstemp failed on /nonexistent/x/negctl-red.Q6bG6I: No such file or directory`, rc=1 |
| A capture redirect to an empty path returns non-zero without running the command | reasoning from bash semantics: `bash -c 'true' >""` fails the redirect (`No such file or directory`) and the command never runs | the step-4 `rc_red` would be 1, read as RED. Named by round-1 R2/R3; case [49] and NC3 prove the guard |
| The current default block, byte for byte (the golden [44] pins) | `negctl.sh <fixture> "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak"` on a fixture that prints `FAIL add-2-2` when `add` is broken | `## Negative control (negctl)`, `Command: bash test.sh`, `Exit: 0 (green before mutation)`, `Mutation: sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak`, `Changed: lib.sh`, `Exit: 1 (under mutation, RED expected)`, `Restore: git checkout HEAD -- lib.sh`, `Exit: 0 (green after restore)`, `Verdict: PASS`; rc=0. That fixture's second assertion, `add 0 0 = 0`, never fails under `s/+/-/` (0-0 is 0), so no fixture here uses it |
| The gate reads only `Command:`/`Exit:`/`Verdict:`/`NEGATIVE CONTROL`, the last `Verdict:` anchored at line start | `grep -n 'Verdict\|Exit:\|NEGATIVE' lib/gate/proof-ledger.sh` | line 313 `last_v="$(grep -iE '^[[:space:]]*Verdict:' "$p" \| tail -1)"`; line 315 `grep -qE 'Exit:[[:space:]]*0\|VERDICT: PASS\|Verdict: PASS\|PASS'`. A line starting `Red:` or `Expect red:` cannot become the last `Verdict:` |
| The suite anchors mutations on literal lines of negctl.sh | `grep -nE 'grep -Fn' tests/test-proof-negctl.sh` | lines 249, 288, 305, 343, 396 resolve `ln` from `head -1` of a fixed-string match; lines 47-48 anchor `^restore() {$` and `^trap restore EXIT$` |
| FEATURES registry: fresh at the base, stale at the spec commit | `bash lib/registry/feature-registry.sh check docs/FEATURES.md` | at `917a2754`: rc=0. At `72417bbb` (this spec committed): rc=1, `docs/FEATURES.md has DRIFTED`, five rows' SPEC-reference counts differ (`/kit:docs`, `/kit:next`, `/kit:spec`, `/kit:start`, `/kit:wrap`); `tests/test-meta.sh` fails `docs/FEATURES.md is fresh`, `Passed: 878 / 879` |

Not sampled: a JS runner's `✗`/`✕`/`✖`/`×` output and Go's `--- FAIL:` from a real run. No such suite exists in this repo. The regex covers the shapes from their documented output; a miss shows as `Red: <none parsed>`, never a false PASS under `--expect-red`.

### Negative control dry traces

The new cases print `no "[NN] <one-line reason>"`, so the label of a failing new case starts with its case number and `--expect-red "[NN]"` names it. Each run uses `--at <build-sha>`, so the outer negctl never runs from the file it mutates. The final case lists are fixed at build time and recorded in the proof; these traces are updated if a list moves.

Fixtures (all in `mkrepo`, all driven by `add()` in `lib.sh`, mutated by `s/+/-/`):
- `test-labels.sh`: when `add 2 2` is not 4, prints `FAIL add-2-2 got 0` (stdout), `  FAIL: add-neg` (stderr), `ESC[31mFAILESC[0m add-ansi`, `not ok 4 - add-tap`, `not ok 5 - add-todo # TODO later`, `✗ add-check`, `✕ add-x`, `FAIL [t7] add-bracket`, `FAIL add-cr` + CR, `FAIL<TAB>example.com/pkg<TAB>0.01s`, `ok: mul`, and a final `FAIL add-last` with no newline; exits 1. Expected `Red:` is `add-2-2 got 0, add-neg, add-ansi, add-tap, add-check, add-x, [t7] add-bracket, add-cr, add-last`.
- `test-many.sh`: when broken, prints `FAIL many 01` .. `FAIL many 24` and one `FAIL long ` + 300 `x`; exits 1. The space after `many` and `long` lets the entries `many` and `long` match every label under the boundary rule.
- `test-golden.sh`: when broken, prints `FAIL add-2-2`; exits 1 (the [44] golden fixture).
- `test-flaky.sh`: counter file; run 1 (baseline) green; run 2 (attempt 1) prints `FAIL stale-1`, exits 0; run 3 (attempt 2) prints `FAIL flaky-2`, exits 1; run 4+ green.
- BREPO (base-ref cases): two commits; `test-labels.sh` identical in both; `lib.sh` broken at the base commit only.

NC1, the parser.
- Mutation: `sed -i.bak 's/^_red_labels() {$/_red_labels() { return 0/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak`.
- Code path: step 4 writes the fixture output to the log; `_red_labels` returns before filling `red_labels`, which stays empty; the caller prints `Red: <none parsed>`.
- Red: [38] (exact `Red:` line), [39] (expects PASS, gets FAIL "missing"), [40] (first run expects PASS), [41] (asserts `unexpected add-x`; the verdict says only `missing`), [43] (asserts `(+5 more)` in `Red:`), [44] (asserts the exact line `Red: add-2-2`), [45] (asserts labels in base-ref and `--at` mode), [50] (asserts `Red: flaky-2`), [51] (asserts `Red: add-2-2`). Green: [42] (asserts `missing .*mul-2-3`, still true), [46] (usage exit 64, before any run), [47] (static block), [48] (vacuous reason still wins), [49] (exits before any parse), and [1]-[37], none of which reads `Red:`.
- Run: `bash lib/gate/negctl.sh --expect-red "[38],[39],[40],[41],[43],[44],[45],[50],[51]" --at <build-sha> "$PWD" "bash tests/test-proof-negctl.sh" "<mutation>"`.

NC2, the comparison.
- Mutation: `sed -i.bak 's/^_expect_red_check() {$/_expect_red_check() { return 0/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak`.
- Code path: parse and `Red:` still work; `red_mismatch` stays empty, so no mismatch `fail` fires.
- Red: [40] (second run expects FAIL `missing add-2`), [41], [42], [43] (its mismatch run expects the capped `unexpected` list), [45] (its mismatching list expects FAIL), each getting PASS. Green: [38], [39], [44], [46], [47], [48], [49], [50], [51].
- Run: the same form with `--expect-red "[40],[41],[42],[43],[45]"`.

NC3, the fail-closed capture.
- Mutation: `sed -i.bak '/red-log capture failed/s/exit 1; }/true; }/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak` (the guard lines have the shape `|| { echo "negctl: red-log capture failed" >&2; exit 1; }`).
- Code path under [49] (`TMPDIR` a missing dir): `mktemp` fails, `red_log` is empty, the guard no longer exits; step 2 goes to /dev/null and is green; step 4's `: >""` fails and is ignored; `run_test >""` fails the redirect, rc=1, read as RED; verdict PASS.
- Red: [49] only (asserts exit 1, the stderr message, and no `Verdict: PASS`). Green: every other case, because a writable `TMPDIR` never reaches the guard's failure branch.
- Run: the same form with `--expect-red "[49]"`.

## Test plan

New cases in `tests/test-proof-negctl.sh`, numbered after [37]. Each prints `no "[NN] <one-line reason>"` on failure: the `rc`, the `Verdict:` line, and the `Red:` line, never a multi-line `$OUT` dump.

| Case | Kind | Input | Expect |
|---|---|---|---|
| [38] | happy | real mutation, `test-labels.sh` | PASS; exactly one `Red:` line, directly after the red `Exit:` line, equal to the expected `Red:` in the fixture list (covers ANSI, stderr, CR, `✕`, TAP TODO skip, Go summary skip, bracket label, final line with no newline) |
| [39] | happy | `--expect-red "add-2-2, add-neg,add-ansi , add-tap,add-check,add-x,[t7] add-bracket,add-cr,add-last"` (spaced entries), run once under `/bin/bash` when it exists | PASS; `Expect red:` line lists the trimmed entries; the `[t7]`-shaped entry matches as a fixed string |
| [40] | boundary | entry `add-2-2` matches `add-2-2 got 0` (space boundary); entry `add-2` must not (next char `-`); entry `[t7]` matches `[t7] add-bracket`, entry `[t` must not | first run PASS; second FAIL naming `missing add-2` and `unexpected add-2-2 got 0` |
| [41] | negative | `--expect-red` omits `add-x` | FAIL `red set differs ... unexpected add-x`; exit 1; tree clean |
| [42] | negative | `--expect-red` adds `mul-2-3` | FAIL `... missing mul-2-3`; exit 1; tree clean |
| [43] | bound | `test-many.sh`: 25 labels, one of 305 chars | `Red:` shows 20 labels and `(+5 more)`, the long label cut to 100 chars with `...`; `--expect-red "many,long"` PASSes (full set compared); `--expect-red "zzz"` FAILs with `missing zzz` and an `unexpected` list of 20 plus `(+5 more)` |
| [44] | compat | `test-golden.sh`, no flag | stdout with the `Red:` line removed equals the Grounding golden (command name swapped) byte for byte; the line directly after the red `Exit:` line is exactly `Red: add-2-2` |
| [45] | modes | BREPO `--base-ref` with a matching then a mismatching `--expect-red`; `--at HEAD` on REPO with no flag | base-ref: `Red:` directly after its `Exit:` line, matching PASS, mismatching FAIL `red set differs`; `--at`: `Red:` equals the [38] line, live tree untouched |
| [46] | usage | `--expect-red ""`, `"a,,b"`, `" , "`, an entry with a TAB, flag with no value | each exits 64, usage on stderr, no `## Negative control` header |
| [47] | integration | a static PASS block with `Red:` + `Expect red:` lines (text pinned in the test) in a proof file | `proof-ledger.sh check` accepts it; the same file ending on `Verdict: FAIL: red set differs ...` is refused |
| [48] | precedence | vacuous mutation (`printf '\n# c\n' >> lib.sh`) with `--expect-red x` | `Verdict: FAIL: test stayed green under the mutation (the check is vacuous)`; exit 1; tree clean |
| [49] | fail-closed | `TMPDIR="$TMP/missing-dir"` for the negctl call, real mutation | exit 1; stderr `negctl: red-log capture failed`; no `Verdict: PASS`; tree clean |
| [50] | retries | `NEGCTL_RED_ATTEMPTS=3`, `test-flaky.sh` | PASS; `Exit: 1 (... attempt 2 of 3)`; `Red: flaky-2` exactly (the stale-1 label from the green attempt is gone) |
| [51] | placement | `TMPDIR="$REPO/.tmp"` (an empty dir inside root, invisible to `git status` until a file lands in it), `test-golden.sh` | PASS; `Red: add-2-2`; no `negctl-red.*` file under `$REPO` afterwards; tree clean |

The existing cases [1]-[37] stay green unchanged.

## Acceptance Criteria (global)

- AC1: every negctl run that reaches the red step prints exactly one `Red:` line directly after the red `Exit:` line, in mutate, `--at`, and `--base-ref` modes ([38], [44], [45]).
- AC2: `--expect-red` FAILs the verdict on any missing or unexpected label under the fixed-string boundary rule, and PASSes on an equal set ([39]-[43], [45]). Every existing failure reason outranks the mismatch ([48]).
- AC3: a red log that cannot be created or written exits 1 with `negctl: red-log capture failed` and never prints `Verdict: PASS` ([49]).
- AC4: with no `--expect-red`, the block equals the pre-change block plus the `Red:` line ([44]). `proof-ledger.sh check` accepts it ([47]).
- AC5: the header comment in `negctl.sh`, the usage lines in `proof-ledger.sh`, and `docs/verification/README.md` item 2 describe `Red:`, `--expect-red`, and the proof-content caution (Verification greps below).
- AC6: no log lands inside `<root>`, and the tree is clean after every new case ([49], [51]).
- AC7: the Verification command passes, and NC1, NC2, and NC3 each go red with exactly the case set their traces name.

## Verification

```
bash tests/test-proof-negctl.sh &&
bash tests/test-proof-visual-evidence.sh &&
grep -q -- '--expect-red' lib/gate/negctl.sh &&
grep -q '^# .*Red:' lib/gate/negctl.sh &&
grep -q -- '--expect-red' lib/gate/proof-ledger.sh &&
grep -q -- '--expect-red' docs/verification/README.md &&
grep -q 'Red:' docs/verification/README.md &&
grep -q '^_red_labels() {$' lib/gate/negctl.sh &&
grep -q '^_expect_red_check() {$' lib/gate/negctl.sh &&
bash tests/test-hooks.sh &&
bash tests/test-meta.sh &&
bash lib/registry/feature-registry.sh check docs/FEATURES.md
```

Then NC1, NC2, NC3 from `## Grounding`, recorded in `docs/verification/negctl-red-set.md`.

## Edge Cases

1. The red run prints no parseable line: `Red: <none parsed>`; with `--expect-red`, FAIL "missing <all>".
2. The mutation is vacuous (test stays green): `Red:` still prints what it parsed; the verdict reason stays "test stayed green", because it is failed before the mismatch ([48]).
3. `NEGCTL_RED_ATTEMPTS=3`: each attempt truncates the log first; labels come from the last attempt run ([50]).
4. A green retry attempt that leaves tracked dirt: the existing FAIL fires first and stops retries; `Red:` parses that last attempt's log.
5. The same label printed twice (stdout and stderr): listed once.
6. A label with a trailing CR, a tab, or other C0 bytes: CR and C0 stripped ([38]).
7. An `--expect-red` entry with surrounding spaces: trimmed ([39]). An entry with a control character: exit 64 ([46]).
8. Test output with invalid UTF-8: parsed under `LC_ALL=C`, so sed never aborts on a byte sequence.
9. `--expect-red` combined with `--at` and `--path`: flag order is free among the leading flags.
10. A `Red:` label that itself contains `Verdict: PASS`: the gate's `Verdict:` match is anchored at line start, and the line starts with `Red:`.
11. `TMPDIR` unset: the template falls back to `/tmp`, same as `--at`.
12. A restore or tree-snapshot failure together with a mismatch: the restore/tree reason wins ([48]'s rule, applied by `fail()` order).

## Out of Scope

- Naming a case from a section header when the FAIL line holds only detail (the kit's own `echo "[N] ..."` + `no "rc=..."` shape). New cases here put the case id in the FAIL line; old suites are not rewritten.
- Labels from the green runs (steps 2 and 6).
- A structured (JSON) proof block.
- Any change to `proof-ledger.sh check()`.

## Touches
- lib/gate/**
- tests/**
- docs/verification/**
- docs/implementation-notes/**
- docs/specs/**
- docs/FEATURES.md

## Tasks

- [ ] T1: `lib/gate/negctl.sh`: helpers (`_red_labels`, `_expect_red_check`, `_cap_list`) defined before the base-ref block; `--expect-red` in the flag loop with the usage checks; fail-closed log creation before step 2 and before the base-ref run, with the under-root fallback; per-attempt `: >"$red_log"`; `Red:` / `Expect red:` lines; mismatch `fail` just before `Verdict:` (base-ref: after "passed at"); log removal in `restore()` and `cleanup()` bodies; header comment. Keep every anchor line the suite resolves.
  Depends on: nothing.
- [ ] T2: `tests/test-proof-negctl.sh`: fixtures `test-labels.sh`, `test-many.sh`, `test-golden.sh`, `test-flaky.sh` in `mkrepo`, a BREPO for base-ref, cases [38]-[51], header comment.
  Depends on: T1 (the cases exercise its interface).
- [ ] T3: `lib/gate/proof-ledger.sh` usage comment and `docs/verification/README.md` item 2 (`Red:`, `--expect-red`, the proof-content caution).
  Depends on: T1.
- [ ] T4: run Verification; run NC1, NC2, NC3 and write `docs/verification/negctl-red-set.md`; then, unconditionally, `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md` and re-run its `check`.
  Depends on: T1, T2, T3.

## Decision Log
- DEC-A: match rule is "equal, or the literal entry followed by one space-class or colon character". Exact match cannot name a label with interpolated detail; a bare prefix lets `T1` match `T10`.
- DEC-B: the red log is a temp file, never a `$(...)` capture, so a test that leaves a background process holding stdout cannot hang negctl.
- DEC-C: `Red:` always prints on the red step, flag or no flag. The lead asked for the labels in every proof; one additive line keeps every existing line byte-identical.
- DEC-D: `_cap_list` bounds display in `Red:` and in the Verdict's missing/unexpected lists; the comparison always uses the full parsed set.
- DEC-E: the new code adds no `trap` line; log removal is a body line in `restore()` and `cleanup()`. The suite splices `restore()` by line anchor.
- DEC-F (round 1, R2/R3 critical): the capture fails closed. A failed `mktemp` or per-attempt truncate exits 1 before any verdict, because a failed redirect returns 1 and would read as RED.
- DEC-G (round 1, R4 critical): the mismatch is the lowest-ranked reason. The vacuous reason and every restore, tree, and green-after failure outrank it; the mismatch `fail` call sits last.
- DEC-H (round 1, R4 critical): `docs/FEATURES.md` is in Touches and T4 regenerates it unconditionally; this spec's own commit drifts it.
- DEC-I (deviation from the round-1 fold text): the log uses `mktemp "${TMPDIR:-/tmp}/negctl-red.XXXXXX"`, not `mktemp -t`. Grounding shows macOS `mktemp -t` ignores `TMPDIR`, which would make [49] and [51] unprovable on macOS. The explicit template is the form `--at` already uses and is equally named.
- DEC-J (round 1 warning): helpers print nothing and communicate through globals and return status; the caller owns every printed line, so a mutated helper cannot also change the block's shape.
