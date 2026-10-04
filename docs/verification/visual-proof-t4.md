# Verification -- visual-proof-t4

`wrap land`, with `proof.visual` resolving true in the landed worktree's
`.kit.toml`, runs `bin/proof-asset flush` inside that worktree before the
dirty-tree check and before the push. A non-zero flush stops the land on the
flush's own message. With the flag off the seam is never called and the run is
unchanged. Battery round 1 additions: `_land_proof_body` renders a
`.kit/proof-assets/` image link as `_(local image, not uploaded: <file>)_`
instead of a broken blob URL, the harness pins `KIT_CONFIG_OPERATOR` to an empty
dir so a real operator opt-in cannot fire a live flush, and a real round-trip
test puts offline, commits, then drains the queue through an unstubbed
`wrap land`. Tests stub the `PROOF_ASSET_BIN` seam where noted; nothing touches
the network.

## Green run

Command: `LAND_CACHE=0 bash tests/test-wrap-land.sh`
Exit: 0
Output (tail):

```
--- PB6: a local cache link becomes a named marker; a committed image still hotlinks
  PASS PB6: the local cache link is named, not hotlinked
  PASS PB6: no blob URL was minted for the cache file
  PASS PB6: the committed image still becomes a blob url
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
--- flush: a real offline put drains through the real flush inside land
  PASS round-trip: the offline put still exits 0
  PASS round-trip: its stderr reports the queue
  PASS round-trip: the queue file holds the pending file
  PASS round-trip: the committed tree is clean (the cache ignores itself)
  PASS round-trip: land's dirty check would pass already
  PASS round-trip: the real land exits 0
  PASS round-trip: the real flush printed the paste line
  PASS round-trip: the land still pushed
  PASS round-trip: the land still merged

test-wrap-land: 12 sections, 12 ran, 0 cached (0 checks credited)
test-wrap-land: all 489 passed
```

Verdict: PASS

## Negative control

The new `sec_flush` section ran against `origin/master`'s
`lib/wrap/wrap-land.sh`: master's tree from `git archive origin/master` in a
temp dir, the branch's `tests/test-wrap-land.sh` overlaid. Master's
`wrap-land.sh` carries no `PROOF_ASSET_BIN` call (`grep -c` returns 0) and no
`bin/proof-asset` exists there.

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
  FAIL round-trip: the offline put still exits 0
  FAIL round-trip: its stderr reports the queue
  FAIL round-trip: the queue file holds the pending file
  FAIL round-trip: the real flush printed the paste line
land-section-result: 14 14 28
```

Result: RED as expected

## Test plan coverage

| Row | Where |
|---|---|
| 23 | "opted in, the flush runs before the dirty check" and "a clean land flushes before the push" |
| 24 | "a failing flush stops the land before the push" |
| 25 | "opted out, land never calls the seam" |
| battery | PB6 local-link marker, "a real offline put drains through the real flush inside land" |

Verdict: PASS
