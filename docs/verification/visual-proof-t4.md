# Verification -- visual-proof-t4

`wrap land`, with `proof.visual` resolving true in the landed worktree's
`.kit.toml`, runs `bin/proof-asset flush` inside that worktree before the
dirty-tree check and before the push. A non-zero flush stops the land on the
flush's own message. With the flag off the seam is never called and the run is
unchanged. Tests stub the `PROOF_ASSET_BIN` seam; nothing touches the network.

## Green run

Command: `LAND_CACHE=0 bash tests/test-wrap-land.sh`
Exit: 0
Output:

```
=== land: the visual-proof flush runs before the dirty check and the push ===
--- flush: opted in, the flush runs before the dirty check
  PASS flush: a dirty worktree still refuses with 1
  PASS flush: the dirty refusal still names the cause
  PASS flush: the flush ran even though the tree is dirty
  PASS flush: its output landed ahead of the dirty refusal
  PASS flush: it ran inside the landed worktree
--- flush: opted in, a clean land flushes before the push
  PASS flush: the opted-in land still exits 0
  PASS flush: the flush was called once, with the flush verb
  PASS flush: its output precedes the push report
  PASS flush: the land still pushed
  PASS flush: the land still merged
--- flush: opted in, a failing flush stops the land before the push
  PASS flush: a failed flush exits non-zero
  PASS flush: the flush's own message surfaces
  PASS flush: the refusal names the flush
  PASS flush: nothing was pushed
  PASS flush: no PR was opened
  PASS flush: the worktree stays
--- flush: opted out, land never calls the seam
  PASS flush: an opted-out land still exits 0
  PASS flush: the seam was never called
  PASS flush: the land still pushed

test-wrap-land: 12 sections, 12 ran, 0 cached (0 checks credited)
test-wrap-land: all 477 passed
```

Verdict: PASS

## Negative control

The new `sec_flush` section ran against `origin/master`'s
`lib/wrap/wrap-land.sh`: master's tree from `git archive origin/master` in a
temp dir, the branch's `tests/test-wrap-land.sh` overlaid. Master's
`wrap-land.sh` carries no `PROOF_ASSET_BIN` call (`grep -c` returns 0).

Command: `LAND_SECTION=sec_flush bash tests/test-wrap-land.sh` (in the master copy)
Output:

```
  FAIL flush: the flush ran even though the tree is dirty
  FAIL flush: its output landed ahead of the dirty refusal
  FAIL flush: it ran inside the landed worktree
  FAIL flush: the flush was called once, with the flush verb
  FAIL flush: its output precedes the push report
  FAIL flush: a failed flush exits non-zero
  FAIL flush: the flush's own message surfaces
  FAIL flush: the refusal names the flush
  FAIL flush: no PR was opened
  FAIL flush: the worktree stays
land-section-result: 9 10 19
```

Result: RED as expected

## Test plan coverage

| Row | Where |
|---|---|
| 23 | "opted in, the flush runs before the dirty check" and "a clean land flushes before the push" |
| 24 | "a failing flush stops the land before the push" |
| 25 | "opted out, land never calls the seam" |

Verdict: PASS
