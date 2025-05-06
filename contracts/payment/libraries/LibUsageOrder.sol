// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";

library LibUsageOrder {
    struct UsageOrder {
        TokenType tokenType;
        address tokenAddress;
        uint256 requestedSeconds;
    }
    struct SettleUsageToNodeRequest {
        address client;
        address node;
        uint256 totalServedUsage;
        address tokenAddress;
        uint256 nonce;
    }
}
