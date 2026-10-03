# Implementation notes: SPEC-385 visual proof upgrade

The delta from `docs/specs/SPEC-385-visual-proof-upgrade.md`. Decisions, changes and open questions only.

## Decisions

- **T0 uses wrangler's own login, not a scoped token.** No stored Cloudflare token in 1Password has R2 permission. The Air's wrangler login can create buckets and put objects. `asset_token_ref` stays empty for now.
- **Domains:** `proof.han.ws` (personal account, zone han.ws) and `proof.d.foundation` (Dwarves account, zone d.foundation). Both are R2 custom domains, so reads are public and listing is off.
- **Spec round 1 changed the shape:** the gate no longer adds a `visual` class to `classify`; it computes the image rule inside `check`. The gate ignores manifest `status` and trusts only a fetch plus hash on a URL under the operator's base, so flush never has to commit.

## Open questions

- **The Mini cannot upload yet:** its wrangler is not logged in. Captures made there queue until a flush runs on the Air. Fix: mint an R2-scoped API token, store it in 1Password, and set `asset_token_ref`.
- **Implementation workers:** Sonnet is at its weekly limit until Oct 8, so Devin builds T1 to T4 and Opus reviews.
- **Account ids stay out of every repo.** The operator file holds `account_<owner> = "op://Toolkit/kit-proof-assets/account_<owner>"`, and `base_url_<owner>` as plain text (dotfiles #665). The frozen interface says the key holds an account id, so the lead adds one rule at integration: a value starting with `op://` resolves through `secret-cache-read` before the uploader call. T1 did not get this rule; it lands as a lead patch to `lib/proof/asset.sh`.

## Battery round 1

Four-reviewer battery findings, all fixed; every fix carries a regression test that went red first.

- **Manifest holds destination, not progress.** `status` is `r2` or `local`; upload progress moved to the gitignored queue `.kit/proof-assets/<slug>/.pending` (one file name per line). `flush` drains the queue, prints each `![name](url)` line, and never rewrites the committed manifest, so a successful flush no longer dirties the worktree ahead of `wrap land`'s dirty check.
- **Unchecked manifest fields are a path-escape hole.** `put` and `flush` validate `slug`, `rand` (32 lowercase hex), and `file` (the image-name regex) before touching the filesystem or the bucket, and require `.assets` to be an array; bad entries and bad queue lines warn and are skipped, never uploaded. `jq --argjson i` replaces `$i` interpolation.
- **Cache ignores itself.** `put` writes `.kit/proof-assets/.gitignore` containing `*` when missing, so `git add -A` in any repo can never commit the cache or the queue.
- **Key carries a hash suffix.** Stored file is `<name>-<sha8>.<ext>`: a re-put of changed bytes mints a fresh key, so the edge cache cannot serve stale bytes the gate would hash-reject.
- **Missing base URL refuses up front.** Under `assets = "r2"`, `put` exits 1 naming the missing `proof.base_url_<owner>` key and writes nothing, instead of printing a cache path the gate could never accept. Trailing slashes on the base are stripped in `put` and `flush`.
- **Small fixes.** `--name settings.v2` keeps its dot; the Cloudflare token passes inline on the wrangler call, never exported; a still image no encoder can convert falls back to `sips -s format png`, else `put` exits 2.
- **Gate hardening.** R3a rejects URLs with `..` or `%` (curl normalization could make another repo's object hash-match), caps verified fetches at five, refuses declared bytes over 3 MB before fetching, and the default fetch adds `-q` so `~/.curlrc` cannot change gate behavior. R3b counts a committed image only when the image path itself changed on the branch. R3c validates `slug` and `file` before the `-f` test.
- **Project config trust.** The visual rule reads the project `.kit.toml` only when `kit_config_tracked_clean` holds; an untracked or dirty project file can no longer arm or disarm the rule. The audited override path now also clears a visual-only block while still refusing source-code changes.
- **Land.** `_land_proof_body` renders a `.kit/proof-assets/` image link as `_(local image, not uploaded: <file>)_` instead of a broken blob URL, and the land suite pins `KIT_CONFIG_OPERATOR` to an empty dir so a real operator opt-in cannot trigger live flushing. A real round-trip test puts offline, commits, and drains the queue through an unstubbed `wrap land`.
- **verify.md.** The final report shows the image itself: every `![name](url)` line (or the cache path, opened with `orca-view` on Orca) listed under the captured output. Bot and chat work iterates through `tools/message-contract/bin/preview` with no posting, then captures once per branch at the end.

## Lead verification after battery round 1

- **Edge-cached 404.** Cloudflare caches a 404 on the proof domains for 4 hours (`cache-control: max-age=14400`). A gate run before the upload poisoned the URL, so the gate kept failing after the flush. The gate now fetches `<url>?kit-check=<epoch>`, and the query is part of the cache key. The PR image (GitHub fetches the plain URL) can still show a broken image for up to 4 hours when anything fetched it before the upload. Open: a zone Cache Rule that never caches 404 on `proof.*`, which needs a token with cache-rule permission.
- **Exploit re-run.** The security reviewer's traversal manifest (`"file":"../../../../outside.txt"`) with a matching queue line: flush refuses ("manifest slug/rand/assets invalid"), no upload call.
