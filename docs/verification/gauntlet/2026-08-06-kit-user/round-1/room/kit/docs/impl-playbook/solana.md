# Solana implementation rules

Distills the Anchor framework docs, Neodyme's Solana Security Workshop, and Helius's Solana program security guide. Solana's account model creates vulnerability classes that do not exist on EVM chains: an instruction operates on whatever accounts the caller supplies, so every account must be validated, not assumed.

## Use Anchor's account constraints, not raw account handling
- `Account<'info, T>` auto-checks the account's discriminator on deserialize, blocking "type cosplay" (treating one account type as another). `Signer<'info>` enforces the signer check. Declarative constraints (`has_one`, `owner`, `seeds`/`bump`, `close`) push validation into the account struct instead of hand-written `if` checks scattered through the instruction body. Prefer these over raw `AccountInfo` handling by default.

## The vulnerability checklist for every instruction
- Signer check: does every account that should only be actioned by its owner actually require a signature?
- Owner check: is the account's owning program verified, not just its type?
- Discriminator/type check: covered automatically by `Account<'info, T>`, but verify when dropping to `AccountInfo` for any reason.
- PDA seeds and bump: seeds must be canonical and the bump must be the canonical bump, not an attacker-supplied alternate bump that derives a different address.
- Account closing: use Anchor's `close = target` constraint rather than a hand-written close, to avoid revival attacks (the runtime only garbage-collects a zero-lamport account after the transaction completes, so a later instruction in that same transaction can refund the "closed" account and reuse it).
- Duplicate mutable accounts: Anchor 1.0+ rejects passing the same mutable account twice in one instruction by default (a real bug class: silent overwrite of the "other" account). Below 1.0, this is unenforced; check for it manually. If a program genuinely needs the same account mutable twice, it opts in explicitly with `#[account(mut, dup)]`.

## Arithmetic
- Rust's overflow checks are not on by default in release builds; they only panic in debug mode. Use `checked_add`/`checked_sub`/`checked_mul` everywhere money or supply math is involved regardless of the flag below.
- **Anchor projects**: since Anchor 0.30.0, `anchor build` hard-errors if `overflow-checks` is unset in the workspace `Cargo.toml` at all, and `anchor init` templates set `overflow-checks = true` by default. But the check only requires the key to be *present*, not `true`; an explicit `overflow-checks = false` builds fine. Verify the generated Cargo.toml actually has `overflow-checks = true` under `[profile.release]`; do not assume the default holds just because the project builds.
- **Raw `cargo-build-sbf` and Pinocchio projects get none of this.** Anchor's build-time check is Anchor tooling, not a Rust/Solana-wide guarantee. Set `overflow-checks = true` explicitly in Cargo.toml yourself; nothing will stop a build with it missing or disabled.

## Testing
- `anchor test` against a local validator is the non-negotiable minimum, not optional. Add a static-analysis pass (Sec3 X-ray, the closest Solana equivalent to Slither) before anything holding real value.

## Why this matters
- Wormhole (February 2022, $320M) is the canonical case study: a forged sysvar account bypassed signature verification because an unchecked account was trusted. It maps directly to the checklist above (owner/account validation), not to a separate oracle-trust problem.

## Sources
- [Anchor account constraints reference](https://www.anchor-lang.com/docs/references/account-constraints)
- [Anchor 0.30.0 release notes (overflow-checks requirement)](https://www.anchor-lang.com/docs/updates/release-notes/0-30-0)
- [Anchor 1.0.0 release notes (dup-account default, Solana 3.x)](https://www.anchor-lang.com/docs/updates/release-notes/1-0-0)
- [Pinocchio](https://github.com/anza-xyz/pinocchio)
- [Neodyme Solana Security Workshop](https://workshop.neodyme.io/)
- [Helius: A Hitchhiker's Guide to Solana Program Security](https://www.helius.dev/blog/a-hitchhikers-guide-to-solana-program-security)
- [Sec3 X-ray](https://github.com/sec3-product/x-ray)
- [Halborn: the Wormhole hack explained](https://www.halborn.com/blog/post/explained-the-wormhole-hack-february-2022)

Verified: 2026-08-03.
