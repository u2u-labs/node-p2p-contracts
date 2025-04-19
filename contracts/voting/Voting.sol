// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "contracts/interfaces/INodesStorage.sol";

contract Voting is Ownable {
    INodesStorage public nodeStorage;

    uint256 public quorumThresholdPercent;

    mapping(address => uint256) public reportedNodes;
    mapping(address => mapping(address => bool)) public reportLogs;

    event NodeReported(
        address indexed reporter,
        address indexed reportedNode,
        uint256 totalReports
    );
    event NodeRemoved(address indexed removedNode);
    event QuorumThresholdUpdated(uint256 newThresholdPercent);

    constructor(address _nodeStorageAddress, uint256 _initialQuorumPercent) {
        require(_nodeStorageAddress != address(0), "Invalid storage address");
        require(
            _initialQuorumPercent > 0 && _initialQuorumPercent <= 100,
            "Invalid quorum %"
        );

        nodeStorage = INodesStorage(_nodeStorageAddress);
        quorumThresholdPercent = _initialQuorumPercent;
    }

    modifier onlyNode() {
        require(nodeStorage.isValidNode(msg.sender), "Not a valid node");
        _;
    }

    function reportNode(address nodeAddress) external onlyNode {
        require(
            nodeStorage.isValidNode(nodeAddress),
            "Target is not a valid node"
        );
        require(!reportLogs[msg.sender][nodeAddress], "Node already reported");

        reportLogs[msg.sender][nodeAddress] = true;
        reportedNodes[nodeAddress] += 1;

        emit NodeReported(msg.sender, nodeAddress, reportedNodes[nodeAddress]);

        uint256 totalValidNodes = nodeStorage.getTotalValidNodes();
        uint256 quorumCount = (totalValidNodes * quorumThresholdPercent + 99) /
            100;

        if (reportedNodes[nodeAddress] >= quorumCount) {
            nodeStorage.removeNode(nodeAddress);
            emit NodeRemoved(nodeAddress);
        }
    }

    function updateQuorumThreshold(uint256 newPercent) external onlyOwner {
        require(newPercent > 0 && newPercent <= 100, "Invalid quorum percent");
        quorumThresholdPercent = newPercent;

        emit QuorumThresholdUpdated(newPercent);
    }

    function updateNodeStorage(address newNodeStorage) external onlyOwner {
        require(newNodeStorage != address(0), "Invalid address");
        nodeStorage = INodesStorage(newNodeStorage);
    }
}
