# Decision Brief: visual proof upgrade

Date: 2026-10-03 · Source: operator ask in session (no board row yet). Status: DRAFT, awaiting operator approval before any build.

## Goal

Every delivery from a kit-run task carries a proof a human can review at a glance: on the local machine and inline in the PR. The proof costs little task time and does not grow the git repo.

## Verified current state (2026-10-03)

| Piece | State |
|---|---|
| Push gate (`lib/gate/proof-ledger.sh check`) | A behavioral diff needs a green run with captured output (#892) plus a negative control. A typed `Exit: 0` alone is refused. |
| Images | Accepted only as a file committed in the branch (`_has_committed_image`). Nothing requires one. |
| PR body | `wrap land` copies the proof file into the PR description and rewrites relative image links to sha-pinned GitHub URLs (#892). |
| Task type to artifact | `proof-gate.sh contract` returns the same `behavioral` contract for UI work and for a CLI flag. |
| Coverage | 21 of 68 repos have the gate on. Eight repos with commits in the last 30 days do not. |

## Opt-in: off by default

The upgrade is a setting. With it off, the kit behaves exactly as today (#892: captured text output plus a negative control). Nothing in this brief changes for an operator or a repo that has not turned it on.

```toml
[proof]
visual = false      # kit default. true turns on everything below.
assets = "r2"       # "r2" uploads images; "local" keeps them in the local cache, never uploaded.
```

The kit's existing config layers decide it (`lib/config/kit-config.sh`): a per-repo `.kit.toml` wins over the operator file `~/.config/dwarves-kit/kit.toml`, which wins over the kit default. One operator turns it on for every repo in the operator file. A sensitive repo sets `assets = "local"` in its own `.kit.toml`, and a repo that wants no visual proof sets `visual = false`.

## Design

```
 task done                                   push / wrap land
     |                                             |
     v                                             v
 /kit:verify capture  --->  local cache  --->  proof-asset flush  --->  R2 bucket
 (screenshot, GIF,          .kit/proof-         (upload, sha256,         <tenant>/<repo>/<slug>/<name>
  text output)              assets/<slug>/      write manifest)          lifecycle: delete after 90 days
     |                      (gitignored)              |
     v                                                v
 docs/verification/<slug>.md  <---- links + assets.json (url, sha256, bytes)
     |
     v
 push gate: text output (all behavioral) + image (visual class) + manifest entry resolves
     |
     v
 PR body: proof section with inline images (GitHub fetches the public R2 URL)
```

### 1. What each task type owes

| Task type | Visual proof | Gate level |
|---|---|---|
| UI page or component | Before and after screenshots, desktop and 400px | Hard: image required on UI paths |
| UI flow | GIF of the whole flow | Hard: same UI paths |
| Bot or chat message | Screenshot of the real message in a test channel, plus read-back text | Contract |
| CLI tool or script | Command plus real output | Hard: live since #892 |
| TUI | GIF of a session (VHS) | Contract |
| API endpoint | `curl -i` request and response | Hard: captured output |
| Data pipeline or report | Sample rows, counts, diff vs previous run; chart PNG for a report | Captured output; image by contract |
| Generated file (docx, xlsx, pptx, pdf) | First pages rendered to PNG | Contract |
| Deploy, infra, migration | Live probe output and the rollback path | Hard: stateful rule |
| Scheduled job | One real run's log tail and the monitor status | Captured output |
| LLM prompt or agent behavior | Old vs new outputs from the real models | Captured output |
| Security or config | Before and after probe, never the secret | Captured output |
| Performance | Before and after numbers | Captured output |
| Refactor, no visible change | Test recap and negative control; "no visual" | Hard: live |
| Docs only | Rendered page screenshot when published | None (inert) |

"Hard" means the push gate blocks. "Contract" means `proof-gate.sh contract` names the artifact, `/kit:verify` captures it, and review catches a miss. The gate cannot tell a bot message or a generated file from other code by path alone.

The new `visual` class: a diff that touches `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.css`, `*.html`, or an `app/`, `pages/`, `components/` path.

### 2. Time cost, kept small

| Lane | Capture |
|---|---|
| tiny | Nothing |
| normal | One screenshot of each changed screen, or the text output |
| full | The full set from the table |

- Capture runs once, at `/kit:verify` before the PR, never per commit.
- Only screens the diff touches get captured.
- Measured cost to confirm in the build: about 20 seconds per screenshot, 1 to 2 minutes per flow GIF.

### 3. Storage: R2, not git

- **Bucket:** one per Cloudflare account (tenant), named `kit-proof-assets`. The repo owner picks the tenant: `tieubao/*` uses the personal account, `dwarvesf/*` uses the Dwarves account.
- **Key:** `<repo>/<slug>/<name>.<ext>`. A re-capture under the same name overwrites, so each slug keeps only its latest image.
- **Retention:** an R2 lifecycle rule deletes objects after 90 days. The text proof stays in git forever; only the images expire.
- **Size:** convert screenshots to WebP or optimized PNG, cap 300 KB each. Cap a GIF at 2 MB.
- **Manifest:** `docs/verification/<slug>/assets.json` records url, sha256, and bytes per image. It is small text and lives in git.
- **Upload:** `bin/proof-asset put <file>` with an R2 token read through the secret ladder (1Password Connect first, Keychain cache next). No raw token on disk.

### 4. Offline (no wifi)

- Capture needs no network and no model: screenshots and terminal output come from local tools. A local-model session captures the same way.
- With no network, `proof-asset put` writes the file to the gitignored local cache `.kit/proof-assets/<slug>/` and queues it. The proof file links the future URL and the manifest marks it `pending`.
- Local review works offline: the proof file falls back to the cached copy (a relative link to the cache) for the local preview.
- Push needs the network anyway. `wrap land` runs `proof-asset flush` first: it uploads the queue, checks each sha256, and flips `pending` to `uploaded`.
- The gate refuses a `pending` entry at push, and the refusal message says to run `proof-asset flush`.

### 5. Gate changes

- `proof-ledger.sh classify` adds `visual` (UI paths, as above).
- A visual diff passes only with at least one image entry in the manifest that is `uploaded` and whose URL answers HTTP 200. A committed image in the branch still counts, so no existing proof breaks.
- Escape hatch: `[UNAVAILABLE: reason]` or an audited override, as today.

## Risks and open questions

| # | Risk or question | Proposal |
|---|---|---|
| 1 | GitHub renders a PR image only when its server can fetch the URL without credentials. A private bucket with signed URLs breaks after at most 7 days. | Public read on an unguessable key (a random 128-bit path segment), served from a custom domain. Anyone holding the URL can view the image until it expires. |
| 2 | Screenshots of sensitive repos (family-office, properties, client work) on a public URL. | A per-repo `[proof] assets = "local"` setting in `.kit.toml`: images stay in the local cache and are never uploaded. The gate accepts the local copy and the PR shows text only. Default `r2`. |
| 3 | Images expire after 90 days, so old PRs show broken images. | Accepted: the text proof stays in git. Confirm 90 days, or "latest only" with no expiry. |
| 4 | Animated WebP and MP4 may not render inline in a PR. | GIF for flows; test WebP in the first build step. |
| 5 | Which Cloudflare account holds each bucket. | Per-owner tenant, as above. Confirm. |

## Build order

1. R2 buckets, lifecycle rule, custom domain, token in 1Password. Proof: an upload, a public GET 200, and the lifecycle rule read back.
2. `bin/proof-asset put|flush` plus the manifest and offline queue. Proof: put offline (queued), flush online (uploaded, sha match).
3. Gate: the `visual` class and the manifest check. Proof: a UI diff without an image is blocked; with one it passes; the negative control goes red.
4. `/kit:verify` capture step by lane, and `proof-gate.sh contract` returning the table's artifact per task type.
5. `wrap land`: flush before the PR, images inline in the PR body.
6. Adopt the eight active repos: dotfiles, homebrew-tools, spacedown, vibedex, learning-kit, context-kit, hidden, pr-evidence-check.

## Exit criteria

- With `[proof] visual` unset, the gate, `/kit:verify` and `wrap land` behave byte for byte as before (the existing suites pass unchanged).

- A UI change in an adopted repo cannot push without an uploaded image, and its PR shows that image inline.
- A capture done offline lands in the PR after the next online `wrap land`, with no manual step.
- No proof image is committed to any repo's history.
- Objects older than 90 days are gone from the bucket.
