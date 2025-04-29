// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";
import "./LibPayment.sol";

library LibSessionReceipt {
    enum SessionReceiptStatus {
        EMPTY,
        PENDING,
        CONFIRMED,
        PAID
    }

    bytes32 private constant SESSION_RECEIPT_TYPEHASH =
        keccak256(
            "SessionReceipt(address client,address node,uint256 totalSecondsServed,uint8 tokenType,address tokenAddress,uint8 status,uint256 nonce)"
        );

    struct SessionReceipt {
        address client;
        address node;
        uint256 totalSecondsServed;
        TokenType tokenType;
        address tokenAddress;
        SessionReceiptStatus status;
        uint256 nonce;
    }

    function hash(
        SessionReceipt memory sessionReceipt
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SESSION_RECEIPT_TYPEHASH,
                    sessionReceipt.client,
                    sessionReceipt.node,
                    sessionReceipt.totalSecondsServed,
                    sessionReceipt.tokenType,
                    sessionReceipt.tokenAddress,
                    sessionReceipt.status,
                    sessionReceipt.nonce
                )
            );
    }
}
