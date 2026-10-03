# Implementation notes: SPEC-385 visual proof upgrade

The delta from `docs/specs/SPEC-385-visual-proof-upgrade.md`. Decisions, changes and open questions only.

## Decisions

- **T0 uses wrangler's own login, not a scoped token.** No stored Cloudflare token in 1Password has R2 permission. The Air's wrangler login can create buckets and put objects. `asset_token_ref` stays empty for now.
- **Domains:** `proof.han.ws` (personal account, zone han.ws) and `proof.d.foundation` (Dwarves account, zone d.foundation). Both are R2 custom domains, so reads are public and listing is off.
- **Spec round 1 changed the shape:** the gate no longer adds a `visual` class to `classify`; it computes the image rule inside `check`. The gate ignores manifest `status` and trusts only a fetch plus hash on a URL under the operator's base, so flush never has to commit.

## Open questions

- **The Mini cannot upload yet:** its wrangler is not logged in. Captures made there queue until a flush runs on the Air. Fix: mint an R2-scoped API token, store it in 1Password, and set `asset_token_ref`.
- **Implementation workers:** Sonnet is at its weekly limit until Oct 8, so Devin builds T1 to T4 and Opus reviews.
