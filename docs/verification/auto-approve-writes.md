# Verification -- auto-approve-writes

The permission-auto-approve hook approves a Bash command only after positively
confirming it is a single, simple, read-only invocation (NUL guard, single-line,
character allowlist, tokenize, first-word list, per-tool safe-flag sets);
everything else returns no decision. The hook never emits deny.

HEAD under test: 25f50761 (fix/auto-approve-writes, fixes fold + exit-0 pins).

## Green run (production interpreter, /bin/bash 3.2)

```
Command: bash tests/test-hooks.sh
Exit: 0
Verdict: PASS -- 665/665 assertions green, including all group-(a)
         must-not-approve cases (each pinned twice: exit 0 AND no "allow"
         via paa_fallthrough), the group-(b) must-still-approve cases, the
         AC5 source grep, and the six AC6 per-stage debug-line asserts.
```

## Green run (PATH bash 5.3)

```
Command: PAA_BASH=$(command -v bash) bash tests/test-hooks.sh
Exit: 0
Verdict: PASS -- 665/665.
```

## Full suite

```
Command: RUN_ALL_TIMEOUT_SECS=900 bash tests/run-all.sh --all
Exit: 0 reported; one suite red
Verdict: PASS with one allowed failure: test-no-scattered-ids fails on clean
         master too (lib/gate/proof-ledger.sh:293,415 hits), confirmed by
         stash -> rerun -> same FAIL -> pop. 161 suites run, 0 skipped.
         This run used the corrected paa_fallthrough. An earlier run under
         machine load also flaked test-run-all-time (fixture sleep 2
         measured 3s; passed on retry, unrelated to this diff).
```

## Negative control 1: pre-fix hook restored

```
Command: bash tests/test-hooks.sh
Exit: 0 (green before mutation)
Mutation: git show 1d4f998a~1:hooks/permission-auto-approve.sh > hooks/permission-auto-approve.sh
Changed: hooks/permission-auto-approve.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/permission-auto-approve.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Re-run at 25f50761 with the corrected paa_fallthrough (see "Pin-quality note"
below): still PASS, now red for the intended reason (live-bypass group-(a)
cases assert no "allow" for real).

## Negative control 2: NUL guard mutated to jq contains()

```
Command: bash tests/test-hooks.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' '/| jq -e/s/explode | any(. == 0)/contains("\\u0000")/' hooks/permission-auto-approve.sh
Changed: hooks/permission-auto-approve.sh
Exit: 0 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/permission-auto-approve.sh
Exit: 0 (green after restore)
Verdict: FAIL: test stayed green under the mutation (the check is vacuous)
```

VACUOUS AS PREDICTED on this toolchain: jq 1.8.2 retains NUL bytes in decoded
strings, so contains(" ") detects the byte correctly and the mutation is
behavior-preserving. The control is meaningful only on jq 1.6 (which truncates
strings at the first NUL). The spec's Verification section records this
expectation.

## Negative control 3: NUL guard neutralized (the teeth check)

```
Command: bash tests/test-hooks.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' '/| jq -e/s/any(. == 0)/any(. == -1)/' hooks/permission-auto-approve.sh
Changed: hooks/permission-auto-approve.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/permission-auto-approve.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The neutralized guard lets the NUL payload through to Stage D ("git status
tail-token" approves), so a53 and c1 go red: the NUL case is genuinely pinned.

## Negative control 4: %G reject arm removed

```
Command: bash tests/test-hooks.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' '/--format=\*%G\*|--pretty=\*%G\*/d' hooks/permission-auto-approve.sh
Changed: hooks/permission-auto-approve.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/permission-auto-approve.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Without the reject arm, `git show --format=%GG` matches the `--format=` prefix
and approves, so the new group-(a) case goes red: the %G exclusion is pinned.

Spot check (not via negctl): SAFE_CHARS mutated back to `\/` inside the bracket
class; `find . -name foo\/bar` approves again under both LC_ALL=C and
LC_ALL=en_US.UTF-8 callers, so the backslash-slash group-(a) cases go red on
that revert.

## Pin-quality note (important)

An early draft of paa_fallthrough passed the pattern `"'allow'"` (stray quotes
from generator escaping) instead of `"allow"`, which silently vacated every
not-contains assert while exits stayed 0. Caught by NC4 reporting green under
a mutation that demonstrably produces "allow" by hand. Fixed to `'"allow"'`;
all counts above are from the corrected helper. The earlier "665/665" runs
before this fix are void.

## Ledger honesty

`~/.local/state/dwarves-kit/logs/runs/auto-approve-writes.log` was hand-edited
once during the run to remove a stray `build ran "test"` line, and the file
was rewritten in place. That file is never hand-edited again; it appends only
through `lib/gate/gate-ledger.sh`.

## Not proven

- jq 1.6 behavior: this host runs jq 1.8.2, so the truncation that motivated
  `explode | any(. == 0)` over `contains()` was verified by documentation and
  by the control's vacuousness, not by reproducing a 1.6 mis-detect.
- Commands executed by the real harness under its own shell: the suite drives
  the hook with crafted PermissionRequest JSON; what WORDS[0] resolves to under
  the operator's snapshot (the bfs/ugrep shadowing row in ## Failure modes) is
  out of the hook's reach by design.
- The archive-carried and clone-carried `.git` config residual gaps are
  recorded in the spec (mitigation `safe.bareRepository=explicit` is an
  operator setting), not exercised here.

## Add-on: git work-tree probe (clone-carried bare layout)

HEAD under test: bbc06384 (fix/auto-approve-writes).

Reproduction, pre-fix: a `git init --bare` fixture with `diff.external`
pointed at a marker-writing script ran the script on `git diff` from inside
the layout (marker written), and the hook approved `git log` / `git diff A B`
payloads whose `.cwd` named the layout. The same layout nested inside a
normal repo's subdirectory still resolves as the bare repo (git tests the
directory itself before walking up); `rev-parse --is-inside-work-tree`
prints `false` in both.

Fix: before any git approve path, `git -C <payload .cwd, else $PWD>
rev-parse --is-inside-work-tree` must print exactly `true` and exit 0.

Probe safety, verified live: in a repo with `core.fsmonitor`, `core.pager`,
`pager.rev-parse`, `diff.external`, `filter.<drv>.clean`,
`diff.<drv>.textconv`, and `gpg.program` all pointed at marker scripts,
`git rev-parse --is-inside-work-tree` ran none of them.

### Green runs

```
Command: bash tests/test-hooks.sh
Exit: 0
Verdict: PASS -- 673/673 under /bin/bash 3.2, and again 673/673 under
         PAA_BASH=$(command -v bash). New pins: a54 bare-layout .cwd, a55
         nested-bare .cwd, a56 non-repo .cwd all fall through; b26/b27
         approve through the .cwd-driven probe path inside KIT_DIR.
```

```
Command: RUN_ALL_TIMEOUT_SECS=900 bash tests/run-all.sh --all
Exit: 0 reported; one suite red
Verdict: PASS with the same allowed failure: test-no-scattered-ids only
         (pre-existing on master). 161 suites run, 0 skipped.
```

### Negative control 5: work-tree probe removed

```
Command: bash tests/test-hooks.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' '/^if \[ "${WORDS\[0\]}" = "git" \]; then$/,/^fi$/d' hooks/permission-auto-approve.sh
Changed: hooks/permission-auto-approve.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/permission-auto-approve.sh
Exit: 0 (green after restore)
Verdict: PASS
```

With the probe deleted, `.cwd` is never consulted and the bare-layout,
nested-bare, and non-repo cases approve again, so a54-a56 go red.
