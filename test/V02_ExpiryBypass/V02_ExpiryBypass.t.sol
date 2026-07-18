// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {X402Facilitator, IERC20Minimal} from "src/facilitator/X402Facilitator.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

/// @notice Clean-leg twin for V02_ExpiryBypass. The reference facilitator
/// rejects any settle() where `block.timestamp >= validBefore` (or
/// `block.timestamp <= validAfter`), so an authorization signed for a
/// one-hour window cannot settle two hours later.
contract V02_ExpiryBypassCleanTest is Test {
    MockUSDC internal usdc;
    X402Facilitator internal facilitator;
    uint256 internal payerPk = 0xB0B;
    address internal payer;
    address internal receiver = address(0xBEEF);

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new X402Facilitator(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function _auth(uint256 nonceSeed, uint256 validBefore)
        internal
        view
        returns (IX402Facilitator.PaymentAuthorization memory)
    {
        return IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: receiver,
            value: 100e6,
            validAfter: 0,
            validBefore: validBefore,
            nonce: bytes32(nonceSeed),
            resourceId: keccak256("resource/A")
        });
    }

    function test_settleInsideWindowSucceeds() public {
        IX402Facilitator.PaymentAuthorization memory a = _auth(1, block.timestamp + 1 hours);
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);
        facilitator.settle(a, v, r, s);
        assertEq(usdc.balanceOf(receiver), 100e6);
    }

    function test_settleAfterValidBeforeReverts() public {
        uint256 vb = block.timestamp + 1 hours;
        IX402Facilitator.PaymentAuthorization memory a = _auth(2, vb);
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);

        // Warp past validBefore.
        vm.warp(vb + 1);
        vm.expectRevert(X402Facilitator.AuthorizationExpired.selector);
        facilitator.settle(a, v, r, s);
        assertEq(usdc.balanceOf(receiver), 0);
    }
}
