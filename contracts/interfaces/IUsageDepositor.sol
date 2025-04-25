// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUsageDepositor {
    function settleUsageToNode(
        address client,
        address node,
        uint256 totalServedUsage,
        address tokenAddress,
        uint256 totalToken
    ) external;
}
