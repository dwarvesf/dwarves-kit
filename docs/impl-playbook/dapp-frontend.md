# dApp frontend integration rules

Distills the current EVM/Solana wallet-connection stack plus wallet-vendor security guidance (MetaMask, Phantom). A dApp frontend is a major real-world phishing surface: users get tricked into signing malicious transactions because the frontend, or the wallet, shows misleading or blind data.

## Connection stack
- EVM: `viem` (typed, tree-shakeable) plus `wagmi` (React hooks) is the current default for new work. `ethers.js` is still actively maintained (6.17.0, monthly release cadence) and remains a reasonable choice; don't treat it as legacy or displaced, just a different tradeoff. Reown's `@reown/appkit` (WalletConnect Inc. rebranded to Reown in 2024) is the standard SDK for multi-wallet connection without exposing keys to the browser; `@walletconnect/modal` is npm-deprecated, migrate any reference to it.
- Solana: for new work, prefer `@solana/kit` + `@solana/kit-plugin-wallet` (Wallet Standard discovery, no per-wallet adapter package needed) per Solana's own docs. `@solana/wallet-adapter-react` (`ConnectionProvider` -> `WalletProvider` -> `WalletModalProvider`) still works and still ships releases, now under the `anza-xyz` org rather than `solana-labs`, but it is legacy/maintenance-mode for existing apps; don't start a new dApp on it.

## Prefer typed signing over blind signing
- Request `eth_signTypedData_v4` (EIP-712 typed structured data) over `personal_sign`/raw `eth_sign` wherever possible. Typed signing binds the signature to chain ID, contract address, and version, and lets the wallet render named fields instead of an opaque hex blob the user cannot verify. Treat a raw-hex signature request in your own flow as a design smell to fix, not accept.
- For a custom signing UI (anything beyond what the wallet renders natively), describe the request with ERC-7730 clear signing, a JSON descriptor format the Ethereum Foundation launched 2026-05-12 with MetaMask, Reown, Ledger, and others, so users see plain-language terms ("Swap 1.5 ETH for 3,200 USDC") instead of raw calldata.

## EIP-7702 delegation phishing
- EIP-7702 lets an EOA delegate its execution to a contract. Phishing kits abuse this: a look-alike site gets the user to sign a delegation (an authorization-list transaction) pointing at a generic drainer contract, which then sweeps the wallet on the next incoming funds. Public research (Wintermute) found over 97% of mainnet EIP-7702 delegations in the sample pointed at the same reused sweeper bytecode family, and losses from this pattern have run into the millions. Treat a delegation-signing request the same as a private-key handover: never build a flow that signs one blind, and surface the delegate contract's address in your own UI so the user can verify the target before approving.

## Approval scoping
- Request the exact token allowance needed for the immediate action. Never request `type(uint256).max` (unlimited approval) as a default; nearly every dApp does, and it is the single most-abused permission in wallet-drainer attacks. Surface the requested scope in the dApp's own UI before the wallet prompt appears; do not rely on the wallet alone to explain it.

## Known exploit patterns to design against
- Blind-signature phishing: a look-alike site requests a signature that looks harmless and replays it elsewhere.
- Malicious `setApprovalForAll`/unlimited-approval requests disguised as routine actions.
- Address poisoning: a lookalike address seeded into the user's transaction history to bait a copy-paste mistake.
- Permit/Permit2 phishing: an EIP-712 typed signature can itself grant a token allowance gaslessly; typed signing improves legibility, it does not by itself make a signature request safe.

## The one absolute
- Never build a UI that asks a user to paste a seed phrase or private key. No exception, no "just this once for debugging."

## Sources
- [EIP-712 spec](https://eips.ethereum.org/EIPS/eip-712)
- [MetaMask: Sign Data guide](https://docs.metamask.io/metamask-connect/evm/guides/sign-data/)
- [MetaMask: what is a malicious token approval](https://support.metamask.io/stay-safe/safety-in-web3/what-is-a-malicious-token-approval/)
- [Phantom: security at Phantom (transaction simulation)](https://phantom.com/learn/blog/security-at-phantom)
- [Penny Wise and Pound Foolish: an empirical study of ERC-20 approvals](https://ar5iv.labs.arxiv.org/html/2207.01790)
- [Solana docs: Migrating to Kit](https://solana.com/docs/frontend/web3-compat)
- [Reown docs (WalletConnect rebrand, AppKit)](https://docs.reown.com/)
- [Ethereum Foundation: Clear Signing (ERC-7730) announcement](https://blog.ethereum.org/2026/05/12/clear-signing-announcement)
- [The CrimeEnjoyor epidemic: EIP-7702 delegation phishing](https://dev.to/ohmygod/the-crimeenjoyor-epidemic-how-eip-7702-delegation-phishing-drained-450k-wallets-and-how-to-e2g)

Verified: 2026-08-03.
