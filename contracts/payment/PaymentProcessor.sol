// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./lib/LibTypes.sol";

abstract contract PaymentProcessor {
    using SafeERC20 for IERC20;

    function processPayment(
        address payer,
        address receiver,
        Payment memory payment,
        uint256 amount
    ) internal {
        if (payment.tokenType == TokenType.Native) {
            require(msg.value == amount, "Incorrect native token amount");
            payable(receiver).transfer(amount);
        } else {
            IERC20(payment.tokenAddress).safeTransferFrom(
                payer,
                receiver,
                amount
            );
        }
    }
}
