# Node P2P Contracts

This repository contains the contracts for the Node P2P project:

- [Node P2P Contracts](./contracts)

## Deploy contract

- Run: npx hardhat run scripts/deploy.ts --network <your_network>

---

# NodesStorage

The `NodesStorage` smart contract manages a registry of valid node addresses that are authorized to perform certain actions within a decentralized system (such as creating or redeeming session receipts). It is owned and controlled by an admin (typically a DAO or system operator) and is designed to be used by other contracts via the `INodesStorage` interface.

- [Contracts](./contracts/nodes%20storage)
- [Document](./contracts/nodes%20storage/README.md)

# Voting

The `Voting` contract allows nodes to report misbehaving peers and, once a quorum is reached, schedule their removal after a delay. This ensures decentralized governance over a set of nodes managed by a separate `NodesStorage` contract.

- [Contracts](./contracts/voting)
- [Document](./contracts/voting/README.md)

# Usage Depositor & Session Receipt

Two core smart contracts for a decentralized usage-based payment system:

- `UsageDepositor.sol`: Handles token deposits from clients in exchange for usage data (bytes), and manages token settlements to nodes.
- `SessionReceipt.sol`: Enables nodes to create usage receipts, which clients confirm or reject, and nodes later redeem for token payouts.

- [Contracts](./contracts/payment)
- [Document](./contracts/payment/README.md)
