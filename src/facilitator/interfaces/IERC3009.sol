// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @title IERC3009  -  minimal EIP-3009 `TransferWithAuthorization` interface
/// @notice Circle's canonical Base USDC (`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`)
/// implements EIP-3009. An x402 facilitator on Base consumes signed
/// `TransferWithAuthorization` messages and calls this entry point to move
/// the payer's USDC. The struct field naming here matches EIP-3009 verbatim
/// so the payload builders in `src/payloads/EIP3009PayloadBuilder.sol` map
/// one-to-one against a Base mainnet or Sepolia USDC deployment.
///
/// Reference: EIP-3009, `transferWithAuthorization`. The full spec at
/// eips.ethereum.org/EIPS/eip-3009.
interface IERC3009 {
    /// @notice Execute a transfer covered by a signed EIP-3009 authorization.
    /// @dev The signature is verified against the token's own EIP-712 domain
    /// separator (Circle's USDC bakes `name`, `version`, `chainId`, and
    /// `verifyingContract` into the domain). The nonce is opaque to the
    /// token; the caller (facilitator) tracks nonce consumption for its
    /// own dedup semantics per this repo's V01 / V03 twins.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice The token's own nonce-consumption tracker for EIP-3009 auths.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
