// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct SpendingLimit {
    uint256 maxPerSession;
    uint256 maxPerPeriod;
    uint256 periodStart;
    uint256 spentInPeriod;
    bool initialized;
}

enum TokenType {
    NATIVE,
    ERC20
}
