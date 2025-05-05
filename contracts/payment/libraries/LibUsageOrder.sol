// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";
import "./LibPayment.sol";

library LibUsageOrder {
    struct UsageOrder {
        TokenType tokenType;
        address tokenAddress;
        uint256 requestedSeconds;
    }
}
