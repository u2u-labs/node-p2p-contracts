# NodesStorage

The `NodesStorage` smart contract manages a registry of valid node addresses that are authorized to perform certain actions within a decentralized system (such as creating or redeeming session receipts). It is owned and controlled by an admin (typically a DAO or system operator) and is designed to be used by other contracts via the `INodesStorage` interface.

---

## Overview

This contract maintains:

- A list of currently valid node addresses.
- The ability to add or remove nodes via the contract owner.
- Efficient tracking of which addresses have ever been added or removed.
- Compatibility with other contracts via the `INodesStorage` interface.

---

## Constructor

### `constructor(address[] memory initialNodes)`

Initializes the contract with an optional list of valid node addresses.

---

## Core Features

- **Validation:** Check whether a node address is currently valid.
- **Listing:** Get all currently valid nodes or their count.
- **Management:** Only the owner can add or remove node addresses.
- **Replay-safe List:** Maintains complete node list without duplicates.

---

## Key Functions

### `function isValidNode(address node) external view override returns (bool)`

Returns `true` if the address is currently recognized as a valid node.

---

### `function getValidNodes() external view override returns (address[] memory validNodes)`

Returns a dynamic array of all currently valid node addresses.

---

### `function getTotalValidNodes() external view override returns (uint256 total)`

Returns the total number of currently valid nodes.

---

### `function addNodes(address[] calldata newNodes) external onlyOwner`

Adds one or more new nodes. Ignores duplicates. Re-activates previously removed nodes.

---

### `function removeNode(address node) external onlyOwner`

Removes a node from the valid list. Marks it as removed and emits a `NodeRemoved` event.

---

## Internal Functions

### `_addNode(address node)`

Internal helper for adding a node. Prevents re-adding already active nodes. Handles previously removed nodes appropriately.

---

## State Variables

- `mapping(address => bool) _isNode`: Tracks whether a node is currently valid.
- `mapping(address => bool) _removedNodes`: Tracks whether a node was ever removed.
- `mapping(address => bool) _nodeExistsInList`: Ensures a node appears only once in the `_nodeList`.
- `address[] _nodeList`: Contains a complete historical list of added node addresses.

---

## Events

- `NodeAdded(address indexed node)`: Emitted when a node is successfully added.
- `NodeRemoved(address indexed node)`: Emitted when a node is removed.

---

## Access Control

- Only the contract owner (via OpenZeppelin's `Ownable`) can add or remove nodes.
- View functions are publicly accessible.

---

## Interface

Implements: [`INodesStorage`](./contracts/interfaces/INodesStorage.sol)

Used by other contracts (e.g. `SessionReceipt`) to check node validity.
