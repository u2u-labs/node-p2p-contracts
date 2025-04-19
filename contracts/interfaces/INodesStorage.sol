// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INodesStorage {
    function addNodes(address[] calldata _nodeAddresses) external;

    function removeNode(address nodeAddress) external;

    function getValidNodes() external view returns (address[] memory);

    function getTotalValidNodes() external view returns (uint256);

    function isValidNode(address nodeAddress) external view returns (bool);
}
