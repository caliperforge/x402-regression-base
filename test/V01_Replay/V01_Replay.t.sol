// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {X402Facilitator, IERC20Minimal} from "src/facilitator/X402Facilitator.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

/// @notice Clean-leg twin for V01_Replay. The reference facilitator marks
/// each authorization consumed on first settle; the second settle of
/// the same authorization reverts with `AuthorizationConsumed`.
contract V01_ReplayCleanTest is Test {
    MockUSDC internal usdc;
    X402Facilitator internal facilitator;
    uint256 internal payerPk = 0xA11CE;
    address internal payer;
    address internal receiver = address(0xBEEF);

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new X402Facilitator(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        // Base mainnet chainId so the domain separator binds 8453.
        vm.chainId(8453);
    }

    function _auth(uint256 nonceSeed) internal view returns (IX402Facilitator.PaymentAuthorization memory) {
        return IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: receiver,
            value: 100e6,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: bytes32(nonceSeed),
            resourceId: keccak256("resource/A")
        });
    }

    function test_singleSettleSucceeds() public {
        IX402Facilitator.PaymentAuthorization memory a = _auth(1);
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);
        facilitator.settle(a, v, r, s);
        assertEq(usdc.balanceOf(receiver), 100e6);
    }

    function test_replayReverts() public {
        IX402Facilitator.PaymentAuthorization memory a = _auth(2);
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);
        facilitator.settle(a, v, r, s);
        vm.expectRevert(X402Facilitator.AuthorizationConsumed.selector);
        facilitator.settle(a, v, r, s);
        assertEq(usdc.balanceOf(receiver), 100e6);
    }
}
