# coverage_map.md

Base-substrate coverage rows for `x402-regression-base`. One row per shipped planted twin. Every arXiv URL is populated from a live-fetched sourcing memo; placeholder rows are marked `[UNVERIFIED-AT-DRAFT]` until the URLs are filed.

## 1. Shipping set (six planted twins)

| ID | Class | Source | How it manifests on Base's x402 rail | What a Base seller should defend against | What the planted-twin catches |
|---|---|---|---|---|---|
| V01_Replay | Payment replay | arXiv:2605.11781 (five-class x402 protocol failure corpus) `[UNVERIFIED-AT-DRAFT, arXiv URL and section citation to be filed]` | Signed EIP-3009-shape authorization consumed by the token, replayed against the facilitator layer | Track authorization consumption keyed by the full authorization hash | Clean leg marks the hash consumed on first settle; planted leg omits the write, letting the same authorization settle N times |
| V02_ExpiryBypass | Expiry not enforced | arXiv:2605.11781 (five-class x402 protocol failure corpus) `[UNVERIFIED-AT-DRAFT]` | `validBefore` upper-bound check missing or wrong-compared | Reject `settle()` past `validBefore` | Clean leg reverts on `AuthorizationExpired`; planted leg accepts a settle two hours past the window |
| V03_NonceReuse | Narrow dedup key | arXiv:2605.11781 (five-class x402 protocol failure corpus) `[UNVERIFIED-AT-DRAFT]` | Facilitator dedups on `(from, nonce)` alone rather than the full authorization hash | Include every signed field in the dedup key | Clean leg lets two distinct authorizations with the same nonce both settle; planted leg drops the second one under the narrow key |
| V04_DoubleGrant | Reentrancy on callback | arXiv:2605.30998 (systematic security analysis of x402 payments) `[UNVERIFIED-AT-DRAFT]` | Resource callback fires before the consumption marker is written | Mark authorization consumed BEFORE the token transfer + resource callback (checks-effects-interactions) | Clean leg blocks the re-entrant second settle; planted leg lets a re-entering resource receive a second grant |
| V05_CrossDomainReplay | Stripped EIP-712 domain | novel-variant twin (not in the arXiv corpus) | EIP-712 domain-separator omits `chainId` and `verifyingContract`; a chainId=1 signature verifies on Base | Enforce full EIP-712 domain (name, version, `chainId`, `verifyingContract`) per Base's chainId (8453 mainnet / 84532 sepolia) | Clean leg rejects a stripped-domain signature; planted leg accepts it |
| V06_DelegationCap | Cumulative-cap not enforced | novel-variant twin against a Coinbase `SpendPermissionManager`-shape primitive | Manager honors an authorization whose cumulative spend within one period exceeds the granter-stated cap | Enforce `spent + amount <= allowance` per rolling period, updated atomically before the token transfer | Clean leg reverts on the cap check; planted leg permits 10x allowance spent across ten calls in one period |

## 2. Provenance discipline

- V01-V04 are class-level twins reproducing published bug classes. Attribution to the source paper authors is preserved verbatim on each row above. The exact paper section anchors are marked `[UNVERIFIED-AT-DRAFT]` and close on a live re-fetch of the arXiv pages.
- V05-V06 are novel-variant twins against synthesized minimal reference contracts (our own `X402Facilitator.sol` for V05 and our own `SpendPermissionManager.sol` for V06). They do NOT claim a specific-instance disclosure against any live Base x402 facilitator or Coinbase's production `SpendPermissionManager`; that manager enforces the invariant correctly.
- The reference-implementation shapes (coinbase/x402 protocol, Circle EIP-3009, Coinbase `SpendPermissionManager`) are preserved as pattern credit in `NOTICE`. No source is vendored under `src/`; the twin contracts are minimal reference implementations authored for CI use.

## 3. What is OUT of scope for this release

- Cross-chain / cross-VM co-mingling. Base only.
- The prompt-injection payment class from the arXiv corpus (off-chain LLM surface; no clean-planted Solidity twin without vendoring an LLM harness). Deferred to a later release.
- The privacy / transaction-graph linkability class (observability harness, not a clean/planted invariant). Deferred to a later release.
- Named-external-adopter integration receipts. This release ships the five-line YAML shape (§6 in README) and the reference facilitator; downstream adopter integration is out of scope for the initial cut.

## 4. Second-machine reproduction discipline

Every shipped clean/planted pair certifies on the operator-of-record's machine at draft. A second-machine reproduction (a second maintainer on a separate laptop) lands with the Sepolia live matrix and again with the mainnet live matrix.

## 5. Change log

- 2026-07-16: draft of the six-row coverage table. Six planted twins shipped locally. `[UNVERIFIED-AT-DRAFT]` markers on arXiv URLs pending closure via the live-fetched sourcing memo.
- `[[PENDING, Sepolia + mainnet deploys: on the reference-facilitator deploys, append a row here noting the deploy date + Basescan address + the specific tx hashes that certified the clean-and-planted matrix against the live reference facilitator.]]`
