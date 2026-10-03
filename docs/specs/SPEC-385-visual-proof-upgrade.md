# Spec: visual proof upgrade (opt-in)

Generated: 2026-10-03
Status: VALIDATED (round 1: FIX THEN DISPATCH, 13 findings folded)
Lane: full (`lib/gate/proof-ledger.sh` is a hard path)
Type: spec-feature
Design: `docs/briefs/DECISION-BRIEF-visual-proof-upgrade.md` (the why, the mapping table, the risks). This spec freezes the interfaces so parallel workers build against them.
Source: operator ask, session 2026-10-03. The operator approved the brief: public unguessable URLs, `assets = "local"` for sensitive repos, 90-day expiry, one bucket per account by repo owner, opt-in default off.

## Problem

A UI change passes the push gate with a test recap, and nothing makes a delivery carry an image a human can review. Committing images would grow every repo's history forever.

## Rules

| # | Rule | Lands in |
|---|---|---|
| R1 | Everything below is off unless `proof.visual` resolves to `true`. The gate reads it with `KIT_PROJECT_ROOT=$root kit_config_get proof.visual false`. Off means byte-identical behavior to master. | every task |
| R2 | `classify` output is unchanged. `check` computes `visual=yes` separately: R1 on, the class is `behavioral`, and a changed file has a UI extension (Interfaces). `stateful` and `inert` diffs never get the image rule. | T2 |
| R3 | When `visual=yes`, after every existing behavioral rule passes, `check` also needs one qualifying image (R3a, R3b or R3c). | T2 |
| R3a | Uploaded image: an entry in a changed `docs/verification/<dir>/assets.json` whose `url` starts with `<base>/<owner>/<repo>/` (base from the owner routing via `kit_config_get_root`, never the project file), whose exact `![..](url)` line appears in a proof file the branch changed, and whose fetched bytes hash to the entry's `sha256`. The gate ignores the entry's `status`. | T2 |
| R3b | Committed image: an image link in a changed proof file whose target `git ls-files` lists. A gitignored or untracked file does not count. | T2 |
| R3c | Local image: only when `proof.assets = "local"` comes from a tracked, clean project `.kit.toml` (`kit_config_tracked_clean`). An entry with `status: local` whose cached file exists under `.kit/proof-assets/`. | T2 |
| R4 | Block messages name the case: no image at all; `fetch failed: <url>`; `hash mismatch: <url>`; `url outside the proof bucket: <url>`; or, when the manifest holds `pending` entries, "run `bin/proof-asset flush`". | T2 |
| R5 | `bin/proof-asset put <slug> <file> [--name N]` converts and caps the image (R8), hashes it, copies it to the local cache, writes the manifest entry, and uploads when online and `assets = "r2"`. It prints the `![name](url)` line to paste into the proof file. Upload failure or offline: the entry stays `pending`, exit 0, one stderr line says "queued". | T1 |
| R6 | `bin/proof-asset flush [<slug>]` uploads every `pending` entry under the repo, re-hashes, and sets `uploaded`. Nothing pending: exit 0, no output. Any entry still pending: exit 1. | T1 |
| R7 | The key is `<owner>/<repo>/<slug>/<rand>/<name>.<ext>`. `<rand>` is 32 hex chars from `/dev/urandom`, made once per slug and stored in the manifest. A re-put of the same name overwrites the same key and keeps one manifest entry. | T1 |
| R8 | A still image becomes WebP, or optimized PNG when no WebP encoder is installed, at most 300 KB. A GIF stays GIF, at most 2 MB. Still over the cap after conversion: exit 2 with the measured size. | T1 |
| R9 | `proof-gate.sh contract "<task>"`, when R1 is on, adds one `visual:` line naming the expected artifact. A frozen keyword table inside `proof-gate.sh` maps the task text to a row: ui page, ui flow, bot message, tui, report, generated file, else none. Off: output unchanged. | T3 |
| R10 | `/kit:verify`, only when R1 is on, gains a capture step by lane: tiny none; normal one capture per changed screen or the text output; full the set the `visual:` line names. Every image goes through `bin/proof-asset put`. | T3 |
| R11 | `wrap land`, when R1 is on, runs `"${PROOF_ASSET_BIN:-$KIT/bin/proof-asset}" flush` before its dirty-tree check and before any push. A non-zero flush stops the land and prints the flush message. Flush commits nothing; the manifest's `status` is a local hint the gate ignores. | T4 |
| R12 | The R2 credential never reaches stdout, stderr, a file, or a commit. The uploader reads it at call time (wrangler's own login, or `asset_token_ref` through `secret-cache-read`). | T1 |

Boundaries: no change to the negative-control rule, the override path, `classify` output, or any behavior with R1 off. The kit never commits an image. No upload when `assets = "local"`.

## Interfaces (frozen; workers build against these and never change them alone)

**Config.** Kit-root `kit.toml` defaults (T2 adds them):

```toml
[proof]
visual = false
assets = "r2"                   # r2 | local
asset_bucket = "kit-proof-assets"
```

Owner routing lives in the operator file `~/.config/dwarves-kit/kit.toml`, read only through `kit_config_get_root`, so a project file can never redirect it:

```toml
[proof]
account_tieubao = "<cloudflare account id>"
base_url_tieubao = "https://proof.han.ws"
account_dwarvesf = "<cloudflare account id>"
base_url_dwarvesf = "https://proof.d.foundation"
```

The key suffix is the lowercased GitHub owner. A missing base URL for the owner: `put` queues with a stderr warning, and the gate treats every R3a entry as `url outside the proof bucket`.

**Owner and repo.** From `git remote get-url origin`: the last two path parts, `.git` stripped, lowercased. Both forms `git@github.com:o/r.git` and `https://github.com/o/r` resolve the same.

**UI files.** A changed file with extension `.tsx .jsx .vue .svelte .css .scss .html`. A path segment alone (`app/`, `pages/`) never makes a file visual.

**Manifest.** `docs/verification/<slug>/assets.json`, committed, written by `put` with `jq`:

```json
{
  "slug": "<slug>",
  "rand": "<32 hex>",
  "assets": [
    {"name": "settings-desktop", "file": "settings-desktop.webp", "status": "pending|uploaded|local",
     "url": "<base>/<owner>/<repo>/<slug>/<rand>/settings-desktop.webp",
     "sha256": "<hex>", "bytes": 123456}
  ]
}
```

The gate does not use its slug argument for manifests. It reads every changed path matching `(^|/)docs/verification/[^/]+/assets\.json`.

**Local cache.** `<repo root>/.kit/proof-assets/<slug>/<file>`. T1 adds `.kit/proof-assets/` to this repo's `.gitignore`.

**Seams** (tests set them; no test touches the network):

| Var | Called as | Default |
|---|---|---|
| `PROOF_ASSET_UPLOADER` | `<cmd> <local-file> <key> <account-id>` | `CLOUDFLARE_ACCOUNT_ID=<id> wrangler r2 object put "<bucket>/<key>" --file <local-file> --remote` |
| `PROOF_ASSET_FETCH` | `<cmd> <url>`, body on stdout | `curl -fsS --proto =https --max-time 15 --max-filesize 3000000` |
| `PROOF_ASSET_CONVERT` | `<cmd> <in> <out>` | `cwebp -q 80`, else `pngquant`, else copy |
| `PROOF_ASSET_BIN` | `<bin> flush` | `$KIT/bin/proof-asset` |

**Hashing.** `shasum -a 256`. The gate pipes the fetch straight into the hasher and never holds the body in a variable.

**Proof file line.** `put` prints `![<name>](<url>)`.

## Tasks (owned files; a task never edits another task's files)

| Task | Owner | Files | Depends on |
|---|---|---|---|
| T0 R2 infra | lead | Cloudflare only (done: buckets, 90-day rule, `proof.han.ws`, `proof.d.foundation`, public GET 200) | none |
| T1 proof-asset CLI | worker | `bin/proof-asset`, `lib/proof/asset.sh`, `tests/test-proof-asset.sh`, `.gitignore` | spec |
| T2 gate | worker | `lib/gate/proof-ledger.sh`, `kit.toml`, `tests/test-proof-visual-gate.sh` | spec |
| T3 contract and verify | worker | `lib/gate/proof-gate.sh`, `commands/verify.md`, `tests/test-proof-contract-visual.sh` | spec |
| T4 land flush | worker | `lib/wrap/wrap-land.sh`, `tests/test-wrap-land.sh` (new section only) | spec (seam, not T1) |
| T5 docs and wiring | lead | `docs/verification/README.md`, `AGENTS.md`, `docs/FEATURES.md` (regenerated), operator file | T1 to T4 |

## Test plan

| # | Case | Expect | Task |
|---|---|---|---|
| 1 | R1 off, UI diff, text-only proof | passes exactly as on master | T2 |
| 2 | R1 on, UI diff, text-only proof | BLOCKED, "no image" | T2 |
| 3 | R1 on, UI diff, R3a entry, fetch returns matching bytes, line in proof | passes | T2 |
| 4 | R1 on, UI diff, R3a entry, fetch bytes differ | BLOCKED, "hash mismatch" | T2 |
| 5 | R1 on, UI diff, entry `pending`, fetch fails | BLOCKED, "fetch failed" and "run bin/proof-asset flush" | T2 |
| 6 | R1 on, UI diff, `assets = local` tracked clean, cached file present | passes | T2 |
| 7 | R1 on, UI diff, committed tracked image in branch | passes | T2 |
| 8 | R1 on, stateful diff touching a UI file | no image rule | T2 |
| 9 | R1 on, `assets = local` set only in an uncommitted `.kit.toml` | R3c refused | T2 |
| 10 | R1 on, entry URL outside `<base>/<owner>/<repo>/` | BLOCKED, "url outside the proof bucket" | T2 |
| 11 | R1 on, image link to a gitignored file under `.kit/proof-assets/` | R3b refused | T2 |
| 12 | R1 on, `app/models/user.rb` only | not visual | T2 |
| 13 | `put` online via uploader stub | entry `uploaded`, prints `![name](url)`, key matches R7 | T1 |
| 14 | `put` with uploader failing | entry `pending`, exit 0, stderr "queued" | T1 |
| 15 | `flush` after the uploader recovers | `uploaded`, exit 0; nothing pending: exit 0, no output | T1 |
| 16 | `flush` with the uploader still failing | exit 1 | T1 |
| 17 | `put` over the cap after conversion (still and GIF) | exit 2 with size | T1 |
| 18 | re-`put` same name | same key, one manifest entry | T1 |
| 19 | `put` with no WebP encoder (convert seam) | PNG path taken | T1 |
| 20 | `put` and `flush` stdout and stderr hold no credential-shaped string | none | T1 |
| 21 | R1 on, `contract "redesign the settings page UI"` | a `visual:` line naming desktop and 400px screenshots | T3 |
| 22 | R1 off, `contract` | output identical to master | T3 |
| 23 | `wrap land`, R1 on, flush stub ok | flush runs before the dirty check and the push | T4 |
| 24 | `wrap land`, R1 on, flush stub fails | land stops before any push | T4 |
| 25 | `wrap land`, R1 off | no flush call | T4 |

Each task's proof file `docs/verification/visual-proof-<task>.md` carries its test run with captured output and a negative control: its new tests run against master's version of its files, red.

## Exit criteria

- All 25 cases pass. The full suite shows no new failure against master's baseline (`test-stats-no-persist` and the nightly's `test-wrap-apply`/`test-wrap-land` are known baseline failures).
- With R1 off, the existing gate, verify and land suites pass unchanged.
- T0: done (an object put to each bucket answers a public GET 200; the 90-day rule reads back).
