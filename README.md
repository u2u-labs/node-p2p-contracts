# Node P2P Contracts

This repository contains the contracts for the Node P2P project:

- [Node P2P Contracts](./contracts)

## Deploy contract

- Run: npx hardhat run scripts/deploy.ts --network <your_network>

---

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

---

# Usage Depositor & Session Receipt Contracts

Two core smart contracts for a decentralized usage-based payment system:

- `UsageDepositor.sol`: Handles token deposits from clients in exchange for usage time, and manages token settlements to nodes.
- `SessionReceipt.sol`: Enables nodes to create usage receipts, which clients confirm or reject, and nodes later redeem for token payouts.

## Overview

Clients deposit tokens or native assets into the system to "purchase" time-based service usage. Nodes serve clients and create verifiable receipts representing the served time. Once the client confirms the receipt, the node can redeem it to receive payments.

---

## Contracts

### UsageDepositor

#### Features

- Accepts usage purchases from clients using ERC20 or native tokens.
- Allows the owner to:
  - Whitelist acceptable tokens.
  - Set reward rates (`rewardPerSecond`) per token.
- Allows only the `SessionReceipt` contract to trigger token settlements to nodes.
- Tracks client usage and balances of deposited tokens.
- Supports secure withdrawals and pausing functionality.

#### Key Functions

- `purchaseUsage(UsageOrder)`: Clients deposit tokens for a specified amount of usage time.
- `settleUsageToNode(SettleUsageToNodeRequest)`: SessionReceipt contract settles confirmed usage to a node.
- `addWhitelistedTokens(tokens[])`: Whitelist tokens for usage purchase.
- `setRewardPerSecond(token, amount)`: Set reward rate per second for each token.
- `withdraw(token, to, amount)`: Owner withdraws funds from the contract.

---

### SessionReceipt

#### Features

- Nodes create usage receipts when service is provided.
- Clients confirm or reject receipts.
- Confirmed receipts can be redeemed by nodes for payment.
- Uses nonces to ensure replay protection and correct ordering.

#### Key Functions

- `createSessionReceipt(client, servedSeconds, token, type, nonce)`: Called by valid nodes.
- `confirmSessionReceipt(nonce)`: Called by clients to approve receipt.
- `rejectSessionReceipt(nonce)`: Called by clients to reject receipt.
- `redeemReceipt(client, nonce)`: Called by node to redeem tokens for confirmed usage.

---

## Libraries & Interfaces

### Libraries Used

- `Types.sol`: Common type definitions including enums like `TokenType`.
- `LibUsageOrder.sol`: Contains struct `UsageOrder` and `SettleUsageToNodeRequest`.
- `LibSessionReceipt.sol`: Contains `SessionReceipt` struct and `SessionReceiptStatus` enum.

### Interfaces

- `INodesStorage`: Used to verify node addresses.
- `IUsageDepositor`: Used by `SessionReceipt` to call `settleUsageToNode`.

---

## Events

### UsageDepositor

- `UsagePurchased(client, totalPrice, usage)`
- `UsageSettledToNode(client, node, usage, amount)`
- `TokenWhitelisted(token)`
- `TokenUnwhitelisted(token)`
- `Withdrawn(token, to, amount)`

### SessionReceipt

- `SessionReceiptCreated(client, node, servedSeconds, token, nonce)`
- `SessionReceiptConfirmed(client, node, nonce)`
- `SessionReceiptRedeemed(client, node, nonce)`
- `SessionReceiptRejected(client, node, nonce)`

---

## Security & Access Control

- Contracts use OpenZeppelin’s `Ownable`, `ReentrancyGuard`, and `Pausable`.
- Only valid nodes (validated through `INodesStorage`) can create and redeem receipts.
- Only the owner can manage whitelisted tokens, reward rates, and withdrawals.

---

## Deployment & Integration

Deploy in the following order:

1. `NodesStorage` – your external registry of whitelisted nodes.
2. `UsageDepositor` – provide `SessionReceipt` and `NodesStorage` addresses.
3. `SessionReceipt` – provide `NodesStorage` and `UsageDepositor` addresses.

Ensure that both contracts are aware of each other's addresses using `setUsageDepositor` and `setSessionReceiptContract`.

---

## Example Flow

1. Client calls `purchaseUsage()` with token/native funds.
2. Node serves the client and calls `createSessionReceipt()`.
3. Client reviews and either:
   - Approves: `confirmSessionReceipt()`
   - Rejects: `rejectSessionReceipt()`
4. If confirmed, node calls `redeemReceipt()` to get paid.
