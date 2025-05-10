# Voting

## Overview

This contract facilitates decentralized node moderation by allowing active nodes to report and vote to remove misbehaving peers. It supports setting a quorum threshold and delay before final removal, ensuring fairness and protection against misuse.

---

## State Variables

- `address public nodeStorage`: The address of the external `NodesStorage` contract.
- `uint256 public quorumThresholdPercent`: The required percent of node votes to trigger a removal.
- `uint256 public removalDelay`: Delay after quorum before a node can be removed.
- `mapping(address => uint256) public reportedNodes`: Count of reports for each node.
- `mapping(address => mapping(address => bool)) public reportLogs`: Tracks who reported whom.
- `mapping(address => PendingRemoval) public pendingRemovals`: Scheduled node removals.

### Structs

```solidity
struct PendingRemoval {
    uint256 timestamp;
    bool exists;
}
```

---

## Events

- `NodeReported(address reporter, address reportedNode, uint256 totalReports)`
- `NodeScheduledForRemoval(address node, uint256 executeAfter)`
- `NodeRemoved(address removedNode)`
- `QuorumThresholdUpdated(uint256 newThresholdPercent)`
- `RemovalDelayUpdated(uint256 newDelay)`
- `NodeStorageUpdated(address newStorage)`

---

## Modifiers

- `onlyNode`: Restricts access to only those addresses currently listed as valid nodes in `INodesStorage`.

---

## Constructor

```solidity
constructor(uint256 _initialQuorumPercent)
```

- Initializes the contract with a required quorum threshold percent.
- Ensures the threshold is between 1 and 100 (inclusive).

---

## External Functions

### setNodesStorage

```solidity
function setNodesStorage(address _nodeStorageAddress) external onlyOwner
```

- Sets the address of the external `NodesStorage` contract.

---

### reportNode

```solidity
function reportNode(address nodeAddress) external onlyNode
```

- Allows a node to report another valid node.
- Tracks reporter and counts total reports.
- If quorum is reached, schedules the node for removal after a delay.

---

### finalizeRemoval

```solidity
function finalizeRemoval(address nodeAddress) external onlyNode
```

- Finalizes a node’s removal after the required delay.
- Must be called by a valid node.
- Calls `removeNode` on the `INodesStorage` contract.

---

### updateQuorumThreshold

```solidity
function updateQuorumThreshold(uint256 newPercent) external onlyOwner
```

- Updates the quorum percent for node removal.
- Must be between 1 and 100.

---

### updateRemovalDelay

```solidity
function updateRemovalDelay(uint256 newDelay) external onlyOwner
```

- Updates the delay (in seconds) before a scheduled removal can be finalized.
- Minimum delay is 1 minute.

---
