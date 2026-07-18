// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {IX402ResourceCallback} from "src/facilitator/interfaces/IX402ResourceCallback.sol";

/// @notice Benign resource. Logs the number of x402Delivered() callbacks
/// received via a public counter. Used by V04 clean-leg tests.
contract BenignResource is IX402ResourceCallback {
    uint256 public deliveries;

    function x402Delivered(bytes32, address, uint256, bytes32) external {
        deliveries += 1;
    }
}

/// @notice Resource that attempts to re-enter the facilitator's settle()
/// during its first callback. Used by V04 planted-leg to reproduce the
/// interactions-before-effects race. When the facilitator marks the
/// authorization consumed AFTER calling the callback, this resource can
/// call settle() again with the same signed authorization inside the
/// first callback, and a second grant lands before the state update.
contract ReenteringResource is IX402ResourceCallback {
    // The facilitator address is set post-deploy to allow the resource
    // to be constructed against either the clean or the broken facilitator.
    address public facilitator;
    uint256 public deliveries;
    bool internal _reentered;

    // Cached auth + sig for the reentrant call.
    IX402Facilitator.PaymentAuthorization internal _auth;
    uint8 internal _v;
    bytes32 internal _r;
    bytes32 internal _s;

    function bindFacilitator(address f) external {
        facilitator = f;
    }

    function armReentry(
        IX402Facilitator.PaymentAuthorization calldata auth,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _auth = auth;
        _v = v;
        _r = r;
        _s = s;
    }

    function x402Delivered(bytes32, address, uint256, bytes32) external {
        deliveries += 1;
        if (!_reentered) {
            _reentered = true;
            IX402Facilitator(facilitator).settle(_auth, _v, _r, _s);
        }
    }
}
