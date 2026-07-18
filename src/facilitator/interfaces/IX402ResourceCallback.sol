// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @title IX402ResourceCallback  -  optional post-settle hook on the resource contract
/// @notice x402 facilitators often notify the resource / receiver contract
/// after a successful settle so the resource can deliver its response
/// (unlock content, mint a receipt, kick a downstream flow). The hook
/// is optional per the x402 spec; the reference facilitator here calls
/// the hook only if `code.length > 0` at the `to` address. See V04
/// (CEI ordering: nonce MUST be marked used before the callback so a
/// re-entrant resource cannot receive a second grant against the same
/// authorization).
interface IX402ResourceCallback {
    /// @notice Called by the facilitator once per successful settle. Return
    /// value is not read; a revert propagates upward.
    function x402Delivered(bytes32 authHash, address from, uint256 value, bytes32 resourceId)
        external;
}
