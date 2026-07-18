// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SpendPermissionManager} from "src/facilitator/SpendPermissionManager.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Planted-leg reference: the cumulative-cap counter is never
/// updated. Each call checks only the single-call `amount <= allowance`,
/// so a spender can move balance past the cap up to the token allowance
/// across unbounded calls within one period.
contract BrokenSpendPermissionManagerV06 {
    struct SpendPermission {
        address account;
        address spender;
        address token;
        uint256 allowance;
        uint256 period;
        uint256 start;
        uint256 end;
        uint256 salt;
    }

    function digest(SpendPermission memory p) public pure returns (bytes32) {
        bytes32 h = keccak256(
            abi.encode(
                p.account, p.spender, p.token, p.allowance, p.period, p.start, p.end, p.salt
            )
        );
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function spend(SpendPermission calldata p, uint8 v, bytes32 r, bytes32 s, uint256 amount)
        external
    {
        require(msg.sender == p.spender, "V06P: not spender");
        require(block.timestamp >= p.start && block.timestamp <= p.end, "V06P: window");
        require(amount > 0 && amount <= p.allowance, "V06P: amount");

        bytes32 d = digest(p);
        address signer = ecrecover(d, v, r, s);
        require(signer == p.account && signer != address(0), "V06P: bad sig");

        // Planted hunk: no cumulative counter. Every call passes the
        // single-call amount check and the transfer succeeds.
        require(IERC20Minimal(p.token).transferFrom(p.account, p.spender, amount), "V06P: transfer");
    }
}

contract V06_DelegationCapPlantedTest is Test {
    MockUSDC internal usdc;
    BrokenSpendPermissionManagerV06 internal manager;
    uint256 internal accountPk = 0xF00F;
    address internal account;
    address internal spender = address(0xC0FFEE);

    function setUp() public {
        usdc = new MockUSDC();
        manager = new BrokenSpendPermissionManagerV06();
        account = vm.addr(accountPk);
        usdc.mint(account, 1_000_000e6);
        vm.prank(account);
        usdc.approve(address(manager), type(uint256).max);
        vm.chainId(8453);
    }

    function test_uncappedSpendSurfacesInvariantViolated() public {
        BrokenSpendPermissionManagerV06.SpendPermission memory p = BrokenSpendPermissionManagerV06
            .SpendPermission({
            account: account,
            spender: spender,
            token: address(usdc),
            allowance: 100e6,
            period: 1 days,
            start: block.timestamp - 1,
            end: block.timestamp + 30 days,
            salt: 1
        });
        bytes32 d = manager.digest(p);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(accountPk, d);

        // Ten calls of 100e6 each within one period. Under the cap invariant,
        // the second call would revert.
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(spender);
            manager.spend(p, v, r, s, 100e6);
        }

        // Invariant: cumulative spend within one period must not exceed
        // `allowance`. The planted manager silently permits 10x allowance.
        assertLe(
            usdc.balanceOf(spender),
            p.allowance,
            "INVARIANT VIOLATED V06_DelegationCap: cumulative spend within one period exceeded allowance"
        );
    }
}
