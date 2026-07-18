// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {X402Facilitator, IERC20Minimal} from "src/facilitator/X402Facilitator.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";
import {BenignResource} from "test/harness/Resources.sol";

/// @notice Clean-leg twin for V04_DoubleGrant. The reference facilitator
/// marks the authorization consumed BEFORE calling the resource's
/// `x402Delivered()` callback (checks-effects-interactions). A resource
/// that tries to re-enter settle() during its callback hits
/// `AuthorizationConsumed` on the second call.
contract V04_DoubleGrantCleanTest is Test {
    MockUSDC internal usdc;
    X402Facilitator internal facilitator;
    BenignResource internal resource;
    uint256 internal payerPk = 0xD00D;
    address internal payer;

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new X402Facilitator(IERC20Minimal(address(usdc)));
        resource = new BenignResource();
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function test_singleGrantPerSettle() public {
        IX402Facilitator.PaymentAuthorization memory a = IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: address(resource),
            value: 100e6,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: bytes32(uint256(1)),
            resourceId: keccak256("resource/A")
        });
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);
        facilitator.settle(a, v, r, s);
        assertEq(resource.deliveries(), 1);
        assertEq(usdc.balanceOf(address(resource)), 100e6);
    }
}
