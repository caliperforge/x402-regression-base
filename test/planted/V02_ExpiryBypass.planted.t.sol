// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Planted-leg reference: the `validBefore` upper-bound check is
/// removed. The `validAfter` lower-bound check remains, so authorizations
/// stamped for the future still cannot settle early, but authorizations
/// past their window continue to settle indefinitely.
contract BrokenX402FacilitatorV02 {
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
        require(block.timestamp > auth.validAfter, "V02P: not yet valid");
        // Planted hunk: the `require(block.timestamp < auth.validBefore, ...)`
        // check is removed. Every other invariant remains, so a settle past
        // the payer's stated expiry succeeds.

        bytes32 h = authHash(auth);
        require(!authConsumed[h], "V02P: consumed");

        bytes32 d = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), h));
        address signer = ecrecover(d, v, r, s);
        require(signer != address(0) && signer == auth.from, "V02P: bad sig");

        authConsumed[h] = true;
        require(token.transferFrom(auth.from, auth.to, auth.value), "V02P: transfer");
    }
}

contract V02_ExpiryBypassPlantedTest is Test {
    MockUSDC internal usdc;
    BrokenX402FacilitatorV02 internal facilitator;
    uint256 internal payerPk = 0xB0B;
    address internal payer;
    address internal receiver = address(0xBEEF);

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new BrokenX402FacilitatorV02(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function test_expiryBypassSurfacesInvariantViolated() public {
        uint256 vb = block.timestamp + 1 hours;
        IX402Facilitator.PaymentAuthorization memory a = IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: receiver,
            value: 100e6,
            validAfter: 0,
            validBefore: vb,
            nonce: bytes32(uint256(1)),
            resourceId: keccak256("resource/A")
        });
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);

        // Warp two hours past validBefore.
        vm.warp(vb + 2 hours);
        facilitator.settle(a, v, r, s);

        // Invariant: an authorization stamped `validBefore = t` must not
        // settle at time `t + 2h`. The receiver balance would be zero if
        // the facilitator honored the payer's expiry.
        assertEq(
            usdc.balanceOf(receiver),
            0,
            "INVARIANT VIOLATED V02_ExpiryBypass: settled past validBefore window"
        );
    }
}
