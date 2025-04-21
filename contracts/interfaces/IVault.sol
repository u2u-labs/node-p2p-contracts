// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVault {
    function transfer(
        address from,
        address to,
        address tokenAddress,
        uint256 amount
    ) external returns (bool);
}
