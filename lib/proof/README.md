# proof

The asset pipeline for visual proof of done. A reviewer needs an image they can open, but committed images grow the repo forever. This module stores the bytes in a bucket and commits only a manifest.

**Entry points**
- `bin/proof-asset put <slug> <file> [--name N]` forwards to `lib/proof/asset.sh`. It converts and caps the image (a still to WebP, at most 300 KB, and a GIF stays GIF, at most 2 MB), hashes it, caches it, updates the manifest, and uploads when `proof.assets` is `r2`. It prints the `![name](url)` embed line.
- `bin/proof-asset flush [<slug>]`: upload every queued file and exit 1 while any remain.

**Layout**
- `docs/verification/<slug>/assets.json`: the committed manifest. Each entry holds the final url, sha256, bytes and a `status` of `r2` or `local`.
- `.kit/proof-assets/<slug>/`: the gitignored cache and the `.pending` upload queue.

The proof gate itself lives in `lib/gate/proof-ledger.sh`, not here.

**Tests**: `tests/test-proof-asset.sh` (`bash tests/test-proof-asset.sh`). The gate side is covered by `tests/test-proof-visual-evidence.sh` and `tests/test-proof-visual-gate.sh`. `lib/proof/` has no `tests/` directory.

**Spec and docs**: `docs/specs/SPEC-385-visual-proof-upgrade.md`.
