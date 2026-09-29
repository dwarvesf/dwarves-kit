# Spec: negctl records which cases went red, and can assert the red set

Generated: 2026-09-29
Status: DRAFT
Lane: full (lane-classify: the change edits `lib/gate/`, the proof-of-done enforcement surface)
Type: spec-feature
File: `docs/specs/SPEC-364-negctl-red-set.md`
References: `lib/gate/negctl.sh` (the tool this extends; its `NEGCTL_RED_ATTEMPTS` knob and `--at` flag loop are the shape to imitate for a new option), `lib/gate/proof-ledger.sh` `check()` lines 295-360 (the parser whose grammar must not move), `tests/test-proof-negctl.sh` (the suite this extends, and its line-anchored mutations that must keep resolving)

## Problem

`lib/gate/negctl.sh` runs every test command with `>/dev/null 2>&1` (`run_test`, line 189; the base-ref run, line 132). Its proof block records one exit code for the whole suite under the mutation. Two gaps follow:

1. A proof never shows which cases went red. A reader sees `Exit: 1 (under mutation, RED expected)` and nothing else.
2. A mutation that reddens an unrelated case still reports `Verdict: PASS`. The control proves "something broke", not "the case that guards this change broke".

Workers in one session worked around this four or more times: per-label wrapper scripts, separate logs, and a manual rerun of the red state to read the FAIL lines. `commands/wrap.md` already names the same loop, hand-rolled four times, as the reason negctl exists.

## Change

negctl keeps the red run's combined output in a temp file, parses failing case labels from it, and prints one new line in its block, directly after the red `Exit:` line:

```
Red: <label>, <label>, ... (+N more)
```

A new opt-in flag, `--expect-red "<label>[,<label>...]"`, turns the red set into an assertion. The verdict FAILs when the observed set differs from the expected set. Both mutate mode (including `--at`) and `--base-ref` mode get both behaviors.

Every existing line keeps its bytes. With no `--expect-red`, the only new output is the `Red:` line.

## Design

Design-bearing: a new CLI flag on a proof tool, a new line in a parsed block, and two viable matching rules. Approaches below; the picture follows.

### Picture

```
negctl.sh [--expect-red L1,L2] [--at sha ...] root test-cmd mutate-cmd
   |
   | step 2  run_test ---------------------------> /dev/null      (unchanged)
   | step 3  mutate
   | step 4  run_test (each red attempt) --------> red_log (mktemp, outside root)
   |              |
   |              v
   |         _red_labels red_log
   |           strip ANSI + CR
   |           match marker: FAIL | FAIL: | FAILED | --- FAIL: | not ok [n] [-] | ✗ ✘ ×
   |           label = rest of line, dedup, order kept
   |              |
   |              +--> "Red: a, b, ... (+N more)"   (20 labels shown, 100 chars each)
   |              |
   |              +--> --expect-red set?  compare FULL observed set (not the display cut)
   |                     missing or unexpected --> fail "red set differs ..."
   |         rm red_log
   | step 5  restore        (unchanged)
   | step 6  run_test ---------------------------> /dev/null      (unchanged)
   v
 Verdict: PASS | FAIL: <first reason>    (fail() keeps the FIRST reason, so "vacuous" wins)

 --base-ref mode: the single RED run takes the same red_log -> _red_labels -> compare path.
```

### Approaches considered

1. Parse FAIL lines from the red run, print `Red:`, optional prefix-bounded `--expect-red` (chosen). One file changes. Callers and the gate see one extra line.
2. Exact string equality for `--expect-red` (rejected). Kit suites put interpolated detail after the label (`no "rc=$RC out=$OUT"`, `--- FAIL: TestX (0.00s)`), so an exact label changes every run and the operator cannot write it in advance.
3. Plain prefix match (rejected). `T1` would match `T10`, so a wrong case going red would pass.
4. A sibling script or a per-suite label adapter (rejected). The lead's precedent rule is to extend negctl. An adapter per suite is the hand-rolled wrapper this spec removes.
5. Capture into a shell variable with `$(...)` instead of a temp file (rejected). `$(...)` waits for every holder of stdout to close, so a test that backgrounds a process inheriting stdout would hang negctl. A redirect to a file never waits.

### Interfaces (I/O contract)

- New flag: `--expect-red <list>`, accepted in the leading flag loop beside `--at`/`--path`/`--setup`, so it works in all three modes. `<list>` is comma-separated. Each entry is trimmed of surrounding spaces. An empty value, or a list with an empty entry after trimming, exits 64 with a usage line.
- Match rule: an expected entry `E` matches an observed label `L` when `L = E`, or `L` starts with `E` followed by a space or a colon. Set comparison: every entry must match at least one label (else "missing"), and every label must be matched by at least one entry (else "unexpected").
- Label parse: after stripping ANSI SGR sequences (`ESC[...m`) and a trailing CR, a line is a failure line when it matches `^[[:space:]]*(FAIL:?|FAILED|--- FAIL:|not ok( <n>)?( -)?|✗|✘|×)[[:space:]]+(.+)$` (`not ok` case-insensitive). The label is the last group. Duplicates keep the first occurrence.
- New output lines, both after the red `Exit:` line:
  - `Red: <label>, <label>` or `Red: <none parsed>`. At most 20 labels print, each cut to 100 chars with `...`; a longer set appends ` (+N more)`.
  - With `--expect-red` only: `Expect red: <list as given>`.
- Verdict on a mismatch: `Verdict: FAIL: red set differs from --expect-red: missing <e1, e2>; unexpected <l1, l2>`. Only the non-empty half prints.
- Invariants: `Command:`, every `Exit:` line, `Verdict:`, `Mutation:`, `Changed:`, `Restore:`, `Side effect:`, `Base ref:`, `At:`, `Export:`, `Setup:` keep their exact bytes and order. The red log is created with `mktemp` outside `<root>` and removed right after parsing, so the step-2/step-6 snapshot comparison never sees it. No new `trap` line: the test suite splices `restore() {` .. `trap restore EXIT` by line anchor.

## Failure modes

| Failure class | Detection signal | Mitigation |
|---|---|---|
| Suite prints failures in a shape the regex does not know | `Red: <none parsed>` on a red run | The line says so plainly; `--expect-red` then FAILs as "missing", never a silent PASS |
| A summary line looks like a failure (`FAIL: 3 of 40 failed`) | A count appears as a label | Named in the docs; `--expect-red` reports it as "unexpected", which is fail-closed |
| Label carries a huge interpolated payload (`out=$OUT`) | A multi-kilobyte line | Only that one line is the label; display cuts it to 100 chars; comparison uses the full text |
| Red log left behind after an interrupt mid-run | A stray `tmp.*` file in `$TMPDIR` | Outside `<root>`, so the tree snapshot is unaffected; accepted residue, same class as `--at` exports |
| An edit shifts a line the suite anchors a mutation on | Cases [25]-[32] resolve `ln` to the wrong line | Implementation adds no line containing `  if [ "${#beyond[@]}" -gt 0 ]; then`, `    if [ "${#baseline_diff[@]}" ...`, `  restore_done=1`, or `  trap '' INT TERM HUP` before their current first occurrence |
| A label contains a comma | `--expect-red` cannot name it whole | Prefix rule lets the entry stop before the comma; documented |

## Grounding

Sampled read-only on 2026-09-29 in this worktree at `917a2754`.

| Claim | Command | Excerpt |
|---|---|---|
| Today the red run's output is discarded and the block carries one exit code | `bash lib/gate/negctl.sh --at HEAD "$PWD" "bash tests/test-proof-visual-evidence.sh" "sed -i.bak 's/^_has_committed_image() {\$/_has_committed_image() { return 0/' lib/gate/proof-ledger.sh && rm -f lib/gate/proof-ledger.sh.bak"` | `Exit: 1 (under mutation, RED expected)` / `Restore: git checkout HEAD -- lib/gate/proof-ledger.sh` / `Exit: 0 (green after restore)` / `Verdict: PASS`; no case is named |
| The same mutation reddens two cases, one of them unrelated to "dangling image" | the same mutation applied by hand in that export, `bash tests/test-proof-visual-evidence.sh` | `FAIL dangling image should BLOCK but ACCEPTED`, `FAIL no evidence should BLOCK but ACCEPTED`, `2 FAILED`, rc=1. A worker proving the dangling-image fix gets `PASS` for a control that also broke the no-evidence case |
| Kit suites print failures as `FAIL <label>`, `  FAIL: <label>`, or ANSI-coloured `FAIL` | `grep -hE '^\s*(fail\|no\|bad)\s*\(\)' tests/*.sh \| sort \| uniq -c` | `12 fail() { echo "FAIL $*"; ...}`, `11 no() { ...; echo "NOT ok - $1"; }`, `10 bad() { ...; echo -e " ${RED}FAIL${NC} $1"; }`, `5 no(){ echo "  FAIL: $*" >&2; ...}` |
| The parse regex extracts those shapes and skips summaries | the regex run over sample lines with BSD sed, `LC_ALL=C` | in: `FAIL add-2-2`, `  FAIL: add-0-0`, `ESC[0;31mFAILESC[0m add-neg`, `not ok 4 - add-tap`, `NOT ok - add-cap`, `✗ add-check`, `--- FAIL: TestAdd (0.00s)`, `FAILED tests/test_x.py::test_add - AssertionError`, `FAILS: 3`, `2 FAILED`, `ok: mul`, `test-x: 1 passed, 1 FAILED`, `FAIL crlf\r`; out: the first eight labels plus `crlf`; the four summary/pass lines produce nothing |
| The current default block, byte for byte (the golden the compat test pins) | `negctl.sh <fixture> "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak"` on a two-assertion fixture | `## Negative control (negctl)`, `Command: bash test.sh`, `Exit: 0 (green before mutation)`, `Mutation: sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak`, `Changed: lib.sh`, `Exit: 1 (under mutation, RED expected)`, `Restore: git checkout HEAD -- lib.sh`, `Exit: 0 (green after restore)`, `Verdict: PASS`; rc=0 |
| The gate reads only `Command:`/`Exit:`/`Verdict:`/`NEGATIVE CONTROL`, the last `Verdict:` anchored at line start | `grep -n 'Verdict\|Exit:\|NEGATIVE' lib/gate/proof-ledger.sh` | line 313 `last_v="$(grep -iE '^[[:space:]]*Verdict:' "$p" \| tail -1)"`; line 315 `grep -qE 'Exit:[[:space:]]*0\|VERDICT: PASS\|Verdict: PASS\|PASS'`. A line starting `Red:` or `Expect red:` cannot become the last `Verdict:` |
| The suite anchors mutations on literal lines of negctl.sh | `grep -nE 'grep -Fn' tests/test-proof-negctl.sh` | lines 249, 288, 305, 343, 396 resolve `ln` from `head -1` of a fixed-string match; lines 47-48 anchor `^restore() {$` and `^trap restore EXIT$` |
| Baseline: FEATURES registry is fresh | `bash lib/registry/feature-registry.sh check docs/FEATURES.md` | rc=0 |

Not sampled: a JS runner's `✗`/`×` output and Go's `--- FAIL:` from a real run. No such suite exists in this repo. The regex covers the shapes from their documented output; a miss shows as `Red: <none parsed>`, never a false PASS under `--expect-red`.

### Negative control dry traces

The new cases print `no "[NN] ..."`, so the label of a failing new case starts with its case number and `--expect-red "[NN]"` can name it.

NC1, the parser.
- Mutation: `sed -i.bak 's/^_red_labels() {$/_red_labels() { return 0/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak`.
- Fixture reads: `mkrepo` gains `test-labels.sh`, which sources `lib.sh` and, when `add` is broken, prints `FAIL add-2-2 got 0` (stdout), `  FAIL: add-0-0` (stderr), `ESC[31mFAILESC[0m add-neg`, `not ok 4 - add-tap`, `✗ add-check`, and `ok: mul`, then exits 1.
- Code path: inner negctl step 4 writes that output to the red log, `_red_labels` returns nothing, so the inner block prints `Red: <none parsed>`.
- Red: [38] (asserts `Red:` lists all five labels), [39] (expects PASS, gets FAIL "missing"), [40] (its first run expects PASS), [41] (asserts `unexpected add-check`; the verdict says only `missing`), [43] (asserts `(+5 more)`), [44] (asserts the exact line `Red: add-2-2, add-0-0`), [45] (asserts `Red:` labels in base-ref and `--at` mode). Green: [42] (asserts `missing .*mul-2-3`, still true), [46] (usage exit 64), [47] (static block, gate grammar only), and every case [1]-[37], none of which reads `Red:`.
- Run: `bash lib/gate/negctl.sh --expect-red "[38],[39],[40],[41],[43],[44],[45]" --at <build-sha> "$PWD" "bash tests/test-proof-negctl.sh" "<mutation>"`. The `--at` export keeps the outer negctl out of the file it mutates. The final case list is fixed at build time and recorded in the proof, and this trace is updated if it moves.

NC2, the comparison.
- Mutation: `sed -i.bak 's/^_expect_red_check() {$/_expect_red_check() { return 0/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak`.
- Code path: the parse still runs and `Red:` still prints; the mismatch never calls `fail`.
- Red: [40] (its second run expects FAIL `missing add-2`), [41], [42], and [45] (its mismatching list expects FAIL), each getting PASS. Green: [38], [39], [43] (its full-set run expects PASS), [44], [46], [47].
- Run: the same `--at` form with `--expect-red "[40],[41],[42],[45]"`.

## Test plan

New cases in `tests/test-proof-negctl.sh`, numbered after [37]. Each prints `no "[NN] ..."` on failure.

| Case | Kind | Input | Expect |
|---|---|---|---|
| [38] | happy | real mutation, `test-labels.sh` | PASS; `Red:` line lists `add-2-2 got 0, add-0-0, add-neg, add-tap, add-check` in that order; stderr lines included |
| [39] | happy | `--expect-red "add-2-2,add-0-0,add-neg,add-tap,add-check"` | PASS; `Expect red:` line present |
| [40] | boundary | label `add-2-2 got 0`: entry `add-2-2` matches it (space boundary); entry `add-2` must not (next char `-`) | first run PASS; second FAIL naming `missing add-2` and `unexpected add-2-2 got 0` |
| [41] | negative | `--expect-red` omits `add-check` | FAIL `red set differs ... unexpected add-check`; exit 1; tree clean |
| [42] | negative | `--expect-red` adds `mul-2-3` | FAIL `... missing mul-2-3`; exit 1; tree clean |
| [43] | bound | fixture prints 25 distinct FAIL lines, one 300-char label | `Red:` shows 20 labels, `(+5 more)`, the long label cut to 100 chars with `...`; `--expect-red` over all 25 still PASSes (comparison uses the full set) |
| [44] | compat | the Grounding golden fixture, no flag | stdout with the `Red:` line removed equals the golden byte for byte; the line directly after the red `Exit:` line is exactly `Red: add-2-2, add-0-0` |
| [45] | modes | `--base-ref` with `--expect-red`; `--at HEAD` with no flag | base-ref: `Red:` directly after its `Exit:` line, matching list PASS, mismatching list FAIL; `--at`: `Red:` lists the labels, live tree untouched |
| [46] | usage | `--expect-red ""`, `--expect-red "a,,b"`, `--expect-red` with no value | exit 64, usage on stderr, nothing run |
| [47] | integration | a static PASS block with `Red:` + `Expect red:` lines (text pinned in the test) in a proof file | `proof-ledger.sh check` accepts it; the same file ending on the mismatch `Verdict: FAIL: red set differs ...` is refused |

The existing cases [1]-[37] stay green unchanged.

## Acceptance Criteria (global)

- AC1: every negctl run that reaches the red step prints exactly one `Red:` line directly after the red `Exit:` line, in mutate, `--at`, and `--base-ref` modes.
- AC2: `--expect-red` FAILs the verdict on any missing or unexpected label under the stated match rule, and PASSes on an equal set. A vacuous mutation still reports the vacuous reason first.
- AC3: with no `--expect-red`, the block equals the pre-change block plus the `Red:` line (case [44]). `proof-ledger.sh check` accepts it (case [47]).
- AC4: no temp file lands inside `<root>`; the tree is clean after every new case.
- AC5: the header comment in `negctl.sh`, the usage lines in `proof-ledger.sh`, and `docs/verification/README.md` item 2 describe `Red:` and `--expect-red`.
- AC6: the Verification command passes, and both negative controls go red with exactly the case sets their traces name.

## Verification

```
bash tests/test-proof-negctl.sh &&
bash tests/test-proof-visual-evidence.sh &&
bash tests/test-hooks.sh &&
bash tests/test-meta.sh &&
bash lib/registry/feature-registry.sh check docs/FEATURES.md
```

Then the two negative controls from `## Grounding`, recorded in `docs/verification/negctl-red-set.md`.

## Edge Cases

1. The red run prints no parseable line: `Red: <none parsed>`; with `--expect-red`, FAIL "missing <all>".
2. The mutation is vacuous (test stays green): `Red:` still prints what it parsed (usually `<none parsed>`); the verdict reason stays "test stayed green", because `fail()` keeps the first reason.
3. `NEGCTL_RED_ATTEMPTS=3`: each attempt overwrites the log; labels come from the last attempt, the one that went red or the last green one.
4. A green retry attempt that leaves tracked dirt: the existing FAIL fires first and stops retries; `Red:` parses the last attempt's log.
5. The same label printed twice (stdout and stderr): listed once.
6. A label with a trailing CR (Windows line ends): CR stripped.
7. An `--expect-red` entry with surrounding spaces (`"a, b"`): trimmed.
8. Test output with invalid UTF-8: parsed under `LC_ALL=C`, so sed never aborts on a byte sequence.
9. `--expect-red` combined with `--at` and `--path`: flag loop order is free among the leading flags.
10. A `Red:` label that itself contains `Verdict: PASS`: the gate's `Verdict:` match is anchored at line start, and the line starts with `Red:`.

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

## Tasks

- [ ] T1: `lib/gate/negctl.sh`: `--expect-red` in the flag loop with usage checks; `_red_labels` and `_expect_red_check`; red-run capture in mutate and base-ref modes; `Red:` and `Expect red:` lines; header comment. Keep every anchor line the suite resolves.
- [ ] T2: `tests/test-proof-negctl.sh`: `test-labels.sh` in `mkrepo`, cases [38]-[47], header comment.
- [ ] T3: `lib/gate/proof-ledger.sh` usage comment and `docs/verification/README.md` item 2.
- [ ] T4: run Verification, both negative controls, write `docs/verification/negctl-red-set.md`; regenerate `docs/FEATURES.md` only if its check turns red.

## Decision Log
- DEC-A: match rule is "equal, or prefix followed by a space or colon". Exact match cannot name a label with interpolated detail; a bare prefix lets `T1` match `T10`.
- DEC-B: the red log is a temp file, never a `$(...)` capture, so a test that leaves a background process holding stdout cannot hang negctl.
- DEC-C: `Red:` always prints on the red step, flag or no flag. The lead asked for the labels in every proof; one additive line keeps every existing line byte-identical.
- DEC-D: the display cut (20 labels, 100 chars) never touches the comparison, which uses the full parsed set.
- DEC-E: the new code adds no `trap` line; the log is removed right after parsing. The suite splices `restore()` by line anchor, and a changed trap line would break that splice.
