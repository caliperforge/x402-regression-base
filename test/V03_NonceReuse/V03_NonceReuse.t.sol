// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {X402Facilitator, IERC20Minimal} from "src/facilitator/X402Facilitator.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

/// @notice Clean-leg twin for V03_NonceReuse. The reference facilitator dedups
/// on the full authorization hash (every signed field), so two distinct
/// authorizations that happen to share a `nonce` value but differ in any
/// other field (`value`, `to`, `resourceId`, `validBefore`) hash to
/// distinct keys and both settle. The dedup key is `keccak256(abi.encode(auth))`,
/// not `(from, nonce)`.
contract V03_NonceReuseCleanTest is Test {
    MockUSDC internal usdc;
    X402Facilitator internal facilitator;
    uint256 internal payerPk = 0xC001;
    address internal payer;
    address internal receiverA = address(0xAAAA);
    address internal receiverB = address(0xBBBB);

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new X402Facilitator(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function _authAt(bytes32 nonce, address to, uint256 value, bytes32 resourceId)
        internal
        view
        returns (IX402Facilitator.PaymentAuthorization memory)
    {
        return IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: to,
            value: value,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: nonce,
            resourceId: resourceId
        });
    }

    function _settle(IX402Facilitator.PaymentAuthorization memory a) internal {
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);
        facilitator.settle(a, v, r, s);
    }

    function test_sameNonceDifferentAuthsBothSettle() public {
        // Two authorizations. Same `from` + `nonce`; distinct `to`, `value`, `resourceId`.
        IX402Facilitator.PaymentAuthorization memory a = _authAt(bytes32(uint256(1)), receiverA, 100e6, keccak256("resource/A"));
        IX402Facilitator.PaymentAuthorization memory b = _authAt(bytes32(uint256(1)), receiverB, 250e6, keccak256("resource/B"));

        _settle(a);
        _settle(b);
        assertEq(usdc.balanceOf(receiverA), 100e6);
        assertEq(usdc.balanceOf(receiverB), 250e6);
    }
}
