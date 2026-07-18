// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";
import {IX402ResourceCallback} from "src/facilitator/interfaces/IX402ResourceCallback.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title X402Facilitator  -  reference x402 facilitator (Base substrate)
/// @notice Reference implementation of an x402 payment facilitator for Base.
/// Consumes a signed `PaymentAuthorization` from a payer, verifies the
/// facilitator's own EIP-712 typed-data signature against the Base
/// chainId, marks the authorization consumed, calls the token's
/// `transferFrom`, and finally notifies the resource contract via
/// `IX402ResourceCallback` if code lives at the destination.
///
/// This is the CLEAN facilitator: all six planted-twin defenses are ON.
/// Each planted twin under `test/planted/` reproduces one of the six
/// bug classes by declaring an inline `BrokenX402Facilitator<Variant>`
/// contract with a single-hunk mutation. The clean / planted delta is
/// confined to one branch per variant so §4b review reads the delta at
/// a glance.
///
/// Base substrate notes:
///
/// - EIP-712 domain binds `chainId` (`block.chainid`) and
///   `verifyingContract` (`address(this)`). On Base mainnet this is
///   8453; on Base Sepolia this is 84532. V05 (CrossDomainReplay)
///   asserts a signature intended for chainId=1 does not settle on Base.
/// - The struct field naming matches EIP-3009 `TransferWithAuthorization`
///   verbatim (`from`, `to`, `value`, `validAfter`, `validBefore`,
///   `nonce`) with one facilitator-specific field (`resourceId`) for
///   routing. M2 can swap in a full EIP-3009 layer over Circle's Base
///   USDC without changing the struct.
/// - The facilitator does NOT vendor the coinbase/x402 SDK. The
///   `NOTICE` file reserves the SDK-vendoring slot; when the SDK is
///   vendored at M2, the shape here stays the same.
///
/// Delegation-cap invariant (V06) is enforced by a separate
/// `SpendPermissionManager` contract per Coinbase's own primitive on Base.
/// The facilitator does not itself cap; the manager does.
contract X402Facilitator is IX402Facilitator {
    bytes32 internal constant PAYMENT_AUTH_TYPEHASH = keccak256(
        "PaymentAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,bytes32 resourceId)"
    );
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant NAME_HASH = keccak256(bytes("x402-facilitator"));
    bytes32 internal constant VERSION_HASH = keccak256(bytes("1"));

    IERC20Minimal public immutable token;
    mapping(bytes32 => bool) internal _authConsumed;

    error InvalidSignature();
    error AuthorizationExpired();
    error AuthorizationNotYetValid();
    error AuthorizationConsumed();
    error TransferFailed();

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

    function authHash(PaymentAuthorization memory a) public pure returns (bytes32) {
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

    function digest(PaymentAuthorization memory a) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), authHash(a)));
    }

    function authConsumed(bytes32 h) external view returns (bool) {
        return _authConsumed[h];
    }

    function settle(PaymentAuthorization calldata auth, uint8 v, bytes32 r, bytes32 s) external {
        // V02 defense: window bounds enforced.
        if (block.timestamp <= auth.validAfter) revert AuthorizationNotYetValid();
        if (block.timestamp >= auth.validBefore) revert AuthorizationExpired();

        // V03 defense: dedup key is the full authorization hash (all fields),
        // not (from, nonce). Two authorizations with the same nonce but
        // different `to` or `value` produce distinct keys, but neither can
        // settle a second time because the full-hash marks the exact one used.
        bytes32 h = authHash(auth);
        if (_authConsumed[h]) revert AuthorizationConsumed();

        // V05 defense: DOMAIN_SEPARATOR binds block.chainid + address(this),
        // so a chainId=1 signature does not verify on Base.
        bytes32 d = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), h));
        address signer = ecrecover(d, v, r, s);
        if (signer == address(0) || signer != auth.from) revert InvalidSignature();

        // V01 + V04 defense: mark consumed BEFORE the external calls
        // (checks-effects-interactions). A re-entrant resource cannot
        // receive a second grant against the same authorization because
        // the second settle() reverts at the `_authConsumed[h]` check.
        _authConsumed[h] = true;

        if (!token.transferFrom(auth.from, auth.to, auth.value)) revert TransferFailed();

        // Optional post-settle hook. The facilitator calls the hook only if
        // code lives at the destination; EOA receivers pay no gas overhead.
        if (auth.to.code.length > 0) {
            IX402ResourceCallback(auth.to).x402Delivered(h, auth.from, auth.value, auth.resourceId);
        }

        emit Settled(h, auth.from, auth.to, auth.value);
    }
}
