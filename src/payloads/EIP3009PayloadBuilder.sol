// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IX402Facilitator} from "src/facilitator/interfaces/IX402Facilitator.sol";

/// @title EIP3009PayloadBuilder  -  helpers for signing test payment authorizations
/// @notice Small helper library that constructs the digest an x402 payer
/// signs when authorizing a settle. The digest binds the facilitator's
/// own EIP-712 domain (name, version, `chainId`, `verifyingContract`) so
/// tests can prove the V05 CrossDomainReplay defense holds against a
/// chainId-mismatched signature.
///
/// Struct field naming matches EIP-3009 `TransferWithAuthorization`
/// verbatim so M2 can swap in a full EIP-3009 layer over Circle's Base
/// USDC without changing the payload builder API.
library EIP3009PayloadBuilder {
    bytes32 internal constant PAYMENT_AUTH_TYPEHASH = keccak256(
        "PaymentAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,bytes32 resourceId)"
    );
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant NAME_HASH = keccak256(bytes("x402-facilitator"));
    bytes32 internal constant VERSION_HASH = keccak256(bytes("1"));

    /// @notice Constructs the digest for a `PaymentAuthorization` signed
    /// against a facilitator on the given `chainId`. `verifyingContract`
    /// is the facilitator's own address. On Base mainnet `chainId` is
    /// 8453; on Base Sepolia it is 84532.
    function digest(
        IX402Facilitator.PaymentAuthorization memory auth,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                PAYMENT_AUTH_TYPEHASH,
                auth.from,
                auth.to,
                auth.value,
                auth.validAfter,
                auth.validBefore,
                auth.nonce,
                auth.resourceId
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
