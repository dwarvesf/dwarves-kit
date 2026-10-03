# Proof of done: proof-asset CLI (put + flush)

## What changed

`bin/proof-asset` is a thin forwarder to `lib/proof/asset.sh` (the new `lib/proof/`
subsystem). `put <slug> <file> [--name N]` converts and caps the image, hashes it,
caches it, upserts its manifest entry, and uploads or queues it:

- Convert + cap: a still goes through `PROOF_ASSET_CONVERT` (default `cwebp -q 80`,
  else `pngquant`, else a copy); the produced bytes are sniffed for their real type so
  the entry lands as `<name>.webp` or `<name>.png`. A GIF is never converted. Stills cap
  at 300 KB, GIFs at 2 MB; over the cap exits 2 with the measured size.
- Hash + cache + manifest: `shasum -a 256`, copy to the gitignored
  `.kit/proof-assets/<slug>/`, and a `jq` upsert into the committed
  `docs/verification/<slug>/assets.json`, keyed by entry name so a re-put keeps one entry.
- Key + url: `<owner>/<repo>/<slug>/<rand>/<name>.<ext>`, owner/repo parsed from the
  origin remote (scp and https forms resolve the same), `<rand>` 32 hex chars made once
  per slug and stored in the manifest. `proof.base_url_<owner>` and
  `proof.account_<owner>` resolve root-only, so a project `.kit.toml` cannot redirect
  the upload route.
- Upload: only when `proof.assets` resolves to `r2`. A failed or unroutable upload
  leaves the entry `pending`, exits 0, prints one `queued` stderr line, and still prints
  the `![name](url)` paste line for the proof file.
- `flush [<slug>]`: retries every `pending` entry, re-hashing the cached bytes and
  updating sha256/bytes/url on success. Nothing pending exits 0 with no output; any
  entry still pending exits 1. Under `assets = "local"` nothing ever uploads: `put`
  writes `local` and `flush` heals stale `pending` entries to `local`.
- Credential: never on stdout, stderr, a file, or a commit. The default uploader reads
  `proof.asset_token_ref` (root-only) through `secret-cache-read` into the wrangler
  environment at call time, else wrangler's own login.

## Gate table

| Claim | Evidence |
|---|---|
| put online -> `uploaded`, prints `![name](<base>/<owner>/<repo>/<slug>/<rand>/<name>.<ext>)`, uploader called as `<file> <key> <account-id>` | case 13 below |
| put with a failing uploader -> `pending`, exit 0, stderr `queued` | case 14 |
| flush after recovery -> `uploaded`, exit 0; nothing pending -> exit 0, no output | case 15 |
| flush while still failing -> exit 1 | case 16 |
| over cap after conversion, still and GIF -> exit 2 with the measured size, no manifest | case 17 |
| re-put same name -> same key, one manifest entry | case 18 |
| converter emits PNG (no WebP encoder) -> `.png` path taken | case 19 |
| put and flush output holds no credential-shaped string; token reaches the uploader env only | case 20 |
| `assets = "local"` -> cached + manifest, no upload attempted | extra case |
| the tests are load-bearing | negative control below |

## Run table

```
Command: bash tests/test-proof-asset.sh
Exit: 0
Output:
== 13: put online via the uploader stub ==
PASS put exits 0
PASS prints ![shot](<base>/<owner>/<repo>/<slug>/<rand>/shot.webp)
PASS manifest written
PASS image cached under .kit/proof-assets/
PASS entry status uploaded
PASS manifest sha256 matches the cached bytes
PASS manifest rand is the url rand, stored once
PASS uploader called as <file> <key> <account-id>
== 14: put with the uploader failing ==
PASS failed upload still exits 0
PASS entry stays pending
PASS one stderr line says queued
PASS the paste line still prints the future url
== 15: flush after the uploader recovers ==
PASS flush exits 0
PASS pending -> uploaded
PASS nothing pending: exit 0, no output
== 16: flush with the uploader still failing ==
PASS flush exits 1 with an entry still pending
== 17: over the cap after conversion (still and GIF) ==
PASS still over 300KB: exit 2 with the measured size
PASS GIF over 2MB: exit 2 with the measured size
PASS an over-cap put writes no manifest
== 18: re-put of the same name ==
PASS same key on re-put (identical url line)
PASS still one manifest entry
== 19: no WebP encoder answers (convert seam emits PNG) ==
PASS PNG path taken: entry file and url carry .png
== 20: no credential-shaped string in put/flush output ==
PASS put output holds neither the token nor its ref
PASS the token reached the uploader through the env
PASS the account id reached the uploader env
PASS default uploader ran wrangler r2 object put <bucket>/<key>
PASS the manifest holds no token
PASS flush output holds no token
== assets = local: cache + manifest, never an upload ==
PASS entry status local
PASS no upload attempted in local mode
PASS prints a paste line
== usage and outside-a-repo guards ==
PASS no args -> usage, exit 64
PASS outside a git repo -> nonzero, says why
---
ALL PASS
Verdict: PASS
```

## Negative control

The new suite run inside a temp copy of the repo at `origin/master` (which has no
`bin/proof-asset`, no `lib/proof/asset.sh`, and no `.kit/proof-assets/` gitignore):
`git archive origin/master | tar -x -C <tmp>` plus the new test file copied in.

```
Command: bash <tmp>/tests/test-proof-asset.sh
Exit: 1
Output (tail):
== 20: no credential-shaped string in put/flush output ==
FAIL leak: rc=127 out=[] err=[bash: <tmp>/bin/proof-asset: No such file or directory]
FAIL wrangler env:
FAIL no account id in uploader env
FAIL wrangler argv:
PASS the manifest holds no token
FAIL flush leak/rc=127: [] [bash: <tmp>/bin/proof-asset: No such file or directory]
== assets = local: cache + manifest, never an upload ==
FAIL rc=127 status=
PASS no upload attempted in local mode
FAIL no paste line
== usage and outside-a-repo guards ==
FAIL rc=127 out=[bash: <tmp>/bin/proof-asset: No such file or directory]
FAIL rc=127 err=[bash: <tmp>/bin/proof-asset: No such file or directory]
---
FAILS: 30
Result: RED as expected
```

## Changed-suite run

```
Command: bash tests/run-all.sh --changed origin/master
Exit: 1
Output (tail):
test-proof-asset                               ok
run-all: FAILED -> test-config-registry test-meta
```

Both failures are in files this task does not own, not in the new code:
`test-config-registry` AC10 wants the four new `proof.*` root-only keys declared in
`lib/config/module-registry.md` (unowned by any task in the spec's table), and
`test-meta` wants `docs/FEATURES.md` regenerated (a T5 file). Also noted for the full
suite: `tests/test-bin-forwarders.sh`'s exact `bin/` census does not know
`proof-asset` yet (not selected by `--changed`, red under `--all`).

## Final run

```
Command: bash tests/test-proof-asset.sh
Exit: 0
Output (tail):
PASS entry status local
PASS no upload attempted in local mode
PASS prints a paste line
== usage and outside-a-repo guards ==
PASS no args -> usage, exit 64
PASS outside a git repo -> nonzero, says why
---
ALL PASS
Verdict: PASS
```
