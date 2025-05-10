// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "contracts/interfaces/INodesStorage.sol";

contract Voting is Ownable {
    address public nodeStorage;

    uint256 public quorumThresholdPercent;
    uint256 public removalDelay = 1 days;

    mapping(address => uint256) public reportedNodes;
    mapping(address => mapping(address => bool)) public reportLogs;

    struct PendingRemoval {
        uint256 timestamp;
        bool exists;
    }

    mapping(address => PendingRemoval) public pendingRemovals;

    event NodeReported(
        address indexed reporter,
        address indexed reportedNode,
        uint256 totalReports
    );
    event NodeScheduledForRemoval(address indexed node, uint256 executeAfter);
    event NodeRemoved(address indexed removedNode);
    event QuorumThresholdUpdated(uint256 newThresholdPercent);
    event RemovalDelayUpdated(uint256 newDelay);
    event NodeStorageUpdated(address newStorage);

    modifier onlyNode() {
        require(
            INodesStorage(nodeStorage).isValidNode(msg.sender),
            "Not a valid node"
        );
        _;
    }

    /**
     * @param _initialQuorumPercent The quorum percentage required to schedule node removal.
     */
    constructor(uint256 _initialQuorumPercent) {
        require(
            _initialQuorumPercent > 0 && _initialQuorumPercent <= 100,
            "Invalid quorum %"
        );
        quorumThresholdPercent = _initialQuorumPercent;
    }

    /**
     * @notice Sets the NodesStorage contract address.
     * @param _nodeStorageAddress The address of the NodesStorage contract.
     */
    function setNodesStorage(address _nodeStorageAddress) external onlyOwner {
        require(_nodeStorageAddress != address(0), "Invalid storage address");
        nodeStorage = _nodeStorageAddress;
        emit NodeStorageUpdated(_nodeStorageAddress);
    }

    /**
     * @notice Allows a node to report another node.
     * @param nodeAddress The address of the node being reported.
     */
    function reportNode(address nodeAddress) external onlyNode {
        require(
            INodesStorage(nodeStorage).isValidNode(nodeAddress),
            "Target is not a valid node"
        );
        require(!reportLogs[msg.sender][nodeAddress], "Node already reported");
        require(
            !pendingRemovals[nodeAddress].exists,
            "Already scheduled for removal"
        );

        reportLogs[msg.sender][nodeAddress] = true;
        reportedNodes[nodeAddress] += 1;

        emit NodeReported(msg.sender, nodeAddress, reportedNodes[nodeAddress]);

        uint256 totalValidNodes = INodesStorage(nodeStorage)
            .getTotalValidNodes();
        uint256 quorumCount = (totalValidNodes * quorumThresholdPercent + 99) /
            100;

        if (reportedNodes[nodeAddress] >= quorumCount) {
            uint256 removalTime = block.timestamp + removalDelay;
            pendingRemovals[nodeAddress] = PendingRemoval(removalTime, true);
            emit NodeScheduledForRemoval(nodeAddress, removalTime);
        }
    }

    /**
     * @notice Finalizes removal of a node after quorum and delay.
     * @dev Can only be called by another valid node.
     * @param nodeAddress The address of the node to remove.
     */
    function finalizeRemoval(address nodeAddress) external onlyNode {
        PendingRemoval storage removal = pendingRemovals[nodeAddress];
        require(removal.exists, "Not scheduled for removal");
        require(
            block.timestamp >= removal.timestamp,
            "Removal delay not passed"
        );

        delete pendingRemovals[nodeAddress];
        delete reportedNodes[nodeAddress];
        INodesStorage(nodeStorage).removeNode(nodeAddress);

        emit NodeRemoved(nodeAddress);
    }

    /**
     * @notice Updates the quorum threshold percentage.
     * @param newPercent The new quorum threshold percentage.
     */
    function updateQuorumThreshold(uint256 newPercent) external onlyOwner {
        require(newPercent > 0 && newPercent <= 100, "Invalid quorum percent");
        quorumThresholdPercent = newPercent;
        emit QuorumThresholdUpdated(newPercent);
    }

    /**
     * @notice Updates the delay period before node removal can be finalized.
     * @param newDelay New delay in seconds.
     */
    function updateRemovalDelay(uint256 newDelay) external onlyOwner {
        require(newDelay >= 1 minutes, "Delay too short");
        removalDelay = newDelay;
        emit RemovalDelayUpdated(newDelay);
    }
}
