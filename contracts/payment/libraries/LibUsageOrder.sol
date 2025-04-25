// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";
import "./LibPayment.sol";

library LibUsageOrder {
    bytes32 private constant USAGE_ORDER_TYPEHASH =
        keccak256(
            "UsageOrder(address client,uint8 tokenType,address tokenAddress,uint256 requestedSeconds,uint256 totalPrice,uint256 nonce)"
        );

    struct UsageOrder {
        address client;
        TokenType tokenType;
        address tokenAddress;
        uint256 requestedSeconds;
        uint256 totalPrice;
        uint256 nonce;
        bytes usageBillingAdminSig; 
    }

    function hash(
        UsageOrder memory usageOrder
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    USAGE_ORDER_TYPEHASH,
                    usageOrder.client,
                    usageOrder.tokenType,
                    usageOrder.tokenAddress,
                    usageOrder.requestedSeconds,
                    usageOrder.totalPrice,
                    usageOrder.nonce
                )
            );
    }
}
