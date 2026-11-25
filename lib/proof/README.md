# proof

The asset pipeline for visual proof of done. A reviewer needs an image they can open, but committed images grow the repo forever. This module stores the bytes in a bucket and commits only a manifest.

**Entry points**
- `bin/proof-asset put <slug> <file> [--name N]` forwards to `lib/proof/asset.sh`. It converts and caps the image (a still to WebP, at most 300 KB, and a GIF stays GIF, at most 2 MB), hashes it, caches it, updates the manifest, and uploads when `proof.assets` is `r2`. It prints the `![name](url)` embed line.
- `lib/proof/digest.sh` (sourced): the one parser for the manifest digest. `proof_digest_fmt <hex>` gives the recorded `sha256:<hex>`; `proof_digest_hex <recorded>` gives the bare hex from either that shape or the older bare one.
- `bin/proof-asset flush [<slug>]`: upload every queued file and exit 1 while any remain.

**Layout**
- `docs/verification/<slug>/assets.json`: the committed manifest. Each entry holds the final url, `sha256`, bytes and a `status` of `r2` or `local`. The `sha256` field reads `sha256:<hex>`: a bare 64-hex run on a committed line trips a commit-time secret scan, which exempts a run after that marker. The gate also accepts the bare hex an older `put` wrote.
- `.kit/proof-assets/<slug>/`: the gitignored cache and the `.pending` upload queue.

The proof gate itself lives in `lib/gate/proof-ledger.sh`, not here.

**Tests**: `tests/test-proof-asset.sh` (`bash tests/test-proof-asset.sh`). The gate side is covered by `tests/test-proof-visual-evidence.sh` and `tests/test-proof-visual-gate.sh`. `lib/proof/` has no `tests/` directory.

**Spec and docs**: `docs/specs/SPEC-385-visual-proof-upgrade.md`.
