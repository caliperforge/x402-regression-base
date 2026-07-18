// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

/// @notice Shared signing helper for the Base x402 planted-twin tests. Every
/// clean-leg + planted-leg test signs authorizations through this helper
/// so the test-side digest math stays byte-identical to the on-chain
/// digest math in `X402Facilitator.digest()` / `SpendPermissionManager.digest()`.
library AuthSigner {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sign(uint256 pk, bytes32 digest)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        (v, r, s) = vm.sign(pk, digest);
    }
}
