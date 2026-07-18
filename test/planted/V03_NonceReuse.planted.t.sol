// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Planted-leg reference: dedup key is narrowed from the full
/// authorization hash to `(from, nonce)`. Two distinct authorizations
/// with the same `(from, nonce)` but different `(to, value, resourceId)`
/// conflate under the narrow key: the first settle marks the pair used,
/// the second reverts even though it is a distinct signed authorization.
contract BrokenX402FacilitatorV03 {
    bytes32 internal constant PAYMENT_AUTH_TYPEHASH = keccak256(
        "PaymentAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,bytes32 resourceId)"
    );
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant NAME_HASH = keccak256(bytes("x402-facilitator"));
    bytes32 internal constant VERSION_HASH = keccak256(bytes("1"));

    IERC20Minimal public immutable token;
    // Planted hunk: narrow key `(from, nonce)` instead of full-auth-hash.
    mapping(address => mapping(bytes32 => bool)) public usedByFromNonce;

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
        require(block.timestamp > auth.validAfter, "V03P: not yet valid");
        require(block.timestamp < auth.validBefore, "V03P: expired");
        // Planted hunk: narrow-key dedup. Every other invariant remains.
        require(!usedByFromNonce[auth.from][auth.nonce], "V03P: consumed");

        bytes32 h = authHash(auth);
        bytes32 d = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), h));
        address signer = ecrecover(d, v, r, s);
        require(signer != address(0) && signer == auth.from, "V03P: bad sig");

        usedByFromNonce[auth.from][auth.nonce] = true;
        require(token.transferFrom(auth.from, auth.to, auth.value), "V03P: transfer");
    }
}

contract V03_NonceReusePlantedTest is Test {
    MockUSDC internal usdc;
    BrokenX402FacilitatorV03 internal facilitator;
    uint256 internal payerPk = 0xC001;
    address internal payer;
    address internal receiverA = address(0xAAAA);
    address internal receiverB = address(0xBBBB);

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new BrokenX402FacilitatorV03(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function _authAt(bytes32 nonce, address to, uint256 value, bytes32 resourceId)
        internal
        view
        returns (IX402Facilitator.PaymentAuthorization memory)
    {
        return IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: to,
            value: value,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: nonce,
            resourceId: resourceId
        });
    }

    function test_narrowKeyConflatesDistinctAuthsSurfacesInvariantViolated() public {
        IX402Facilitator.PaymentAuthorization memory a = _authAt(bytes32(uint256(1)), receiverA, 100e6, keccak256("resource/A"));
        IX402Facilitator.PaymentAuthorization memory b = _authAt(bytes32(uint256(1)), receiverB, 250e6, keccak256("resource/B"));

        bytes32 da = facilitator.digest(a);
        (uint8 va, bytes32 ra, bytes32 sa) = AuthSigner.sign(payerPk, da);
        facilitator.settle(a, va, ra, sa);

        // Second distinct authorization signed by the same payer with the same
        // nonce. The narrow-key dedup rejects it even though the signed
        // struct differs in `to`, `value`, and `resourceId`.
        bytes32 db = facilitator.digest(b);
        (uint8 vb, bytes32 rb, bytes32 sb) = AuthSigner.sign(payerPk, db);
        (bool ok,) = address(facilitator).call(
            abi.encodeWithSelector(BrokenX402FacilitatorV03.settle.selector, b, vb, rb, sb)
        );

        // Invariant: distinct signed authorizations from the same payer that
        // reuse a nonce value in unrelated `to` / `value` / `resourceId`
        // fields must remain independent. The narrow-key facilitator drops
        // the second one silently.
        assertTrue(
            ok,
            "INVARIANT VIOLATED V03_NonceReuse: distinct authorization rejected under narrow (from, nonce) dedup"
        );
    }
}
