// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";

library LibPayment {
    bytes32 private constant PAYMENT_TYPEHASH =
        keccak256(
            "Payment(uint8 tokenType,address tokenAddress,uint256 unitPrice)"
        );

    struct Payment {
        TokenType tokenType;
        address tokenAddress;
        uint256 unitPrice;
    }

    function hash(
        Payment memory payment
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PAYMENT_TYPEHASH,
                    payment.tokenType,
                    payment.tokenAddress,
                    payment.unitPrice
                )
            );
    }
}
