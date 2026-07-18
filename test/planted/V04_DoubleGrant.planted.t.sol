// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {IX402ResourceCallback} from "src/facilitator/interfaces/IX402ResourceCallback.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";
import {ReenteringResource} from "test/harness/Resources.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Planted-leg reference: the interactions (transfer + callback)
/// happen BEFORE the authorization is marked consumed. A resource that
/// re-enters settle() during its callback observes `authConsumed[h] ==
/// false` and receives a second grant against the same signed authorization.
contract BrokenX402FacilitatorV04 {
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
        require(block.timestamp > auth.validAfter, "V04P: not yet valid");
        require(block.timestamp < auth.validBefore, "V04P: expired");
        bytes32 h = authHash(auth);
        require(!authConsumed[h], "V04P: consumed");

        bytes32 d = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), h));
        address signer = ecrecover(d, v, r, s);
        require(signer != address(0) && signer == auth.from, "V04P: bad sig");

        // Planted hunk: interactions before effects. Transfer + callback fire
        // before the consumption marker is written; a re-entrant resource
        // observes `authConsumed[h] == false` and can call settle() again.
        require(token.transferFrom(auth.from, auth.to, auth.value), "V04P: transfer");
        if (auth.to.code.length > 0) {
            IX402ResourceCallback(auth.to).x402Delivered(h, auth.from, auth.value, auth.resourceId);
        }
        authConsumed[h] = true;
    }
}

contract V04_DoubleGrantPlantedTest is Test {
    MockUSDC internal usdc;
    BrokenX402FacilitatorV04 internal facilitator;
    ReenteringResource internal resource;
    uint256 internal payerPk = 0xD00D;
    address internal payer;

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new BrokenX402FacilitatorV04(IERC20Minimal(address(usdc)));
        resource = new ReenteringResource();
        resource.bindFacilitator(address(facilitator));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function test_doubleGrantSurfacesInvariantViolated() public {
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
        resource.armReentry(a, v, r, s);

        facilitator.settle(a, v, r, s);

        // Invariant: exactly one grant delivered per authorized settlement.
        assertEq(
            resource.deliveries(),
            1,
            "INVARIANT VIOLATED V04_DoubleGrant: >1 service grant delivered for a single signed authorization"
        );
    }
}
