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

## 🚨 Node Reporting Flow

### Step 1: A node reports another node

```solidity
voting.reportNode(reportedNodeAddress); // called by a valid node
```

- Validations:
  - Caller is a valid node.
  - Target is also currently valid.
  - Caller has not already reported this node.
  - Node is not already scheduled for removal.

- Effects:
  - Increments `reportedNodes[reportedNodeAddress]`.
  - Logs the report to prevent duplicates.

### Step 2: Quorum check

- After each report, the contract checks if the number of reports crosses the quorum threshold.
- If quorum is reached:
  - A removal timestamp is calculated using `block.timestamp + removalDelay`.
  - `pendingRemovals[reportedNodeAddress]` is set.
  - Event `NodeScheduledForRemoval` is emitted.

---

## 🕒 Finalizing Node Removal

After the removal delay has passed:

### Step 3: Any valid node can finalize

```solidity
voting.finalizeRemoval(reportedNodeAddress);
```

- Validations:
  - Caller is a valid node.
  - The node is in `pendingRemovals`.
  - The current time exceeds the scheduled removal time.

- Effects:
  - Removes the node from `NodesStorage`.
  - Deletes all tracking data for that node (`reportedNodes`, `pendingRemovals`).
  - Emits `NodeRemoved`.

---

## ✅ Example Walkthrough

| Step | Action | Actor | Outcome |
|------|--------|-------|---------|
| 1 | Add 5 nodes | Owner | Nodes added to NodesStorage |
| 2 | Set quorum to 60% | Owner | Requires 3 reports |
| 3 | Node A reports Node X | Node A | Report count = 1 |
| 4 | Node B reports Node X | Node B | Report count = 2 |
| 5 | Node C reports Node X | Node C | Quorum met → scheduled for removal |
| 6 | Wait for delay (e.g., 1 hour) | — | — |
| 7 | Node D finalizes removal | Node D | Node X is removed |


---
