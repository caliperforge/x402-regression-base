// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @title IX402Facilitator  -  reference x402 facilitator interface (Base substrate)
/// @notice The x402 protocol asks a facilitator to settle a signed payment
/// authorization from a payer to a resource / receiver. On Base, the
/// underlying transfer primitive is EIP-3009 on Circle's USDC. This
/// interface encodes the shape our reference facilitator implements
/// and the shape the planted-twin CI matrix asserts against.
interface IX402Facilitator {
    /// @notice A single x402 payment authorization consumed by `settle()`.
    /// @dev Field naming intentionally matches EIP-3009 `TransferWithAuthorization`:
    /// `from` is the payer, `to` is the resource / receiver, `value` is the
    /// USDC amount (6-decimal), `validAfter` and `validBefore` bound the
    /// settlement window, and `nonce` is a 32-byte opaque nonce chosen by
    /// the payer. `resourceId` is a facilitator-side hint (routing / receipt)
    /// and is bound into the facilitator's own EIP-712 typed-data domain
    /// separately from the token's own signature check.
    struct PaymentAuthorization {
        address from;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
        bytes32 resourceId;
    }

    event Settled(bytes32 indexed authHash, address indexed from, address indexed to, uint256 value);

    /// @notice Settle a signed authorization. The `v/r/s` args are the payer's
    /// EIP-3009 signature over the token's own EIP-712 typed-data domain
    /// (Circle's USDC domain), not over the facilitator's domain. The
    /// facilitator layers its own dedup, expiry, and delegation-cap
    /// invariants on top of the token's transfer.
    function settle(PaymentAuthorization calldata auth, uint8 v, bytes32 r, bytes32 s) external;

    /// @notice Whether an authorization has been consumed. Dedup key is the
    /// full-auth-hash: `keccak256(abi.encode(auth))`. See V01_Replay + V03_NonceReuse.
    function authConsumed(bytes32 authHash) external view returns (bool);
}
