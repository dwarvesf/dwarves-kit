# Proof of done: proof-asset CLI (put + flush)

## What changed

`bin/proof-asset` is a thin forwarder to `lib/proof/asset.sh` (the new `lib/proof/`
subsystem). `put <slug> <file> [--name N]` converts and caps the image, hashes it,
caches it, upserts its manifest entry, and uploads or queues it:

- Convert + cap: a still goes through `PROOF_ASSET_CONVERT` (default `cwebp -q 80`,
  else `pngquant`, else `sips -s format png`, else exit 2; a raw copy is never an
  answer). The produced bytes are sniffed for their real type so the entry lands as
  `<name>-<sha8>.webp` or `.png`. A GIF is never converted. Stills cap at 300 KB,
  GIFs at 2 MB; over the cap exits 2 with the measured size.
- Hash + cache + manifest: `shasum -a 256`, copy to `.kit/proof-assets/<slug>/`
  (a `.gitignore` holding `*` is written when missing, so the cache ignores itself
  in any repo), and a `jq` upsert into the committed
  `docs/verification/<slug>/assets.json`, keyed by entry name so a re-put keeps one
  entry. `slug`, `rand`, `file`, and `.assets` are validated before any use; a bad
  committed manifest warns and is skipped or replaced, never trusted.
- Key + url: `<owner>/<repo>/<slug>/<rand>/<name>-<sha8>.<ext>`, owner/repo parsed
  from the origin remote (scp and https forms resolve the same), `<rand>` 32 hex
  chars made once per slug and stored in the manifest. The sha8 in the file name
  means a re-put of changed bytes mints a fresh key, so a stale edge cache cannot
  serve old bytes the gate would hash-reject. `proof.base_url_<owner>` and
  `proof.account_<owner>` resolve root-only, so a project `.kit.toml` cannot
  redirect the upload route; a missing base URL under `assets = "r2"` exits 1
  naming the key and writes nothing.
- Upload state: the committed manifest records the final destination only
  (`status` = `r2` or `local`). Upload progress lives in the gitignored queue
  `.kit/proof-assets/<slug>/.pending`, one cached file name per line. A failed or
  unroutable upload still exits 0, prints one `queued` stderr line, and still
  prints the `![name](url)` paste line for the proof file.
- `flush [<slug>]`: drains the queue, re-hashing the cached bytes and uploading
  each pending file, printing its `![name](url)` line, and removing the line on
  success. It never writes the manifest, so a successful flush leaves the
  worktree clean. Nothing pending exits 0 with no output; any entry still
  pending exits 1. Under `assets = "local"` nothing ever uploads and `put`
  prints the cache-path embed.
- Credential: never on stdout, stderr, a file, or a commit. The default uploader
  reads `proof.asset_token_ref` (root-only) through `secret-cache-read` into the
  wrangler environment at call time, else wrangler's own login; the token is
  passed inline, never exported.

## Gate table

| Claim | Evidence |
|---|---|
| put online -> `status: r2`, prints `![name](<base>/<owner>/<repo>/<slug>/<rand>/<name>-<sha8>.<ext>)`, uploader called as `<file> <key> <account-id>` | case 13 below |
| put with a failing uploader -> queue line written, exit 0, stderr `queued`, paste line prints the future url | case 14 |
| flush after recovery -> queue drains, manifest byte-identical, `![name](url)` printed, exit 0; nothing pending -> exit 0, no output | case 15 |
| flush while still failing -> exit 1 | case 16 |
| over cap after conversion, still and GIF -> exit 2 with the measured size, no manifest | case 17 |
| re-put same bytes -> same key; changed bytes -> new key; one manifest entry | case 18 |
| converter emits PNG (no WebP encoder) -> `.png` path taken | case 19 |
| put and flush output holds no credential-shaped string; token reaches the uploader env only | case 20 |
| r2 with no `base_url_<owner>` -> exit 1 naming the key, no manifest, no cache | base-url case |
| traversal manifest `file`/queue line and non-array `.assets` -> warned, skipped, never uploaded | distrust cases |
| no-encoder still -> `sips` png fallback or exit 2, never a raw copy | encoder case |
| `assets = "local"` -> cached + manifest `status: local`, no upload attempted, cache-path embed | extra case |
| offline put, commit, flush -> `git status --porcelain` empty | round-trip case |
| the tests are load-bearing | negative control below |

## Run table

```
Command: bash tests/test-proof-asset.sh
Exit: 0
Output (tail):
== 15: flush after the uploader recovers ==
PASS flush exits 0
PASS the .pending queue drains
PASS flush never rewrites the committed manifest
PASS flush prints the ![name](url) line for what it uploaded
PASS nothing pending: exit 0, no output
== 16: flush with the uploader still failing ==
PASS flush exits 1 with the line still pending
== 18: re-put of the same name ==
PASS same key on re-put of identical bytes
PASS new bytes move the key (sha8 changes, stale edge cache cannot bite)
PASS still one manifest entry
== r2 with no base url: exit 1 naming the key, writing nothing ==
PASS missing base url exits 1 naming proof.base_url_<owner>
PASS writes nothing (no manifest, no cache)
PASS no origin remote: exit 1, writes nothing
== put distrusts a bad committed manifest ==
PASS a bad manifest rand warns and is replaced
PASS a non-array .assets refuses, manifest untouched
== flush distrusts the queue and the manifest ==
PASS a traversal queue line is warned, dropped, never uploaded
PASS the bad line leaves the queue
PASS a bad manifest rand blocks the flush, queue kept
PASS a manifest slug that fights its dir blocks the flush
== a still no encoder can convert must not land as a copy ==
PASS unconvertible still: exit 2, no manifest
PASS sips is the last encoder: jpeg -> .png
== assets = local: cache + manifest, never an upload ==
PASS entry status local
PASS no upload attempted in local mode
PASS prints a paste line
PASS local mode prints the cache-path embed
== round trip: offline put, commit, flush -> the tree lands clean ==
PASS the queued put flushes once the uploader is back
PASS git status --porcelain is empty after the flush
PASS only ignored cache lines remain: land's dirty check would pass
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
== assets = local: cache + manifest, never an upload ==
FAIL rc=127 status=
PASS no upload attempted in local mode
FAIL no paste line
FAIL paste line:
== round trip: offline put, commit, flush -> the tree lands clean ==
FAIL flush rc=127 out=[]
PASS git status --porcelain is empty after the flush
PASS only ignored cache lines remain: land's dirty check would pass
== usage and outside-a-repo guards ==
FAIL rc=127 out=[bash: <tmp>/bin/proof-asset: No such file or directory]
FAIL rc=127 err=[bash: <tmp>/bin/proof-asset: No such file or directory]
---
FAILS: 47
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
PASS local mode prints the cache-path embed
== round trip: offline put, commit, flush -> the tree lands clean ==
PASS the queued put flushes once the uploader is back
PASS git status --porcelain is empty after the flush
PASS only ignored cache lines remain: land's dirty check would pass
== usage and outside-a-repo guards ==
PASS no args -> usage, exit 64
PASS outside a git repo -> nonzero, says why
---
ALL PASS
Verdict: PASS
```
