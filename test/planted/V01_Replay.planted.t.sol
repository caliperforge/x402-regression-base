// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {IX402ResourceCallback} from "src/facilitator/interfaces/IX402ResourceCallback.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Planted-leg reference: single-hunk mutation of the clean facilitator.
/// The nonce-consumption write is removed; every other invariant stays.
/// The same signed authorization settles N times, moving the payer's
/// balance N * value to the receiver.
contract BrokenX402FacilitatorV01 {
    bytes32 internal constant PAYMENT_AUTH_TYPEHASH = keccak256(
        "PaymentAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,bytes32 resourceId)"
    );
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant NAME_HASH = keccak256(bytes("x402-facilitator"));
    bytes32 internal constant VERSION_HASH = keccak256(bytes("1"));

    IERC20Minimal public immutable token;
    mapping(bytes32 => bool) public authConsumed;

    constructor(IERC20Minimal _token) {
        token = _token;
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)
            )
        );
    }

    function authHash(IX402Facilitator.PaymentAuthorization memory a) public pure returns (bytes32) {
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

    function digest(IX402Facilitator.PaymentAuthorization memory a) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), authHash(a)));
    }

    function settle(
        IX402Facilitator.PaymentAuthorization calldata auth,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp > auth.validAfter, "V01P: not yet valid");
        require(block.timestamp < auth.validBefore, "V01P: expired");
        bytes32 h = authHash(auth);

        // Planted hunk: the `authConsumed[h] = true` write is removed. Every other
        // invariant remains, so signature and window checks still pass, but the
        // same authorization can be replayed until the payer's allowance runs out.
        // (The clean facilitator writes `_authConsumed[h] = true` at this line.)

        bytes32 d = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), h));
        address signer = ecrecover(d, v, r, s);
        require(signer != address(0) && signer == auth.from, "V01P: bad sig");

        require(token.transferFrom(auth.from, auth.to, auth.value), "V01P: transfer");
    }
}

contract V01_ReplayPlantedTest is Test {
    MockUSDC internal usdc;
    BrokenX402FacilitatorV01 internal facilitator;
    uint256 internal payerPk = 0xA11CE;
    address internal payer;
    address internal receiver = address(0xBEEF);

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new BrokenX402FacilitatorV01(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function test_replaySurfacesInvariantViolated() public {
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
        facilitator.settle(a, v, r, s);
        facilitator.settle(a, v, r, s);

        // Invariant: the payer authorized 100e6 exactly once; receiver balance
        // must equal 100e6. The planted hunk lets the same auth settle
        // repeatedly, driving balance past 100e6.
        assertEq(
            usdc.balanceOf(receiver),
            100e6,
            "INVARIANT VIOLATED V01_Replay: same signed authorization settled >1 time"
        );
    }
}
