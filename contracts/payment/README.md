# UsageDepositor Smart Contract

A Solidity smart contract that manages usage-based payments for decentralized node services. It allows clients to deposit tokens (ERC20 or native), enforces maintain fee requirements, tracks daily free usage, and handles reward distribution to nodes based on bytes of data served.

---

## 🧾 Features

- ✅ Maintain fee enforcement for clients
- ✅ Daily free usage quota (in bytes)
- ✅ Reward per byte configuration per token
- ✅ Support for both ERC20 tokens and native ETH
- ✅ Secure deposit and reward settlement system
- ✅ Role-restricted interaction for receipt settlement
- ✅ Owner-only administration

---

## 📦 Contract Overview

### `UsageDepositor`

This contract:

- Allows clients to deposit funds for usage.
- Supports usage accounting by bytes.
- Handles automated settlement to service-providing nodes.
- Enforces maintain fee before usage is allowed.
- Tracks and resets free usage daily per client.
- Stores maintain fees inside the contract (retrievable via `withdraw()`).

---

## 🛠 Deployment

### Constructor Parameters

```solidity
constructor(address _sessionReceiptContract, address _nodesStorage)
```

- `_sessionReceiptContract`: The authorized contract that can call `settleUsageToNode()`.
- `_nodesStorage`: The contract that validates whether an address is a registered node.

---

## 🔐 Roles & Permissions

| Function               | Role                     |
| ---------------------- | ------------------------ |
| `settleUsageToNode()`  | `SessionReceiptContract` |
| `withdraw()`           | `Owner`                  |
| Admin config (setters) | `Owner`                  |
| `payMaintainFee()`     | `Client`                 |
| `purchaseUsage()`      | `Client`                 |

---

## 💰 Payment & Reward Flow

### Clients:

1. **Pay Maintain Fee (Required Every 30 Days)**:

   ```solidity
   payMaintainFee()
   ```

2. **Purchase Usage by Byte**:

   ```solidity
   purchaseUsage(UsageOrder)
   ```

3. **UsageOrder Fields (via `LibUsageOrder.UsageOrder`)**:
   - `tokenType`: Native or ERC20
   - `tokenAddress`
   - `requestedBytes`

### Nodes:

- Usage is reported and settled via `SessionReceiptContract`:

  ```solidity
  settleUsageToNode(SettleUsageToNodeRequest)
  ```

- They receive:
  - **Paid usage** → in the same token deposited by client
  - **Free usage** → in native token (ETH), from contract's balance

---

## 🔄 Daily Free Usage

- Clients receive a daily quota (`DAILY_FREE_USAGE`, default 500 KB).
- Automatically reset once per day on first settlement.
- Configurable by owner.

---

## ⚙️ Admin Functions

- `setDailyFreeUsage(uint256)`
- `setMaintainFee(uint256)`
- `setRewardPerByte(address token, uint256)`
- `addWhitelistedTokens(address[])`
- `removeWhitelistedToken(address)`
- `setSessionReceiptContract(address)`
- `setNodesStorage(address)`
- `withdraw(address token, address to, uint256 amount)`

---

## 🧪 Events

- `UsagePurchased(client, totalPrice, usageBytes)`
- `UsageSettledToNode(client, node, bytes, reward)`
- `TokenWhitelisted(token)`
- `TokenUnwhitelisted(token)`
- `Withdrawn(token, to, amount)`
- `MaintainFeePaid(payer, amount, timestamp)`

---

## 🔎 Example Flow

1. Owner whitelists tokens and sets reward per byte.
2. Client pays maintain fee.
3. Client purchases 1 MB of usage with an ERC20 token.
4. SessionReceiptContract settles usage:
   - Node receives token for actual usage beyond free quota.
   - Node receives native token for free bytes (if applicable).
5. Owner can later withdraw collected fees or unused balances.

---

## 🧱 Libraries and Interfaces

- [`SafeERC20`](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#SafeERC20)
- [`ReentrancyGuard`](https://docs.openzeppelin.com/contracts/4.x/api/security#ReentrancyGuard)
- [`Pausable`](https://docs.openzeppelin.com/contracts/4.x/api/security#Pausable)
- `INodesStorage` — Interface to validate node addresses
- `LibUsageOrder` — Structs and helper logic for usage orders

---

## ⚠️ Security Notes

- Free usage is paid out **only in native token** (ETH).
- Maintain fee must be paid before any usage purchase.
- ERC20 `rewardPerByte` must be carefully set based on token decimals.
- Only the `SessionReceiptContract` can settle usage to nodes.

---

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

## 📄 License

MIT © 2025
