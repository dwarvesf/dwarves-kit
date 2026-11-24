# Verification -- adopt-pointer-yields

The adopt pointer's four generic rules now sit under `## Kit defaults (apply only where this repo states no rule of its own)`, after a sentence that a repo's own rule wins. The line-1 marker and `v1` are unchanged, so every reader (hooks, adopt, tests) keeps working. Design: `docs/briefs/DECISION-BRIEF-team-stamp.md`, build step 1.

| Check | Result |
|---|---|
| Fixture repo with its own `## Team rules` section, adopted with `--single-source` | defaults heading, precedence sentence, stop-and-ask default, then the repo's rules, in that order |
| Previous pointer in a repo | known hash: notice, swapped only by `--refresh --swap-agents`; an edited copy left alone |
| Current pointer hash in `agents-known.sha256` | present |
| Pointer size | 1172 bytes, cap 1200 |
| Negative control (old pointer text restored) | RED, 2 failures |

## Primary flow, run end to end

A repo whose only agent file is a CLAUDE.md with its own rule section, adopted for real:

```
Command: bash lib/adopt.sh --single-source <repo with CLAUDE.md holding "## Team rules"> ; then cat <repo>/AGENTS.md
Exit: 0
Output:
  <!-- kit:agents-pointer v1 -->
  ## Kit defaults (apply only where this repo states no rule of its own)
  A rule this repo states, below or in its docs, wins over the matching default here, including when it allows what a default would stop.
  4. Stop and ask a human before: an architecture or interface change, ...
  # Repo
  ## Team rules
  An interface change needs no human sign-off; one reviewer on the PR is enough.
  adopt: <repo> (already adopted, no-op)   <- second run, --refresh
Verdict: PASS
```

## Tests

```
Command: bash tests/test-adopt.sh
Exit: 0
Output:
  ok - pointer over a repo's own rule section: defaults scoped to repos with no rule of their own, own rules kept below
  ok - previous pointer is a known old copy: swapped only on request, an edited one is left alone
  ok - known list holds the current pointer hash
  PASS=81 FAIL=0
Verdict: PASS
```

```
Command: bash tests/test-meta-contract.sh && bash tests/test-install-contract.sh
Exit: 0
Output:
  Passed: 44 / 44
  PASS=4 FAIL=0
Verdict: PASS
```

`bash tests/run-all.sh --changed --time` ran 32 suites on a host at load 334: 28 ok, 4 hit the runner's own timeout with no assertion failed (test-adopt at 118s, test-wrap-adopt-codes, test-wrap-adopt, test-wrap-land). The first three were rerun alone below, test-adopt above. test-wrap-land references only CHANGELOG.md and was not rerun.

```
Command: bash tests/test-wrap-adopt-codes.sh && bash tests/test-wrap-adopt.sh
Exit: 0
Output:
  test-wrap-adopt-codes: all 20 passed
  test-wrap-adopt: all 225 passed
Verdict: PASS
```

## Negative control

## Negative control (negctl)
Command: bash tests/test-adopt.sh
Exit: 0 (green before mutation)
Output:
  ok - agents_only: an old kit AGENTS.md gets no block and still swaps to the pointer
  ok - agents_only: --refresh refuses two blocks and keeps the consumer text between them
  ok - agents_only: --refresh refuses an END before the START
  ok - agents_only: the block append keeps the AGENTS.md mode (640)
  ---
  PASS=81 FAIL=0

Mutation: cp <scratch>/old-pointer.md lib/adopt/AGENTS.pointer.md
Changed: lib/adopt/AGENTS.pointer.md
Exit: 1 (under mutation, RED expected)
Output:
  ok - agents_only: an old kit AGENTS.md gets no block and still swaps to the pointer
  ok - agents_only: --refresh refuses two blocks and keeps the consumer text between them
  ok - agents_only: --refresh refuses an END before the START
  ok - agents_only: the block append keeps the AGENTS.md mode (640)
  ---
  PASS=79 FAIL=2

Restore: git checkout HEAD -- lib/adopt/AGENTS.pointer.md
Exit: 0 (green after restore)
Verdict: PASS

## Rollback

Revert the fix commit. The pointer text returns to the previous version, whose hash stays in `lib/adopt/agents-known.sha256`, so repos swapped to the new pointer are recognised as a known copy and can be swapped back by `--refresh --swap-agents`.
