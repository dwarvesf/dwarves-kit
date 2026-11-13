# Verification -- kit-weekly-prose-rag-path

The `kit-weekly` dispatcher now puts `$HOME/.cargo/bin` on PATH, so the `prose-rag-index` job finds `ctx` under launchd's bare PATH. Before, the job failed every week with `prose-rag: engine not installed`.

## Green run

```
Command: env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin KIT_WEEKLY_JOBS=<one-line list: prose-rag-index bin/prose-rag index> bash deploy/macos/kit-weekly
Exit: 0
Output:
  kit-weekly: running 'prose-rag-index' (.../bin/prose-rag index)
  prose-rag: embedding 20232 chunks from 1125 changed files (33 removed, 2182 total files)...
  prose-rag: indexed 30666 chunks (2182 files) -> ~/.claude/prose-rag/index.bin
  kit-weekly: 'prose-rag-index' ok
  kit-weekly: done (ran=1 skipped=0 failed=0)
Verdict: PASS
```

```
Command: bash tests/test-kit-weekly.sh
Exit: 0
Output:
  PASS bare launchd PATH finds ctx in ~/.cargo/bin and the job succeeds
  PASS no engine and no corpus skips clean (an unconfigured consumer)
  PASS corpus set but no engine anywhere still fails loud (NC)
  TOTAL: 18   PASS: 18   FAIL: 0
Verdict: PASS
```

## Negative control

```
Command: same one-job run, before the fix (PATH without ~/.cargo/bin)
Exit: 0 (the dispatcher continues past a failed job)
Output:
  prose-rag: engine not installed; install context-kit's binary: cargo install --path <context-kit>/src/ctx (or set PROSE_RAG_BIN)
  kit-weekly: 'prose-rag-index' FAILED (exit 1), continuing
  kit-weekly: done (ran=0 skipped=0 failed=1)
Verdict: PASS (fails before the fix, succeeds after)
```

```
Command: remove "$HOME/.cargo/bin:" from the PATH line; bash tests/test-kit-weekly.sh
Exit: 1
Output:
  FAIL prose-rag-index did not reach ctx under a bare PATH
  TOTAL: 18   PASS: 17   FAIL: 1
Verdict: PASS (reverted fix is red; restored is 18 of 18)
```

## Rollback

Revert the one PATH line in `deploy/macos/kit-weekly`; the installed plist points at the dispatcher, so nothing else changes. The live plist is untouched.

## Not proven

- The "after" run was a real index of the operator's corpus, started by hand with launchd's PATH, not a launchd firing. The next Monday 09:00 run is the end-to-end check.
