# Spec: negctl records which cases went red, and can assert the red set

Generated: 2026-09-29
Status: DRAFT (rounds 1-3 NEEDS REVISION folded; awaiting operator decision on a further round)
Lane: full (lane-classify: the change edits `lib/gate/`, the proof-of-done enforcement surface)
Type: spec-feature
File: `docs/specs/SPEC-364-negctl-red-set.md`
References: `lib/gate/negctl.sh` (the tool this extends; its `NEGCTL_RED_ATTEMPTS` knob and `--at` flag loop are the shape to imitate for a new option, and its `--at` export's `mktemp "${tmp_base%/}/negctl-at.XXXXXX"` is the temp-file form to copy), `lib/gate/proof-ledger.sh` `check()` lines 295-360 (the parser whose grammar must not move), `hooks/codex-hook-adapter.sh` line 79 (the redaction patterns to start from; this spec widens and left-bounds the token pattern, DEC-P), `tests/test-proof-negctl.sh` (the suite this extends, and its line-anchored mutations that must keep resolving)

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

Every existing line keeps its bytes. With no `--expect-red`, the only new output is the `Red:` line. A red log that cannot be created or written stops negctl with exit 1 before it can read a capture failure as RED. Labels are redacted for credential shapes before they print, because a proof block gets committed. `--expect-red` entries pass through the same redaction, so entry and label compare in one form.

## Design

Design-bearing: a new CLI flag on a proof tool, a new line in a parsed block, a new fail-closed path, and two viable matching rules. Approaches below; the picture follows.

### Picture

```
negctl.sh [--expect-red L1,L2] [--at sha ...] root test-cmd mutate-cmd
   |
   | globals: red_labels=() red_log="" red_mismatch="" capped=""
   | helpers defined first (before the base-ref block):
   |   _redact  _red_labels  _expect_red_check  _cap_list  _capture_failed
   | run_test gains an optional sink, edited in place on its current line (one line to one line):
   |   run_test() { (cd "$root" && bash -c "$test_cmd") >"${1-/dev/null}" 2>&1; }
   |   no colon in ${1-...}: an empty $1 stays empty, so `run_test ""` fails its redirect (rc 1)
   | --expect-red parsed + validated in the flag loop (empty / control char -> exit 64),
   |   then each entry runs through _redact (same form as the labels)
   | REFUSED (dirty tree) / --at export failures exit as today
   | trap restore EXIT                                            (unchanged line)
   | red_log = mktemp "${TMPDIR:-/tmp}/negctl-red.XXXXXX"
   |           || _capture_failed pre   -> stderr message, exit 1 (no header, nothing mutated)
   | echo "## Negative control (negctl)"                          (unchanged)
   |
   | step 2  run_test ----------------------------------> /dev/null   (unchanged)
   | step 3  mutate
   | step 4  per attempt:
   |           : >"$red_log"          || _capture_failed post   (write probe)
   |           run_test "$red_log"; rc_red=$?                    (sink truncates: fresh log; rc read at once,
   |                                                              before the append probe)
   |           printf '\n' >>"$red_log" || _capture_failed post (ENOSPC probe; ends a bare last line)
   |         _capture_failed post -> "Verdict: FAIL: red-log capture failed", exit 1; EXIT trap restores
   |         after the loop:
   |           Exit: <rc> (under mutation, RED expected)          (unchanged bytes)
   |           _red_labels red_log  -> red_labels[]   (prints nothing; redacts)
   |           printf 'Red: %s\n' "$capped"
   |           printf 'Expect red: %s\n' ...                     (flag only)
   |           _expect_red_check    -> red_mismatch   (prints nothing; reason held, not yet failed)
   |           vacuous check (rc_red = 0) -> fail "test stayed green ..."   (unchanged, first)
   | step 5  restore()   last body line: [ -z "$red_log" ] || rm -f "$red_log"
   | step 6  run_test ----------------------------------> /dev/null   (unchanged)
   |         restore/tree/green-after failures -> fail(...)         (unchanged)
   |         red_mismatch set -> fail "red set differs ..."          (LAST, just before Verdict)
   v
 Verdict: PASS | FAIL: <first reason>

 --base-ref: after `trap cleanup EXIT` and the extract failure exit, before its header: same
 mktemp + _capture_failed pre; one run with the same probe pair (its own inline `>"$red_log" 2>&1`,
 no run_test there); cleanup() last body line removes
 the log; Red:/Expect red: after its Exit: line; own verdict: "passed at <ref>" first, then the
 red-set mismatch.
```

### Approaches considered

1. Parse FAIL lines from the red run, print `Red:`, optional boundary-prefix `--expect-red` (chosen). One executable file changes. Callers and the gate see one extra line.
2. Exact string equality for `--expect-red` (rejected). Kit suites put interpolated detail after the label (`no "rc=$RC out=$OUT"`, `--- FAIL: TestX (0.00s)`), so an exact label changes every run and the operator cannot write it in advance.
3. Plain prefix match (rejected). `T1` would match `T10`, so a wrong case going red would pass.
4. A sibling script or a per-suite label adapter (rejected). The lead's precedent rule is to extend negctl. An adapter per suite is the hand-rolled wrapper this spec removes.
5. Capture into a shell variable with `$(...)` instead of a temp file (rejected). `$(...)` waits for every holder of stdout to close, so a test that backgrounds a process inheriting stdout would hang negctl. A redirect to a file never waits.
6. `mktemp -t negctl-red.XXXXXX` for the log (rejected, see Grounding). On macOS it ignores `TMPDIR`, so the unwritable-TMPDIR case cannot be exercised there. The explicit-template form already used by `--at` honors `TMPDIR` on both platforms.
7. Relocate the log to `/tmp` when `TMPDIR` sits inside `<root>` (rejected by the lead in round 2). That configuration already fails closed: the log is in the step-2 snapshot, `restore()` removes it before step 6, the snapshots differ, and negctl FAILs `tree differs`. A fallback adds path resolution for a case that is already safe.

### Interfaces (I/O contract)

- New flag: `--expect-red <list>`, accepted in the leading flag loop beside `--at`/`--path`/`--setup`, in any order among them, so it works in all three modes. `<list>` is comma-separated; each entry is trimmed of surrounding spaces. Exit 64 with a usage line when: the value is missing or empty, an entry is empty after trimming, or an entry contains a control character (checked under `LC_ALL=C` with `[[:cntrl:]]`). After validation each entry passes through `_redact` (label step 5), so `--expect-red "sk-abc12345678"` compares as `sk-[redacted]` and `Expect red:` prints the redacted form.
- Match rule (fixed strings only): entry `E` matches label `L` when `[ "$L" = "$E" ]`, or `L` starts with the literal `E` followed by one `[[:space:]]` or `:` character (`case "$L" in "$E"[[:space:]]*|"$E":*)`, `$E` quoted so `[38]` is never a glob). Every entry must match at least one label (else "missing"); every label must be matched by at least one entry (else "unexpected").
- Label parse, one linear pass, `LC_ALL=C sed -nE '...' "$log" | awk '!seen[$0]++'`. `LC_ALL=C` scopes to that sed and to the entry control-character check only. Steps, in order:
  1. strip ANSI SGR sequences (`ESC[...m`) and a trailing CR;
  2. drop Go's package summary line, `^FAIL\t[^\t ]+( \[[^]]*\]|\t([0-9.]+s|\(cached\)|\[[^]]*\]))$`, and TAP directive lines, `not ok` with a `# TODO` or `# SKIP` directive; case-insensitivity uses bracket classes (`[Nn][Oo][Tt] [Oo][Kk]`, `[Tt][Oo][Dd][Oo]`, `[Ss][Kk][Ii][Pp]`), never sed's `I` flag, which BSD sed lacks;
  3. a line is a failure line when it matches `^[[:space:]]*(FAIL:?|FAILED|--- FAIL:|[Nn][Oo][Tt] [Oo][Kk]( [0-9]+)?( -)?|✗|✘|✕|✖|×)[[:space:]]+([^[:space:]].*)$`; the label is the last group, so it starts with a non-space;
  4. in the label, strip every C0 byte and DEL, C1 controls (`\xc2[\x80-\x9f]`), the line and paragraph separators plus bidi overrides (U+2028-202E as `\xe2\x80[\xa8-\xae]`, U+2066-2069 as `\xe2\x81[\xa6-\xa9]`);
  5. redact with `_redact` (`sed -E`, stdin to stdout, shared with the `--expect-red` entries): `(^|[^A-Za-z0-9])(gh[pousr]_|github_pat_|sk-|xox[a-z]-)[A-Za-z0-9_-]{8,}` becomes `\1\2[redacted]`, `AKIA[A-Z0-9]{16}` becomes `AKIA[redacted]`, `[A-Fa-f0-9]{32,}` becomes `[redacted]`. This is a deliberate deviation from copying line 79: the copied `sk-` has no left boundary, so `task-queue-drains` and `task-runner-works` both became `task-[redacted]` and dedup merged two distinct labels. The boundary keeps `task-...` intact and still redacts `(sk-...)`, `=sk-...`, and a token at line start. A token glued to a letter (`FOOsk-...`) is not redacted; named residual risk. The hex pattern stays unbounded on purpose: a left boundary would stop it redacting a hex run glued to a letter, the leaking direction. Cost accepted: a 40-hex git SHA in a label redacts, and two labels differing only in a 32+ hex run merge.
  Dedup keeps the first occurrence and the order. The comparison and the display both use the redacted label.
- Helpers. `_red_labels <log>` fills the global array `red_labels` and returns 0. `_expect_red_check` fills the global `red_mismatch` with the reason (empty on a match) and returns 1 on a mismatch. `_cap_list` formats a list into the global `capped`. `_redact` is a stdin-to-stdout filter. These four print nothing; the caller prints every line, labels only as `%s` arguments (`printf 'Red: %s\n' "$capped"`). `_capture_failed <pre|post>` is the one helper that prints: `negctl: red-log capture failed` on stderr, plus `Verdict: FAIL: red-log capture failed` on stdout when called `post` (after the header), then `exit 1`. Header lines are pinned as `^_red_labels() {$`, `^_expect_red_check() {$`, `^_capture_failed() {$` (the negative controls mutate them).
- `_cap_list`: at most 20 items, each cut to 100 characters with `...` (the cut runs under the ambient locale, so a UTF-8 locale never splits a multibyte character; under an ambient C locale the cut is bytewise and can split one, which prints a replacement glyph in the display only, never in the comparison. Accepted, not handled); a longer list appends ` (+N more)`.
- `run_test`: `run_test() { (cd "$root" && bash -c "$test_cmd") >"${1-/dev/null}" 2>&1; }`, edited in place on its current line. Steps 2 and 6 call it with no argument (sink `/dev/null`, unchanged). Step 4 calls `run_test "$red_log"` and reads `rc_red=$?` directly after it, before the append probe, so the probe cannot overwrite the test's status. The form is `${1-...}`, not `${1:-...}`: with the colon an empty `$1` falls back to `/dev/null`, the test would run, and the fail-closed guard (NC3) would stop biting.
- Base-ref mode has no `fail()` or verdict at the point of its run, so T1 hand-writes its ranking and the same probe pair inline. `Side effect:` lines printed after `_capture_failed post`'s Verdict are cosmetic (the run has already ended, exit 1).
- New output lines, after the red `Exit:` line, in this order:
  - `Red: <label>, <label>` or `Red: <none parsed>`.
  - With `--expect-red` only: `Expect red: <entries, trimmed, comma-space joined>`.
- Verdict on a mismatch: `Verdict: FAIL: red set differs from --expect-red: missing <list>; unexpected <list>`, each list through `_cap_list`, only the non-empty half printed.
- Verdict precedence (mutate mode): every existing reason ranks first, the mismatch last. `fail()` keeps the first reason, and the mismatch `fail` call sits directly before `echo "Verdict: $verdict"`. Base-ref mode: "the check passed at <ref>" first, then the mismatch.
- Log lifecycle: created after `trap restore EXIT` (base-ref: after `trap cleanup EXIT`) and after the REFUSED, `--at` export, and extract failure exits, before the `## Negative control` header. Removed by `[ -z "$red_log" ] || rm -f "$red_log"` as the last body line of `restore()` and of `cleanup()`. No new `trap` line: the suite splices `restore() {` .. `trap restore EXIT` by line anchor.
- Comments: the header comment of `negctl.sh` names `Red:`, `--expect-red`, the redaction, and the read-before-commit caution, and says new runner output shapes go in `_red_labels`, pinned by [38]'s fixture. A comment above `_redact` cross-references `hooks/codex-hook-adapter.sh` line 79 and states that the pattern here is a deliberate widened copy.
- Invariants: `Command:`, every `Exit:` line, `Verdict:`, `Mutation:`, `Changed:`, `Baseline side write:`, `Restore:`, `Side effect:`, `Delta:`, `Base ref:`, `At:`, `Export:`, `Setup:` keep their exact bytes and order. The script stays bash 3.2 safe: every array expansion that can be empty sits behind a `${#arr[@]} -gt 0` guard.

## Failure modes

| Failure class | Detection signal | Mitigation |
|---|---|---|
| The red log cannot be created (`TMPDIR` missing or read-only) | `mktemp` fails | `_capture_failed pre`: stderr message, exit 1, no header, nothing mutated. Without it, `run_test ""` (empty sink) fails its redirect with rc 1 without running the test, and a vacuous mutation reads as RED and PASSes |
| The red log stops being writable between attempts | `: >"$red_log"` fails | `_capture_failed post`: `Verdict: FAIL: red-log capture failed`, exit 1, the EXIT trap restores (case [51]) |
| Disk full (ENOSPC) while the test writes the log | `printf '\n' >>"$red_log"` fails after the attempt | `_capture_failed post`, same as above. The same append also terminates a final label with no newline. Residual risk: a test that hits ENOSPC, then frees space so the probe succeeds, goes undetected and its truncated output parses as is |
| `TMPDIR` points inside `<root>` | The log is in the step-2 snapshot and `restore()` removes it before step 6, so the snapshots differ | The existing snapshot check FAILs `tree differs`; point `TMPDIR` elsewhere. For a gitignored in-root `TMPDIR` the log is in neither snapshot and nothing fires (harmless). No relocation code |
| Labels copy test output into a proof file that gets committed. No kit hook scans commit content for secrets: `hooks/secrets-guard.sh` blocks reads only | A label carries a token, a key, or a long hex string | `_red_labels` redacts `gh[pousr]_`, `github_pat_`, `sk-`, `xox?-` (left-bounded), `AKIA` and 32+ hex shapes to `[redacted]` (line 79 of `hooks/codex-hook-adapter.sh`, widened and bounded, DEC-P); 20-label and 100-char caps bound the rest; control, C1, U+2028/2029, and bidi bytes are stripped; the header comment and `docs/verification/README.md` tell the operator to read the block before committing it. Other secret shapes are not redacted and are named as residual risk |
| Suite prints failures in a shape the regex does not know | `Red: <none parsed>` on a red run | The line says so plainly; `--expect-red` then FAILs as "missing", never a silent PASS |
| A summary line looks like a failure (`FAIL: 3 of 40 failed`) | A count appears as a label | Named in the docs; `--expect-red` reports it as "unexpected", which is fail-closed |
| Label carries a huge interpolated payload (`out=$OUT`) | A multi-kilobyte line | Only that one line is the label; `_cap_list` cuts it to 100 chars in `Red:` and in the Verdict; comparison uses the full text |
| Two distinct labels redact to the same text (`task-queue-drains`, `task-runner-works` under an unbounded `sk-`) | Dedup merges them; `--expect-red` cannot tell them apart | The `sk-` alternation takes a left boundary; [38]'s fixture holds both labels and asserts both print unredacted and separate |
| A stale label from an earlier green retry attempt | Label from attempt 1 shows under attempt 2 | Each attempt's `run_test "$red_log"` sink truncates the log; only the last attempt's output is parsed (case [50]) |
| Red log left behind after an interrupt mid-run | A stray `negctl-red.*` file in `$TMPDIR` | `restore()` removes it on every EXIT-trap path; residue only on SIGKILL, or in case [22], whose naive splice replaces `restore()` (the suite points `TMPDIR` at its own temp dir, removed on exit) |
| An edit shifts a line the suite anchors a mutation on | Cases [20], [24], [26], [30], [32] resolve `ln` to the wrong line; case [22]'s splice misses its anchors | New code adds no line containing `  if [ "${#beyond[@]}" -gt 0 ]; then`, `    if [ "${#baseline_diff[@]}" ...`, `  restore_done=1`, or `  trap '' INT TERM HUP` before their current first occurrence; `^restore() {$` and `^trap restore EXIT$` stay single and unchanged; helpers use other variable names; the `run_test` edit replaces line 189 in place, one line to one line |
| A label contains a comma | `--expect-red` cannot name it whole | The boundary rule lets the entry stop before the comma; documented |

## Grounding

Sampled read-only on 2026-09-29 in this worktree, base `917a2754` unless a row says otherwise.

| Claim | Command | Excerpt |
|---|---|---|
| Today the red run's output is discarded and the block carries one exit code | `bash lib/gate/negctl.sh --at HEAD "$PWD" "bash tests/test-proof-visual-evidence.sh" "sed -i.bak 's/^_has_committed_image() {\$/_has_committed_image() { return 0/' lib/gate/proof-ledger.sh && rm -f lib/gate/proof-ledger.sh.bak"` | `Exit: 1 (under mutation, RED expected)` / `Restore: git checkout HEAD -- lib/gate/proof-ledger.sh` / `Exit: 0 (green after restore)` / `Verdict: PASS`; no case is named |
| The same mutation reddens two cases, one of them unrelated to "dangling image" | the same mutation applied by hand in that export, `bash tests/test-proof-visual-evidence.sh` | `FAIL dangling image should BLOCK but ACCEPTED`, `FAIL no evidence should BLOCK but ACCEPTED`, `2 FAILED`, rc=1. A worker proving the dangling-image fix gets `PASS` for a control that also broke the no-evidence case |
| Kit suites print failures as `FAIL <label>`, `  FAIL: <label>`, `NOT ok - <label>`, or ANSI-coloured `FAIL` | `grep -hE '^\s*(fail\|no\|bad)\s*\(\)' tests/*.sh \| sort \| uniq -c` | `12 fail() { echo "FAIL $*"; ...}`, `11 no() { ...; echo "NOT ok - $1"; }`, `10 bad() { ...; echo -e " ${RED}FAIL${NC} $1"; }`, `5 no(){ echo "  FAIL: $*" >&2; ...}` |
| The parse regex extracts those shapes and skips summaries | the regex run over sample lines with BSD sed, `LC_ALL=C` | in: `FAIL add-2-2`, `  FAIL: add-0-0`, `ESC[0;31mFAILESC[0m add-neg`, `not ok 4 - add-tap`, `NOT ok - add-cap`, `✗ add-check`, `--- FAIL: TestAdd (0.00s)`, `FAILED tests/test_x.py::test_add - AssertionError`, `FAILS: 3`, `2 FAILED`, `ok: mul`, `test-x: 1 passed, 1 FAILED`, `FAIL crlf\r`; out: the first eight labels plus `crlf`; the four summary/pass lines produce nothing |
| Go summary lines and TAP directives drop with bracket classes; mixed-case `not ok` still parses | `printf 'FAIL\tex.com/pkg\t(cached)\nFAIL\tex.com/pkg [build failed]\nnot ok 5 - x # todo later\nNot OK 6 - y\n' \| LC_ALL=C sed -nE` with the step-2 drops and the step-3 match; plus `printf 'FAIL\tgithub.com/x/pkg\t0.012s\n'` through the drop | only `y` prints; the `0.012s` line prints nothing |
| C1 controls and bidi overrides strip under `LC_ALL=C` byte classes | `printf 'a\xe2\x80\xaeb\xc2\x85c\n' \| LC_ALL=C sed -E $'s/\xe2\x80[\xaa-\xae]//g; s/\xe2\x81[\xa6-\xa9]//g; s/\xc2[\x80-\x9f]//g' \| od -c` | `a b c \n` |
| The adapter's redaction patterns work under BSD sed | `hooks/codex-hook-adapter.sh` line 79, run over `FAIL leak <fake sk- token> and <32 hex digits>` with the fake token assembled from two string halves at runtime | `FAIL leak sk-[redacted] and [redacted]`. Unbounded, the same pattern turns `task-queue-drains` and `task-runner-works` into `task-[redacted]` (round-3 reproduced). A literal token on a command line trips the operator's secret-guard hook, so the [38] fixture builds its fake token from halves too |
| No kit hook scans commit content for secrets | `sed -n 1,12p hooks/secrets-guard.sh` | `# secrets-guard.sh, PreToolUse hook, matcher: Read\|Edit\|Bash` / `# Blocks the agent from READING secret files.` |
| A final line with no newline survives sed + awk | `printf 'FAIL a\nFAIL last' \| LC_ALL=C sed -nE 's/^FAIL (.+)$/\1/p' \| awk '!seen[$0]++' \| od -c` | `a \n l a s t \n` (the per-attempt `printf '\n' >>` makes this moot for the log, and the test pins it anyway) |
| macOS `mktemp -t` ignores `TMPDIR`; the explicit template honors it | `TMPDIR=/nonexistent/x mktemp -t negctl-red.XXXXXX`; `mktemp /nonexistent/x/negctl-red.XXXXXX` | first: `/var/folders/.../T/negctl-red.XXXXXX.VhukmZBlpa`, rc=0 (TMPDIR ignored); second: `mkstemp failed on /nonexistent/x/negctl-red.Q6bG6I: No such file or directory`, rc=1 |
| A capture redirect to an empty path returns non-zero without running the command | reasoning from bash semantics: `bash -c 'true' >""` fails the redirect (`No such file or directory`) and the command never runs | the step-4 `rc_red` would be 1, read as RED. Named by round-1 R2/R3; cases [49], [51] and NC3 prove the guard |
| `run_test` with an optional sink keeps the empty-path guard only without the colon | a scratch script: `f() { (cd "$d" && bash -c "touch ran") >"${1-/dev/null}" 2>&1; }`, then `f ""`, `f`, and the `${1:-...}` twin `h ""` | `f ""`: `No such file or directory`, rc=1, `ran` not created (NC3 holds). `f`: rc=0, test ran. `h ""`: rc=0, test ran to `/dev/null` (the colon form defeats the guard) |
| The bounded, widened redaction leaves `task-...` alone and still redacts real shapes | `printf 'task-queue-drains ghp_abcdefgh12345 sk-abcdefgh1234 x-sk-abcdefgh1234 (sk-abcdefgh1234)\n' \| LC_ALL=C sed -E 's/(^\|[^A-Za-z0-9])(gh[pousr]_\|github_pat_\|sk-\|xox[a-z]-)[A-Za-z0-9_-]{8,}/\1\2[redacted]/g'` | `task-queue-drains ghp_[redacted] sk-[redacted] x-sk-[redacted] (sk-[redacted])` |
| U+2028 and U+2029 strip with the widened class | `printf 'a\xe2\x80\xa8b\xe2\x80\xa9c\xe2\x80\xaed\n' \| LC_ALL=C sed -E $'s/\xe2\x80[\xa8-\xae]//g' \| od -c` | `a b c d \n` |
| The current default block, byte for byte (the golden [44] pins) | `negctl.sh <fixture> "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak"` on a fixture that prints `FAIL add-2-2` when `add` is broken | `## Negative control (negctl)`, `Command: bash test.sh`, `Exit: 0 (green before mutation)`, `Mutation: sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak`, `Changed: lib.sh`, `Exit: 1 (under mutation, RED expected)`, `Restore: git checkout HEAD -- lib.sh`, `Exit: 0 (green after restore)`, `Verdict: PASS`; rc=0. That fixture's second assertion, `add 0 0 = 0`, never fails under `s/+/-/` (0-0 is 0), so no fixture here uses it |
| The gate reads only `Command:`/`Exit:`/`Verdict:`/`NEGATIVE CONTROL`, the last `Verdict:` anchored at line start | `grep -n 'Verdict\|Exit:\|NEGATIVE' lib/gate/proof-ledger.sh` | line 313 `last_v="$(grep -iE '^[[:space:]]*Verdict:' "$p" \| tail -1)"`; line 315 `grep -qE 'Exit:[[:space:]]*0\|VERDICT: PASS\|Verdict: PASS\|PASS'`. A line starting `Red:` or `Expect red:` cannot become the last `Verdict:` |
| The suite anchors mutations on literal lines of negctl.sh | `grep -n 'grep -Fn\|mk_naive_negctl "' tests/test-proof-negctl.sh` | [20] line 249, [24] line 288, [26] line 305, [30] line 343, [32] line 396 resolve `ln` from `head -1` of a fixed-string match; [22] line 268 splices via `mk_naive_negctl`, anchored on `^restore() {$` and `^trap restore EXIT$` (lines 47-48) |
| FEATURES registry: fresh at the base, stale at the spec commit | `bash lib/registry/feature-registry.sh check docs/FEATURES.md` | at `917a2754`: rc=0. At `72417bbb` (this spec committed): rc=1, `docs/FEATURES.md has DRIFTED`, five rows' SPEC-reference counts differ (`/kit:docs`, `/kit:next`, `/kit:spec`, `/kit:start`, `/kit:wrap`); `tests/test-meta.sh` fails `docs/FEATURES.md is fresh`, `Passed: 878 / 879` |

Not sampled: a JS runner's `✗`/`✕`/`✖`/`×` output from a real run. No such suite exists in this repo. The regex covers the shapes from their documented output; a miss shows as `Red: <none parsed>`, never a false PASS under `--expect-red`.

### Negative control dry traces

The new cases print `no "[NN] <one-line reason>"`, so the label of a failing new case starts with its case number and `--expect-red "[NN]"` names it. Each run uses `--at <build-sha>`, so the outer negctl never runs from the file it mutates. The final case lists are fixed at build time and recorded in the proof; these traces are updated if a list moves. Any NC list change during the build needs an entry in `docs/implementation-notes/negctl-red-set.md` giving the reason.

The suite exports `TMPDIR="$TMP/tmpdir"` (created at start) so every red log lands under the suite's own temp dir, removed by its EXIT trap. [49] and [51] override it for their own negctl call.

Fixtures (all in `mkrepo`, all driven by `add()` in `lib.sh`, mutated by `s/+/-/`):
- `test-labels.sh`: when `add 2 2` is not 4, prints `FAIL add-2-2 got 0` (stdout), `  FAIL: add-neg` (stderr), `ESC[31mFAILESC[0m add-ansi`, `not ok 4 - add-tap`, `not ok 5 - add-todo # TODO later`, `✗ add-check`, `✕ add-x`, `FAIL [t7] add-bracket`, `FAIL add-cr` + CR, the benign `FAIL task-queue-drains` and `FAIL task-runner-works` (they must print unredacted and separate), `FAIL leak <fake sk- token>` (token assembled from two halves at runtime, never a literal in the file), `FAIL bidi` + U+202E + `txt`, `failed to connect to host` (noise), `FAIL<TAB>example.com/pkg<TAB>0.01s`, `ok: mul`, and a final `FAIL add-last` with no newline; exits 1. Expected `Red:` is `add-2-2 got 0, add-neg, add-ansi, add-tap, add-check, add-x, [t7] add-bracket, add-cr, task-queue-drains, task-runner-works, leak sk-[redacted], biditxt, add-last`.
- `test-many.sh`: when broken, prints `FAIL many 01` .. `FAIL many 24` and one `FAIL long ` + 300 `x`; exits 1. The space after `many` and `long` lets the entries `many` and `long` match every label under the boundary rule.
- `test-golden.sh`: when broken, prints `FAIL add-2-2`; exits 1 (the [44] golden fixture).
- `test-flaky.sh`: counter file under `$TMP` (the `FLAKY_COUNTER` env pattern), never in the fixture repo, where it would dirty the tree; run 1 (baseline) green; run 2 (attempt 1) prints `FAIL stale-1`, exits 0; run 3 (attempt 2) prints `FAIL flaky-2`, exits 1; run 4+ green.
- `test-chmodlog.sh`: counter file under `$TMP` (the `RETRY_COUNTER` env pattern), never in the fixture repo; always exits 0; on run 2 (red attempt 1) runs `chmod a-w "$TMPDIR"/negctl-red.*`.
- BREPO (base-ref cases): two commits; `test-labels.sh` identical in both; `lib.sh` broken at the base commit only.

NC1, the parser.
- Mutation: `sed -i.bak 's/^_red_labels() {$/_red_labels() { return 0/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak`.
- Code path: step 4 writes the fixture output to the log; `_red_labels` returns before filling `red_labels`, which stays empty; the caller prints `Red: <none parsed>`.
- Red: [38] (exact `Red:` line), [39] (expects PASS, gets FAIL "missing"), [40] (first run expects PASS), [41] (asserts `unexpected add-x`; the verdict says only `missing`), [43] (asserts `(+5 more)` in `Red:`), [44] (asserts the exact line `Red: add-2-2`), [45] (asserts labels in base-ref and `--at` mode), [50] (asserts `Red: flaky-2`). Green: [42] (asserts `missing .*mul-2-3`, still true), [46] (usage exit 64, before any run), [47] (static block), [48] (each outranking reason still wins), [49] and [51] (exit before any parse), and [1]-[37], none of which reads `Red:`.
- Run: `bash lib/gate/negctl.sh --expect-red "[38],[39],[40],[41],[43],[44],[45],[50]" --at <build-sha> "$PWD" "bash tests/test-proof-negctl.sh" "<mutation>"`.

NC2, the comparison.
- Mutation: `sed -i.bak 's/^_expect_red_check() {$/_expect_red_check() { return 0/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak`.
- Code path: parse and `Red:` still work; `red_mismatch` stays empty, so no mismatch `fail` fires.
- Red: [40] (second run expects FAIL `missing add-2`), [41], [42], [43] (its mismatch run expects the capped `unexpected` list), [45] (its mismatching list expects FAIL), each getting PASS. Green: [38], [39], [44], [46], [47], [48], [49], [50], [51].
- Run: the same form with `--expect-red "[40],[41],[42],[43],[45]"`.

NC3, the fail-closed capture.
- Mutation: `sed -i.bak 's/^_capture_failed() {$/_capture_failed() { return 0/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak`.
- Code path under [49] (`TMPDIR` a missing dir): `mktemp` fails, `_capture_failed pre` returns, `red_log` is empty; step 2 goes to /dev/null and is green; step 4's `: >""` fails and `_capture_failed` returns; `run_test ""` keeps the empty sink (`${1-...}`, no colon), fails the redirect without running the test, rc=1, read as RED; the append fails and returns; verdict PASS.
- Code path under [51] (vacuous mutation, `NEGCTL_RED_ATTEMPTS=2`): attempt 1 is green and makes the log read-only; the append probe fails and returns; attempt 2's `: >` fails and returns; its `run_test "$red_log"` redirect fails on the read-only log, rc=1, read as RED; verdict PASS.
- Red: [49], [51] (each asserts exit 1 and no `Verdict: PASS`). Green: every other case, because a writable log never reaches the failure branch.
- Run: the same form with `--expect-red "[49],[51]"`.

## Test plan

New cases in `tests/test-proof-negctl.sh`, numbered after [37]. Each prints `no "[NN] <one-line reason>"` on failure: the `rc`, the `Verdict:` line, and the `Red:` line, never a multi-line `$OUT` dump.

| Case | Kind | Input | Expect |
|---|---|---|---|
| [38] | happy | real mutation, `test-labels.sh` | PASS; exactly one `Red:` line, directly after the red `Exit:` line, equal to the expected `Red:` in the fixture list (covers ANSI, stderr, CR, `✕`, TAP TODO skip, Go summary skip, bracket label, redacted fake `sk-` token, stripped U+202E, final line with no newline, and the benign `task-queue-drains` and `task-runner-works` printing unredacted and separate); the fake token's secret half and `failed to connect` appear nowhere in the output; no `negctl-red.*` remains under the suite's `TMPDIR` |
| [39] | happy | `--expect-red "add-2-2, add-neg,add-ansi , add-tap,add-check,add-x,[t7] add-bracket,add-cr,task-queue-drains,task-runner-works,leak,biditxt,add-last"` (spaced entries), run once under `/bin/bash` when it exists | PASS; `Expect red:` line lists the trimmed entries; the `[t7]`-shaped entry matches as a fixed string |
| [40] | boundary | entry `add-2-2` matches `add-2-2 got 0` (space boundary); entry `add-2` must not (next char `-`); entry `[t7]` matches `[t7] add-bracket`, entry `[t` must not | first run PASS; second FAIL naming `missing add-2` and `unexpected add-2-2 got 0` |
| [41] | negative | `--expect-red` omits `add-x` | FAIL `red set differs ... unexpected add-x`; exit 1; tree clean |
| [42] | negative | `--expect-red` adds `mul-2-3` | FAIL with the Verdict matching `missing .*mul-2-3`; exit 1; tree clean |
| [43] | bound | `test-many.sh`: 25 labels, one of 305 chars | `Red:` shows 20 labels and `(+5 more)`, the long label cut to 100 chars with `...`; `--expect-red "many,long"` PASSes (full set compared); `--expect-red "zzz"` FAILs with `missing zzz` and an `unexpected` list of 20 plus `(+5 more)` |
| [44] | compat | `test-golden.sh`, no flag | stdout with the `Red:` line removed equals the Grounding golden (command name swapped) byte for byte; the line directly after the red `Exit:` line is exactly `Red: add-2-2` |
| [45] | modes | BREPO `--base-ref` with a matching then a mismatching `--expect-red`; `--at HEAD` on REPO with no flag | base-ref: `Red:` directly after its `Exit:` line, matching PASS, mismatching FAIL `red set differs`; `--at`: `Red:` equals the [38] line, live tree untouched; no `negctl-red.*` remains under the suite's `TMPDIR` after either run |
| [46] | usage | `--expect-red ""`, `"a,,b"`, `" , "`, an entry with a TAB, flag with no value | each exits 64, usage on stderr, no `## Negative control` header |
| [47] | integration | a static PASS block with `Red:` + `Expect red:` lines (text pinned in the test) in a proof file | `proof-ledger.sh check` accepts it; the same file ending on `Verdict: FAIL: red set differs ...` is refused |
| [48] | precedence | (a) vacuous mutation (`printf '\n# c\n' >> lib.sh`) with `--expect-red x`; (b) case [8]'s leftover mutation (`sed -i.bak 's/+/-/' lib.sh`, `.bak` left behind) with `--expect-red zzz`, `.bak` removed after; (c) BREPO `--base-ref HEAD` (green at the ref) with `--expect-red zzz` | (a) `Verdict: FAIL: test stayed green under the mutation (the check is vacuous)`; (b) Verdict contains `tree differs`; (c) Verdict contains `the check passed at`; each exit 1, tree clean |
| [49] | fail-closed | `TMPDIR="$TMP/missing-dir"` for the negctl call, real mutation | exit 1; stderr `negctl: red-log capture failed`; no `## Negative control` header; no `Verdict: PASS`; tree clean |
| [50] | retries | `NEGCTL_RED_ATTEMPTS=3`, `test-flaky.sh` | PASS; `Exit: 1 (... attempt 2 of 3)`; `Red: flaky-2` exactly (the stale-1 label from the green attempt is gone) |
| [51] | fail-closed, per attempt | `TMPDIR="$TMP/t51"` (private, created), `NEGCTL_RED_ATTEMPTS=2`, vacuous mutation, `test-chmodlog.sh` | exit 1; `Verdict: FAIL: red-log capture failed`; no `Verdict: PASS`; tree clean. Skipped as ok when `id -u` is 0 (root ignores the mode bits) |

The existing cases [1]-[37] stay green unchanged.

## Acceptance Criteria (global)

- AC1: every negctl run that reaches the red step prints exactly one `Red:` line directly after the red `Exit:` line, in mutate, `--at`, and `--base-ref` modes ([38], [44], [45]).
- AC2: `--expect-red` FAILs the verdict on any missing or unexpected label under the fixed-string boundary rule, and PASSes on an equal set ([39]-[43], [45]). Every existing failure reason outranks the mismatch ([48]).
- AC3: a red log that cannot be created, truncated, or appended to exits 1 with `negctl: red-log capture failed` and never prints `Verdict: PASS` ([49], [51]).
- AC4: with no `--expect-red`, the block equals the pre-change block plus the `Red:` line ([44]). `proof-ledger.sh check` accepts it ([47]).
- AC5: the header comment in `negctl.sh`, the usage lines in `proof-ledger.sh`, and `docs/verification/README.md` item 2 describe `Red:`, `--expect-red`, the redaction, and the read-before-commit caution (Verification greps below).
- AC6: labels are redacted (left-bounded, so `task-queue-drains` survives) and stripped of control, C1, U+2028/2029, and bidi bytes before they print ([38]); no `negctl-red.*` is left under the suite's `TMPDIR` after a normal run ([38], [45]); the tree is clean after every new case.
- AC7: the Verification command passes, and NC1, NC2, and NC3 each go red with exactly the case set their traces name.

## Verification

```
bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md &&
bash tests/test-proof-negctl.sh &&
bash tests/test-proof-visual-evidence.sh &&
grep -q '^# .*--expect-red' lib/gate/negctl.sh &&
grep -q '^# .*Red:' lib/gate/negctl.sh &&
grep -q -- '--expect-red' lib/gate/proof-ledger.sh &&
grep -q -- '--expect-red' docs/verification/README.md &&
grep -q 'Red:' docs/verification/README.md &&
grep -qi 'redact' docs/verification/README.md &&
grep -q '^_red_labels() {$' lib/gate/negctl.sh &&
grep -q '^_expect_red_check() {$' lib/gate/negctl.sh &&
grep -q '^_capture_failed() {$' lib/gate/negctl.sh &&
bash tests/test-hooks.sh &&
bash tests/test-meta.sh &&
bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md &&
bash lib/registry/feature-registry.sh check docs/FEATURES.md
```

Then NC1, NC2, NC3 from `## Grounding`, recorded in `docs/verification/negctl-red-set.md`.

## Edge Cases

1. The red run prints no parseable line: `Red: <none parsed>`; with `--expect-red`, FAIL "missing <all>".
2. The mutation is vacuous (test stays green): `Red:` still prints what it parsed; the verdict reason stays "test stayed green", because it is failed before the mismatch ([48]).
3. `NEGCTL_RED_ATTEMPTS=3`: each attempt's `run_test "$red_log"` sink truncates the log, and `: >"$red_log"` before it is the write probe; labels come from the last attempt run ([50]).
4. A green retry attempt that leaves tracked dirt: the existing FAIL fires first and stops retries; `Red:` parses that last attempt's log.
5. The same label printed twice (stdout and stderr): listed once.
6. A label with a trailing CR, a tab, other C0 bytes, a C1 control, or a bidi override: all stripped ([38]).
7. An `--expect-red` entry with surrounding spaces: trimmed ([39]). An entry with a control character: exit 64 ([46]).
8. Test output with invalid UTF-8: parsed under `LC_ALL=C`, so sed never aborts on a byte sequence.
9. `--expect-red` combined with `--at` and `--path`: flag order is free among the leading flags.
10. A `Red:` label that itself contains `Verdict: PASS`: the gate's `Verdict:` match is anchored at line start, and the line starts with `Red:`.
11. `TMPDIR` unset: the template falls back to `/tmp`, same as `--at`.
12. A restore or tree-snapshot failure together with a mismatch: the restore/tree reason wins ([48] b).
13. A label that is only a secret (`FAIL sk-...`): prints as `sk-[redacted]`; an `--expect-red` entry is redacted the same way, so naming the raw token or the redacted form both match.
14. A non-failure line that contains "failed" (`failed to connect ...`): not a failure line; absent from `Red:` ([38]).

## Out of Scope

- Naming a case from a section header when the FAIL line holds only detail (the kit's own `echo "[N] ..."` + `no "rc=..."` shape). New cases here put the case id in the FAIL line; old suites are not rewritten.
- Labels from the green runs (steps 2 and 6).
- A structured (JSON) proof block.
- Any change to `proof-ledger.sh check()`.
- Secret shapes beyond the adapter's five patterns.
- Relocating a log whose `TMPDIR` sits inside `<root>` (the snapshot check already fails closed).

## Touches
- lib/gate/**
- tests/**
- docs/verification/**
- docs/implementation-notes/**
- docs/specs/**
- docs/FEATURES.md

## Tasks

- [ ] T1: `lib/gate/negctl.sh`: globals (`red_labels=()`, `red_log=""`, `red_mismatch=""`, `capped=""`) at the top; helpers (`_red_labels`, `_expect_red_check`, `_cap_list`, `_capture_failed`) defined before the base-ref block; `--expect-red` in the flag loop with the usage checks; log creation after the trap and exits, before each header; per-attempt `: >` and `printf '\n' >>` probes; `Red:` / `Expect red:` lines; mismatch `fail` just before `Verdict:` (base-ref: after "passed at"); log removal as the last body line of `restore()` and `cleanup()`; header comment. `run_test` takes the optional sink in place (`${1-/dev/null}`); step 4 calls `run_test "$red_log"; rc_red=$?`. Base-ref mode has no `fail()`, so hand-write its ranking. Keep every anchor line the suite resolves.
  Done when: [38] and [44] are green.
  Depends on: nothing.
- [ ] T2: `tests/test-proof-negctl.sh`: suite-level `TMPDIR`; fixtures `test-labels.sh`, `test-many.sh`, `test-golden.sh`, `test-flaky.sh`, `test-chmodlog.sh` in `mkrepo`; a BREPO for base-ref; cases [38]-[51]; header comment.
  Done when: [1]-[51] are green.
  Depends on: T1 (the cases exercise its interface).
- [ ] T3: `lib/gate/proof-ledger.sh` usage comment and `docs/verification/README.md` item 2 (`Red:`, `--expect-red`, the redaction, the read-before-commit caution).
  Depends on: T1.
- [ ] T4: `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md` first; run Verification; run NC1, NC2, NC3 and write `docs/verification/negctl-red-set.md`; then `check --fix` again, last, and re-run its `check`.
  Depends on: T1, T2, T3.

## Decision Log
- DEC-A: match rule is "equal, or the literal entry followed by one space-class or colon character". Exact match cannot name a label with interpolated detail; a bare prefix lets `T1` match `T10`.
- DEC-B: the red log is a temp file, never a `$(...)` capture, so a test that leaves a background process holding stdout cannot hang negctl.
- DEC-C: `Red:` always prints on the red step, flag or no flag. The lead asked for the labels in every proof; one additive line keeps every existing line byte-identical.
- DEC-D: `_cap_list` bounds display in `Red:` and in the Verdict's missing/unexpected lists; the comparison always uses the full parsed set.
- DEC-E: the new code adds no `trap` line; log removal is the last body line of `restore()` and `cleanup()`. The suite splices `restore()` by line anchor.
- DEC-F (round 1, R2/R3 critical): the capture fails closed. A failed `mktemp`, per-attempt truncate, or per-attempt append exits 1 before any PASS, because a failed redirect returns 1 and would read as RED.
- DEC-G (round 1, R4 critical): the mismatch is the lowest-ranked reason. The vacuous reason and every restore, tree, and green-after failure outrank it; the mismatch `fail` call sits last.
- DEC-H (round 1, R4 critical): `docs/FEATURES.md` is in Touches and T4 regenerates it first and last; this spec's own commit drifts it.
- DEC-I (deviation from the round-1 fold text): the log uses `mktemp "${TMPDIR:-/tmp}/negctl-red.XXXXXX"`, not `mktemp -t`. Grounding shows macOS `mktemp -t` ignores `TMPDIR`, which would make [49] unprovable on macOS. The explicit template is the form `--at` already uses.
- DEC-J (round 1 warning): the label helpers print nothing and communicate through globals and return status; the caller owns every printed line, so a mutated helper cannot also change the block's shape. `_capture_failed` is the one printing helper, because it ends the run.
- DEC-K (round 2, R1 critical): labels are redacted with the adapter's patterns inside `_red_labels`, because no kit hook scans commit content and a proof block is committed.
- DEC-L (round 2, R2 critical): a per-attempt `printf '\n' >>"$red_log"` probe catches ENOSPC and terminates a bare final line.
- DEC-M (round 2, lead decision): no TMPDIR-inside-root fallback; case [51] of round 1 is dropped and its number reused for the per-attempt guard. The existing snapshot check already fails closed.
- DEC-N (round 2 warning): the log is created after the EXIT trap and the pre-run exits, before the header, so a creation failure never leaves a header without a verdict, and a later failure prints `Verdict: FAIL: red-log capture failed`.
- DEC-O (round 3, R3/R4 critical): `run_test` takes an optional sink, `>"${1-/dev/null}"`, edited in place. The old body redirected to `/dev/null` itself, so `run_test >"$red_log" 2>&1` wrote nothing and every run parsed an empty log. Step 4 calls `run_test "$red_log"` and reads `rc_red=$?` before the append probe. The no-colon form is deliberate: `${1:-...}` maps an empty path to `/dev/null`, which would let the test run and defeat NC3 (Grounding shows both).
- DEC-P (round 3, R2/R3 critical): redaction deviates from copying line 79. The token alternation takes a left boundary `(^|[^A-Za-z0-9])`, widens to `gh[pousr]_|github_pat_|sk-|xox[a-z]-`, and `--expect-red` entries pass through the same `_redact`. The hex pattern stays unbounded because a boundary there leaks; git SHAs redact, accepted. U+2028/2029 join the strip class.
- DEC-Q (round 3 warnings): the fixture holds `task-queue-drains` and `task-runner-works`; [38] and [45] assert no `negctl-red.*` remains under the suite's `TMPDIR`; an NC list change during the build needs an implementation-notes entry with the reason; the ENOSPC-then-recover window and the C-locale UTF-8 cut are named residual risks, not handled.
