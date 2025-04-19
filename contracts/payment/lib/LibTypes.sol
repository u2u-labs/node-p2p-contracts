// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum TokenType {
    Native,
    ERC20
}

struct Payment {
    TokenType tokenType;
    address tokenAddress;
}

struct DataPlan {
    uint256 unitPrice; //price per GB used
}

struct Bill {
    address node;
    address client;
    DataPlan dataPlan;
    Payment payment;
    uint256 usedAmount;
    uint256 nonce;
}
