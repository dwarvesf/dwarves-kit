# Solidity implementation rules

Distills ConsenSys Smart Contract Best Practices, OpenZeppelin Contracts, and Slither. A smart contract bug is usually unrecoverable once deployed: there is no patching a live contract without a pre-planned upgrade path, and funds lost to an exploit are typically gone for good.

## Never hand-roll what OpenZeppelin already audited
- Use OpenZeppelin's `ERC20`/`ERC721`, `AccessControl`/`Ownable`, and a reentrancy guard instead of reimplementing token or access-control logic. Using the audited library is itself a security control, not a style preference. For chains on Cancun or later, use `ReentrancyGuardTransient` (`nonReentrant`, added v5.1, built on EIP-1153 transient storage): OpenZeppelin's own source now marks the storage-based `ReentrancyGuard` "Deprecated, will be removed in v6.0". Keep the storage-based guard only for pre-Cancun chains or upgradeable proxies (no upgradeable version of the transient variant exists yet).

## Reentrancy
- Checks-effects-interactions: validate, then update state, then make any external call, in that order. The DAO hack (2016, roughly $60M drained) is the canonical case for what happens when a contract calls out before updating its own state.
- A transient-storage lock (`TSTORE`/`TLOAD`, EIP-1153) must be explicitly cleared at the end of the call frame. Transient storage persists for the whole transaction, not just the current call, so a lock left set silently blocks every later call in the same tx, a composability break rather than a revert you'd notice in isolation. This is also part of why the transient guard is preferred post-Cancun: `TSTORE` is usable below the 2,300 gas stipend where `SSTORE` is not.

## Arithmetic
- Solidity 0.8+ reverts on overflow/underflow by default. Any `unchecked{}` block disables that check locally and reintroduces the pre-0.8 bug class. Treat every `unchecked{}` block as a flagged, individually justified exception, never a default reached for gas savings alone.

## Access control
- Every state-changing function has an explicit role or owner gate. Maintain a checklist mapping each state-changing function to its intended caller; a missing gate is a top real-world loss category.

## External calls and known attack classes
- Check the return value of every external call. An unchecked failed `send`/`call` is treated as success by default.
- `.transfer()`/`.send()`: solc 0.8.31+ emits a deprecation warning on both, ahead of removal in the 0.9.0 breaking release (their fixed 2,300 gas stipend no longer reliably prevents reentrancy at current gas costs anyway). Use `.call{value: ...}("")` with an explicit success check, backed by checks-effects-interactions or a reentrancy guard, instead.
- Front-running/MEV: assume transaction ordering is visible and can be front-run. Do not rely on submission order for correctness.
- Oracle manipulation: a price read from a single on-chain source, especially via flash loan, is a manipulable input, not ground truth.

## Upgradeability
- A proxy pattern (transparent or UUPS) introduces a storage-layout-collision risk between proxy and implementation. Use OpenZeppelin's Upgrades tooling to validate storage layout compatibility on every upgrade; a silent layout mismatch corrupts state permanently, no attacker required.

## Tooling
- Slither clean, or every finding explicitly triaged with a written reason, before any deploy. This is a mandatory gate, not optional linting.
- Foundry (`forge`) is the default test framework: native Solidity tests, fast fuzzing, the tool most security researchers and major DeFi protocols actually use. Hardhat is the fallback when the project needs deep JS/TS tooling integration; Hardhat 3's Rust-based execution engine (EDR) narrowed most of the historical speed gap (no official head-to-head benchmark exists, but the older "Foundry is 5-10x faster" reports predate this rewrite), so pick Hardhat for ecosystem fit, not because Foundry has a large performance edge left to justify it.
- A contract holding real value beyond personal-project scale is the point to consider Certora or an external audit, not before.

## Sources
- [ConsenSys Smart Contract Best Practices](https://consensysdiligence.github.io/smart-contract-best-practices/) (archived, no longer actively maintained)
- [Smart Contract Security Field Guide](https://scsfg.io/) (successor, curated by the same Diligence engineer)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)
- [OpenZeppelin ReentrancyGuard.sol source (deprecation notice)](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol)
- [OpenZeppelin ReentrancyGuardTransient.sol source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol)
- [Slither (Trail of Bits)](https://github.com/crytic/slither)
- [Solidity 0.8.0 Breaking Changes](https://docs.soliditylang.org/en/latest/080-breaking-changes.html)
- [Solidity 0.8.31 Release Announcement](https://soliditylang.org/blog/2025/12/03/solidity-0.8.31-release-announcement/)
- [OpenZeppelin Proxy Upgrade Pattern](https://docs.openzeppelin.com/upgrades-plugins/proxies)
- [Foundry](https://book.getfoundry.sh/)
- [Nomic Foundation: Rust-powered Hardhat](https://blog.nomic.foundation/rust-powered-hardhat-present-future/)

Verified: 2026-08-03.
