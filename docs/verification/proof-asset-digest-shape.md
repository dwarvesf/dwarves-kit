# Verification -- proof-asset-digest-shape

`bin/proof-asset put` records the manifest digest as `sha256:<hex>`, so a host whose commit-time secret scan refuses a bare 64-hex run on an added line accepts the manifest. The proof gate reads both the new shape and the older bare hex through one helper.

| Claim | Evidence |
|---|---|
| Before: a real offline put then `git commit` was refused by the host scan | Red before |
| After: no line a put adds holds a bare 40+ hex run | Green run, proof-asset suite, section 21 |
| The writer is the only thing that changed that row | Negative control |
| An old-shape (bare digest) manifest still flushes, re-puts and verifies | Section 22 and visual-gate case 3 |
| The land round trip commits again with the hook active | wrap-land run |

## Red before

Real scan, scratch repo, shipped master writer, offline put then `git add -A && git commit`.

```
Command: bin/proof-asset put land s.png --name shot (offline uploader stub), then git add -A && git commit -qm "docs: proof"
Output:
queued: land/shot (upload failed or offline); run bin/proof-asset flush
git pre-commit: secret-shaped content staged, commit blocked:
  docs/verification/land/assets.json: Hex private key (64 hex chars, also blocks SHA-256 digests by design): 4667... (64 chars)
If real: rotate it, then git restore --staged <file> and remove it.
Exit: 1
```

Only the manifest line `"sha256": "<64 hex>"` matched. The queue `.pending` and the cache sit under the self-ignoring `.kit/proof-assets/`; file names carry 8 hex and the url carries a 32-hex rand, neither a match.

## Green run

```
Command: bash tests/test-proof-asset.sh
Output:
== 13: put online via the uploader stub ==
PASS manifest sha256 is sha256:<hex> of the cached bytes
== 18: re-put of the same name ==
PASS same key on re-put of identical bytes
== round trip: offline put, commit, flush -> the tree lands clean ==
== 21: nothing a put adds to the tree holds a bare digest (the operator's commit-time secret scan) ==
PASS an offline put leaves no bare digest on any added line
PASS the manifest digest reads sha256:<hex>
PASS the check flags a bare digest line (control)
== 22: an old-shape record (bare digest) still flushes and re-puts ==
PASS flush drains a queue whose manifest holds the old bare digest
PASS a re-put over an old-shape manifest keeps one entry
PASS the re-put rewrites the entry in the new shape
ALL PASS
Exit: 0
```

```
Command: bash tests/test-proof-visual-gate.sh
Output:
=== case 3: R3a entry, fetch returns matching bytes, link in proof -> passes ===
PASS case 3: verified uploaded asset passes
=== case 3b: the same entry with the digest recorded as sha256:<hex> -> passes; case 3 above is the old bare shape ===
PASS case 3b: sha256:<hex> digest verifies
PASS case 3b: sha256:<hex> with different bytes blocked
test-proof-visual-gate: all 35 passed
Exit: 0
```

## wrap-land run, operator's global hooks path active

```
Command: bash tests/test-wrap-land.sh
Output:
  PASS round-trip: its stderr reports the queue
  PASS round-trip: land's dirty check would pass already
  PASS round-trip: the committed tree is clean (the cache ignores itself)
  PASS round-trip: the land still merged
  PASS round-trip: the land still pushed
  PASS round-trip: the offline put still exits 0
  PASS round-trip: the queue file holds the pending file
  PASS round-trip: the real flush printed the paste line
  PASS round-trip: the real land exits 0
test-wrap-land: all 880 passed
Exit: 0
```

## NEGATIVE CONTROL

Mutation: the writer stores the bare hex again.

```
## Negative control (negctl)
Command: bash tests/test-proof-asset.sh
Exit: 0 (green before mutation)
Output:
  == 22: an old-shape record (bare digest) still flushes and re-puts ==
  == usage and outside-a-repo guards ==
  ---
  ALL PASS

Mutation: sed -i '' 's/"$(proof_digest_fmt "$sha")"/"$sha"/' lib/proof/asset.sh
Changed: lib/proof/asset.sh
Exit: 1 (under mutation, RED expected)
Output:
  == 22: an old-shape record (bare digest) still flushes and re-puts ==
  FAIL sha256 field: <hex>
  == usage and outside-a-repo guards ==
  ---
  FAILS: 6

Restore: git checkout HEAD -- lib/proof/asset.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Verdict: PASS
