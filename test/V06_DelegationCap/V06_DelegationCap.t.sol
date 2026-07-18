// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SpendPermissionManager} from "src/facilitator/SpendPermissionManager.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

/// @notice Clean-leg twin for V06_DelegationCap. The reference
/// `SpendPermissionManager` enforces `spent + amount <= allowance` per
/// rolling `period` and persists the cumulative counter before every
/// token transfer. A spender that tries to move more than `allowance`
/// within one period reverts on the cap check.
contract V06_DelegationCapCleanTest is Test {
    MockUSDC internal usdc;
    SpendPermissionManager internal manager;
    uint256 internal accountPk = 0xF00F;
    address internal account;
    address internal spender = address(0xC0FFEE);

    function setUp() public {
        usdc = new MockUSDC();
        manager = new SpendPermissionManager();
        account = vm.addr(accountPk);
        usdc.mint(account, 1_000_000e6);
        vm.prank(account);
        usdc.approve(address(manager), type(uint256).max);
        vm.chainId(8453);
    }

    function _permit() internal view returns (SpendPermissionManager.SpendPermission memory) {
        return SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: address(usdc),
            allowance: 100e6,
            period: 1 days,
            start: block.timestamp - 1,
            end: block.timestamp + 30 days,
            salt: 1
        });
    }

    function test_spendUpToAllowanceSucceeds() public {
        SpendPermissionManager.SpendPermission memory p = _permit();
        bytes32 d = manager.digest(p);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(accountPk, d);
        vm.prank(spender);
        manager.spend(p, v, r, s, 100e6);
        assertEq(usdc.balanceOf(spender), 100e6);
    }

    function test_spendPastAllowanceReverts() public {
        SpendPermissionManager.SpendPermission memory p = _permit();
        bytes32 d = manager.digest(p);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(accountPk, d);
        vm.prank(spender);
        manager.spend(p, v, r, s, 60e6);
        vm.prank(spender);
        vm.expectRevert(bytes("SPM: cap"));
        manager.spend(p, v, r, s, 60e6);
        assertEq(usdc.balanceOf(spender), 60e6);
    }
}
