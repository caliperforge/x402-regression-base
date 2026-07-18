// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {X402Facilitator, IERC20Minimal} from "src/facilitator/X402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";

/// @title DeployFacilitator  -  Base-substrate reference x402 facilitator deploy
/// @notice Deploys `X402Facilitator` (and, for Sepolia, a `MockUSDC` when no
/// canonical USDC address is supplied). Broadcasts under the operator key
/// supplied via `--private-key` on the forge script CLI; captures the
/// deployed contract addresses to stdout so `ci/live_sepolia.sh` can
/// forward them to the Basescan record and the settle script.
///
/// Runtime shape (both Sepolia + mainnet share this script; the calling
/// runner decides the target chain via `--rpc-url`):
///
///   forge script script/DeployFacilitator.s.sol:DeployFacilitator \
///       --rpc-url "$RPC_URL" \
///       --private-key "$OPERATOR_KEY" \
///       --broadcast \
///       --verify \
///       --etherscan-api-key "$BASESCAN_API_KEY"
///
/// Env inputs (all optional):
///
///   X402_USDC       explicit token address (canonical Base USDC on mainnet:
///                   0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913). If unset,
///                   deploys `MockUSDC` (Sepolia path).
///
/// Outputs (stdout, one per line, prefixed for the runner's grep):
///
///   X402_FACILITATOR=<address>
///   X402_USDC_DEPLOYED=<address>
contract DeployFacilitator is Script {
    function run() external {
        // Operator address derived by forge from --private-key; balance +
        // gas paid by that key. No vm.envUint("PRIVATE_KEY") here so the
        // key never lands in a Forge trace variable.
        vm.startBroadcast();

        address tokenAddr = _resolveToken();

        X402Facilitator facilitator = new X402Facilitator(IERC20Minimal(tokenAddr));

        vm.stopBroadcast();

        console2.log("X402_FACILITATOR=", address(facilitator));
        console2.log("X402_USDC_DEPLOYED=", tokenAddr);
        console2.log("X402_CHAINID=", block.chainid);
    }

    function _resolveToken() internal returns (address tokenAddr) {
        try vm.envAddress("X402_USDC") returns (address canonical) {
            require(canonical != address(0), "X402_USDC must be non-zero");
            require(canonical.code.length > 0, "X402_USDC must have deployed code");
            return canonical;
        } catch {
            // Fresh MockUSDC on Sepolia paths; not used on mainnet (M1 spec
            // §2.2 stage 2 requires canonical Coinbase-issued Base USDC).
            MockUSDC usdc = new MockUSDC();
            return address(usdc);
        }
    }
}
