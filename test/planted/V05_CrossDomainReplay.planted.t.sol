// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {MockUSDC} from "src/facilitator/mocks/MockUSDC.sol";
import {AuthSigner} from "test/harness/AuthSigner.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Planted-leg reference: the EIP-712 domain separator omits both
/// `chainId` and `verifyingContract`. A signature stamped for chainId=1
/// with the same `name` + `version` verifies against every facilitator
/// on every chain, including the Base-mainnet-deployed instance.
contract BrokenX402FacilitatorV05 {
    bytes32 internal constant PAYMENT_AUTH_TYPEHASH = keccak256(
        "PaymentAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,bytes32 resourceId)"
    );
    // Planted hunk: stripped domain typehash omits chainId + verifyingContract.
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH_STRIPPED = keccak256(
        "EIP712Domain(string name,string version)"
    );
    bytes32 internal constant NAME_HASH = keccak256(bytes("x402-facilitator"));
    bytes32 internal constant VERSION_HASH = keccak256(bytes("1"));

    IERC20Minimal public immutable token;
    mapping(bytes32 => bool) public authConsumed;

    constructor(IERC20Minimal _token) {
        token = _token;
    }

    function DOMAIN_SEPARATOR() public pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH_STRIPPED, NAME_HASH, VERSION_HASH));
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

    function digest(IX402Facilitator.PaymentAuthorization memory a) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), authHash(a)));
    }

    function settle(
        IX402Facilitator.PaymentAuthorization calldata auth,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp > auth.validAfter, "V05P: not yet valid");
        require(block.timestamp < auth.validBefore, "V05P: expired");
        bytes32 h = authHash(auth);
        require(!authConsumed[h], "V05P: consumed");

        bytes32 d = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), h));
        address signer = ecrecover(d, v, r, s);
        require(signer != address(0) && signer == auth.from, "V05P: bad sig");

        authConsumed[h] = true;
        require(token.transferFrom(auth.from, auth.to, auth.value), "V05P: transfer");
    }
}

contract V05_CrossDomainReplayPlantedTest is Test {
    MockUSDC internal usdc;
    BrokenX402FacilitatorV05 internal facilitator;
    uint256 internal payerPk = 0xE00E;
    address internal payer;
    address internal receiver = address(0xBEEF);

    function setUp() public {
        usdc = new MockUSDC();
        facilitator = new BrokenX402FacilitatorV05(IERC20Minimal(address(usdc)));
        payer = vm.addr(payerPk);
        usdc.mint(payer, 1_000_000e6);
        vm.prank(payer);
        usdc.approve(address(facilitator), type(uint256).max);
        vm.chainId(8453);
    }

    function test_stripledDomainSurfacesInvariantViolated() public {
        IX402Facilitator.PaymentAuthorization memory a = IX402Facilitator.PaymentAuthorization({
            from: payer,
            to: receiver,
            value: 100e6,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: bytes32(uint256(1)),
            resourceId: keccak256("resource/A")
        });

        // Payer signs against the stripped domain. On the clean facilitator
        // a stripped-domain signature would not verify (the clean domain
        // binds chainId + verifyingContract); here it does.
        bytes32 d = facilitator.digest(a);
        (uint8 v, bytes32 r, bytes32 s) = AuthSigner.sign(payerPk, d);

        // Simulate: this signature was produced on chainId=1. Warp chainId
        // to Base mainnet and settle - the stripped domain accepts it.
        vm.chainId(8453);
        facilitator.settle(a, v, r, s);

        // Invariant: a signature that omits chainId + verifyingContract from
        // the domain should not settle on Base. Receiver balance would be zero
        // if the facilitator bound the domain per EIP-712.
        assertEq(
            usdc.balanceOf(receiver),
            0,
            "INVARIANT VIOLATED V05_CrossDomainReplay: stripped domain accepted cross-chain signature on Base"
        );
    }
}
