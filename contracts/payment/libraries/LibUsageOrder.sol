// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";

library LibUsageOrder {
    struct UsageOrder {
        TokenType tokenType;
        address tokenAddress;
        uint256 requestedBytes;
    }
    struct SettleUsageToNodeRequest {
        address client;
        address node;
        uint256 totalServedBytes;
        address tokenAddress;
    }
}
