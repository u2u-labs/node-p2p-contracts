// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../payment/libraries/LibUsageOrder.sol";

interface IUsageDepositor {
    function settleUsageToNode(
        LibUsageOrder.SettleUsageToNodeRequest calldata request
    ) external;
}
