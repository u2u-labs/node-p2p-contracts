// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";

library LibSessionReceipt {
    enum SessionReceiptStatus {
        EMPTY,
        PENDING,
        CONFIRMED,
        PAID
    }

    struct SessionReceipt {
        address client;
        address node;
        uint256 totalSecondsServed;
        TokenType tokenType;
        address tokenAddress;
        SessionReceiptStatus status;
        uint256 nonce;
    }
}
