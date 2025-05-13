# 📦 UsageDepositor Smart Contract

A secure and flexible usage-based payment system for decentralized data-serving networks. Clients prepay for data usage in tokens (native or ERC20), and verified nodes receive payouts based on served data. It includes features like daily free usage, maintain fee enforcement, and token reward rates per byte.

---

## 🛠 Features

- Pay-per-byte usage model for clients
- Support for both **native token** and **ERC20 tokens**
- Daily **free usage limit** per client
- **Maintain fee** required every 30 days
- Secure **settlement to nodes** after data service
- Configurable reward rate per byte/token
- Token whitelist management
- Emergency `pause/unpause` functions
- Only authorized SessionReceiptContract can trigger settlements

---

## 🧩 Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- Custom libraries:
  - `Types.sol`
  - `LibUsageOrder.sol`
- External contracts:
  - `INodesStorage`
  - `SessionReceipt`

---

## 🚀 Deployment

### Constructor

```solidity
constructor(address _sessionReceiptContract, address _nodesStorage)
```

| Parameter                 | Description                           |
|--------------------------|---------------------------------------|
| `_sessionReceiptContract`| Contract to authorize usage settlement|
| `_nodesStorage`          | Contract that manages valid node list |

---

## ⚙️ Configuration (Owner-only)

| Function                             | Purpose                                  |
|--------------------------------------|------------------------------------------|
| `setDailyFreeUsage(uint256)`         | Set daily free byte quota per client     |
| `setMaintainFee(uint256)`            | Set native token amount for maintenance  |
| `setRewardPerByte(address, uint256)` | Set token amount paid per byte served    |
| `addWhitelistedTokens(address[])`    | Add supported ERC20 tokens               |
| `removeWhitelistedToken(address)`    | Remove supported token                   |
| `setSessionReceiptContract(address)` | Update SessionReceipt contract           |
| `setNodesStorage(address)`           | Update NodesStorage contract             |
| `withdraw(address, address, uint256)`| Withdraw tokens or native balance        |
| `pause()` / `unpause()`              | Emergency controls                       |

---

## 👤 Client Functions

### Pay Maintain Fee

```solidity
payMaintainFee() external payable
```

- Must pay `MAINTAIN_FEE` in native token
- Required every 30 days to remain active

---

### Purchase Usage

```solidity
purchaseUsage(LibUsageOrder.UsageOrder calldata usageOrder)
```

- Pays in selected token for specified `requestedBytes`
- Must have paid maintain fee beforehand

---

### View Functions

| Function                                | Description                              |
|-----------------------------------------|------------------------------------------|
| `getClientUsage(address)`               | Returns total remaining bytes            |
| `getClientFreeUsage(address)`           | Remaining free usage for the day         |
| `isPaidMaintainFee(address)`            | Whether client is within fee window      |
| `getRewardPerByte(address)`             | Reward rate for a token (per byte)       |
| `getClientLastMaintainFeePaid(address)` | Get last time client paid maintain fee   |

---

## 📤 Node Settlement

### Called by `SessionReceiptContract`

```solidity
settleUsageToNode(LibUsageOrder.SettleUsageToNodeRequest calldata request)
```

- Validates node and usage
- Deducts usage from client
- Pays tokens to the node (and native token for free usage)

---

## 🧾 Events

| Event                      | Triggered When                                        |
|---------------------------|--------------------------------------------------------|
| `UsagePurchased`          | Client buys usage with tokens                          |
| `UsageSettledToNode`      | Token payout is completed to a node                    |
| `MaintainFeePaid`         | Client pays native token to activate service           |
| `Withdrawn`               | Owner withdraws tokens or native funds                 |
| `TokenWhitelisted`        | New token added for usage payments                     |
| `TokenUnwhitelisted`      | Token removed from whitelist                           |

---

## 🛡️ Errors (Custom)

Some examples:
- `UsageDepositor__MaintainFeeNotDueYet(...)`
- `UsageDepositor__InsufficientTokenBalance(...)`
- `UsageDepositor__TokenNotWhitelisted()`
- `UsageDepositor__TransferTokenFailed(...)`
- `UsageDepositor__InvalidCaller(...)`

Use [custom errors](https://docs.soliditylang.org/en/latest/control-structures.html#custom-errors) for gas optimization.

---

## 🧪 Example Flow

### 1. Client Setup
- Pays native maintain fee: `payMaintainFee()`
- Buys usage credits via `purchaseUsage()` with selected token

### 2. Node Serves Client
- Client submits a signed session receipt
- `SessionReceiptContract` calls `settleUsageToNode()` to transfer payment to the node

---

## 🔐 Security Considerations

- Only whitelisted tokens can be used for usage
- Owner can pause the contract during emergencies
- Settlement only by trusted `SessionReceiptContract`
- Contract prevents reentrancy attacks

---

## ⛓️ Example Token Pricing

If 1 token = 1e18 (like ETH), then:
- `rewardPerByte = 1e12` → 1 KB costs 1e15 (0.001 token)
- Set this via: `setRewardPerByte(token, 1e12)`


# SessionReceipt Smart Contract

The `SessionReceipt` smart contract is responsible for managing verifiable session-based data usage reports between clients and nodes. It issues, confirms, and redeems usage receipts which are used to settle payments via the `UsageDepositor` contract.

---

## 🧾 Features

- ✅ Receipt creation by verified nodes
- ✅ Client-side confirmation or rejection
- ✅ Enforces sequential receipt ordering via nonce
- ✅ Redemption triggers on-chain payment via `UsageDepositor`
- ✅ Fully on-chain, non-custodial, verifiable trail

---

## 📦 Contract Overview

### `SessionReceipt`

This contract allows:

- Nodes to issue usage receipts for served bytes
- Clients to confirm or reject those receipts
- Confirmed receipts to be redeemed (payout to nodes)
- All data to be verifiably stored and accessible

---

## 🛠 Deployment

### Constructor

```solidity
constructor(address _nodesStorage, address _usageDepositor)
```

- `_nodesStorage`: Contract that tracks valid nodes (`INodesStorage`)
- `_usageDepositor`: Contract responsible for paying out rewards (`IUsageDepositor`)

---

## 🔐 Roles & Access

| Action                  | Role           |
| ----------------------- | -------------- |
| `createSessionReceipt`  | Valid node     |
| `confirmSessionReceipt` | Client         |
| `rejectSessionReceipt`  | Client         |
| `redeemReceipt`         | Valid node     |
| Admin setters           | Contract owner |

---

## 📘 Key Concepts

### `SessionReceipt`

Each session receipt includes:

- `client`: Address of client
- `node`: Address of node
- `totalServedBytes`: Amount of data served
- `tokenType`: ERC20 or Native
- `tokenAddress`: Address of the token used
- `status`: Pending / Confirmed / Rejected / Paid
- `nonce`: Sequential nonce per client

---

## 🔄 Receipt Lifecycle

1. **Creation** (by node):

   ```solidity
   createSessionReceipt(client, bytes, token, type, nonce)
   ```

2. **Confirmation** (by client):

   ```solidity
   confirmSessionReceipt(nonce)
   ```

3. **Redemption** (by node):

   ```solidity
   redeemReceipt(client, nonce)
   ```

4. **Rejection** (by client):
   ```solidity
   rejectSessionReceipt(nonce)
   ```

---

## ⚙️ Admin Functions

- `setNodesStorage(address)`
- `setUsageDepositor(address)`

---

## 📊 Views & Queries

- `getSessionReceipt(address client, uint256 nonce)`
- `getNonce(address client)`
- `getConfirmedNonces(address client, address node)`
- `getLatestReceipt(address client)`

---

## 🧪 Events

- `SessionReceiptCreated`
- `SessionReceiptConfirmed`
- `SessionReceiptRedeemed`
- `SessionReceiptRejected`

---
