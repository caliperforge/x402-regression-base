// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {X402Facilitator} from "src/facilitator/X402Facilitator.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";

/// @title SettleSmoke  -  live-network clean-leg settle probe
/// @notice One clean-leg settle against a deployed `X402Facilitator`. Signs
/// a `PaymentAuthorization` payload with the operator key against the
/// facilitator's own EIP-712 domain (chainId bound to `block.chainid`,
/// `verifyingContract` bound to the facilitator address), pre-approves
/// the facilitator on the underlying token, and calls `settle()`. Emits
/// the tx hash the surrounding runner captures for the Basescan record.
///
/// Two required env inputs:
///
///   X402_FACILITATOR  address of the deployed facilitator (from
///                     DeployFacilitator's stdout).
///   X402_USDC         address of the token to settle against (canonical
///                     Base USDC on mainnet; MockUSDC address on Sepolia).
///
/// Optional:
///
///   X402_SETTLE_VALUE settle amount in token base units. Default 10000
///                     (= 1 cent USDC at 6 decimals). Kept nominal so
///                     mainnet W6 stays under the §6 cost envelope.
///   X402_RECEIVER     receiver address. Defaults to the operator address
///                     (self-settle keeps Sepolia funding self-contained).
///
/// The operator is BOTH payer and (default) receiver. On MockUSDC we
/// mint to the operator first; on canonical USDC the operator must
/// already hold the settle value. Runner is responsible for either.
contract SettleSmoke is Script {
    function run() external {
        address facilitatorAddr = vm.envAddress("X402_FACILITATOR");
        address tokenAddr = vm.envAddress("X402_USDC");
        uint256 value = _envOrDefault("X402_SETTLE_VALUE", 10_000);

        X402Facilitator facilitator = X402Facilitator(facilitatorAddr);

        uint256 operatorPk = vm.envUint("OPERATOR_KEY_UINT");
        address operator = vm.addr(operatorPk);
        address receiver = _envOrDefaultAddr("X402_RECEIVER", operator);

        IX402Facilitator.PaymentAuthorization memory auth = IX402Facilitator.PaymentAuthorization({
            from: operator,
            to: receiver,
            value: value,
            validAfter: 0,
            validBefore: block.timestamp + 30 minutes,
            nonce: keccak256(abi.encodePacked(block.chainid, block.timestamp, operator, "w2-smoke")),
            resourceId: keccak256("resource/w2-smoke")
        });

        bytes32 digest = facilitator.digest(auth);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, digest);

        vm.startBroadcast(operatorPk);

        // MockUSDC path: mint + approve. Canonical USDC path: caller
        // pre-funded + pre-approved out-of-band (see ci/live_sepolia.sh).
        // Under vm.startBroadcast, the low-level .call inside _prepMockUsdc
        // becomes a real broadcast tx; on canonical USDC that tx reverts
        // ("caller is not a minter") which aborts the whole broadcast
        // pre-simulation. X402_SKIP_MINT=1 lets the mainnet runner skip it.
        if (!_envOrDefaultBool("X402_SKIP_MINT", false)) {
            _prepMockUsdc(tokenAddr, operator, value);
        }

        MockUSDC(tokenAddr).approve(facilitatorAddr, value);

        facilitator.settle(auth, v, r, s);

        vm.stopBroadcast();

        console2.log("X402_SMOKE_AUTH_HASH=", vm.toString(facilitator.authHash(auth)));
        console2.log("X402_SMOKE_OPERATOR=", operator);
        console2.log("X402_SMOKE_RECEIVER=", receiver);
        console2.log("X402_SMOKE_VALUE=", value);
    }

    /// @dev Best-effort MockUSDC mint. Uses a raw call so the script does
    /// not revert against canonical USDC (which has no `mint(address,uint256)`);
    /// in that case the operator must be pre-funded by the runner.
    function _prepMockUsdc(address tokenAddr, address to, uint256 amount) internal {
        (bool ok,) = tokenAddr.call(abi.encodeWithSignature("mint(address,uint256)", to, amount));
        // Deliberate no-revert: canonical USDC returns false or reverts;
        // either way the settle() below still runs, and if the balance is
        // absent the underlying transferFrom will revert with a clear
        // reason string that the runner captures.
        ok;
    }

    function _envOrDefault(string memory key, uint256 defaultVal) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return defaultVal;
        }
    }

    function _envOrDefaultAddr(string memory key, address defaultVal) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return defaultVal;
        }
    }

    function _envOrDefaultBool(string memory key, bool defaultVal) internal view returns (bool) {
        try vm.envBool(key) returns (bool v) {
            return v;
        } catch {
            return defaultVal;
        }
    }
}
