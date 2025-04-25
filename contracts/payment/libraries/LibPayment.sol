// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";

library LibPayment {
    bytes32 private constant PAYMENT_TYPEHASH =
        keccak256("Payment(address tokenAddress, uin256 pricePerSecond)");

    struct Payment {
        address tokenAddress;
        uint256 pricePerSecond;
    }

    function hash(Payment memory payment) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PAYMENT_TYPEHASH,
                    payment.tokenAddress,
                    payment.pricePerSecond
                )
            );
    }
}
