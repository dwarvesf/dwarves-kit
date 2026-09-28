# Verification -- auto-approve-writes

The permission-auto-approve hook approves a Bash command only after positively
confirming it is a single, simple, read-only invocation (NUL guard, single-line,
character allowlist, tokenize, first-word list, per-tool safe-flag sets);
everything else returns no decision. The hook never emits deny.

## Green run (production interpreter, /bin/bash 3.2)

```
Command: bash tests/test-hooks.sh
Exit: 0
Verdict: PASS -- 593/593 assertions green, including all 53 group-(a)
         must-not-approve cases, 25 group-(b) must-still-approve cases, the AC5
         source grep, and the six AC6 per-stage debug-line asserts.
```

## Green run (PATH bash 5.3)

```
Command: PAA_BASH=$(command -v bash) bash tests/test-hooks.sh
Exit: 0
Verdict: PASS -- 593/593.
```

## Full suite

```
Command: RUN_ALL_TIMEOUT_SECS=900 bash tests/run-all.sh --all
Exit: 0 reported; one suite red
Verdict: PASS with one allowed failure: test-no-scattered-ids fails on clean
         master too (lib/gate/proof-ledger.sh:293,415 hits), confirmed by
         stash -> rerun -> same FAIL -> pop. 161 suites run, 0 skipped.
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
- The archive-carried `.git/config` residual gap is recorded in the spec, not
  exercised here.
