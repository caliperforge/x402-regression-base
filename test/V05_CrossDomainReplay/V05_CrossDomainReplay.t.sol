// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {X402Facilitator, IERC20Minimal} from "src/facilitator/X402Facilitator.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

/// @notice Clean-leg twin for V05_CrossDomainReplay. The reference facilitator
/// binds `block.chainid` and `address(this)` into the EIP-712 domain
/// separator. A signature produced for chainId=1 (Ethereum mainnet) does
/// not verify on Base mainnet (chainId=8453) or Sepolia (84532).
contract V05_CrossDomainReplayCleanTest is Test {
    MockUSDC internal usdc;
    X402Facilitator internal facilitator;
    uint256 internal payerPk = 0xE00E;
    address internal payer;
    address internal receiver = address(0xBEEF);

    // Recomputes the digest against a caller-supplied chainId. Used to
    // produce a signature "intended for chainId=1" and then submit it to
    // the Base-mainnet facilitator.
    bytes32 internal constant PAYMENT_AUTH_TYPEHASH = keccak256(
        "PaymentAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,bytes32 resourceId)"
    );
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant NAME_HASH = keccak256(bytes("x402-facilitator"));
    bytes32 internal constant VERSION_HASH = keccak256(bytes("1"));

    function _structHash(IX402Facilitator.PaymentAuthorization memory a) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PAYMENT_AUTH_TYPEHASH,
                a.from,
                a.to,
                a.value,
                a.validAfter,
                a.validBefore,
                a.nonce,
                a.resourceId
            )
        );
    }

    function _digestFor(
        IX402Facilitator.PaymentAuthorization memory a,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract)
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, _structHash(a)));
    }

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new X402Facilitator(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function test_baseChainSignatureSettles() public {
        IX402Facilitator.PaymentAuthorization memory a = IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: receiver,
            value: 100e6,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: bytes32(uint256(1)),
            resourceId: keccak256("resource/A")
        });
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);
        facilitator.settle(a, v, r, s);
        assertEq(usdc.balanceOf(receiver), 100e6);
    }

    function test_ethMainnetSignatureRejected() public {
        IX402Facilitator.PaymentAuthorization memory a = IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: receiver,
            value: 100e6,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: bytes32(uint256(2)),
            resourceId: keccak256("resource/A")
        });
        // Payer signs the digest as if the domain's chainId were 1 (Ethereum mainnet).
        bytes32 wrongDomainDigest = _digestFor(a, 1, address(facilitator));
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, wrongDomainDigest);
        vm.expectRevert(X402Facilitator.InvalidSignature.selector);
        facilitator.settle(a, v, r, s);
        assertEq(usdc.balanceOf(receiver), 0);
    }
}
