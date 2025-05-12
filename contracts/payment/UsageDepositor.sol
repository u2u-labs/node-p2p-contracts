// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./libraries/Types.sol";
import "./libraries/LibUsageOrder.sol";
import "../interfaces/INodesStorage.sol";

contract UsageDepositor is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // === Constants ===
    address public constant NATIVE_TOKEN_ADDRESS = address(0);
    uint256 public constant FREE_USAGE_RESET_INTERVAL = 1 days;
    uint256 public constant MAINTAIN_FEE_PAYMENT_PERIOD = 30 days;

    // === Configurable Parameters ===
    uint256 public DAILY_FREE_USAGE = 500 * 1024; // 500 KB in bytes
    uint256 public MAINTAIN_FEE;

    // === External Contracts ===
    address public nodesStorage;
    address public sessionReceiptContract;

    // === State ===
    mapping(address => uint256) private lastMaintainFeePaidPerClient;
    mapping(address => bool) private whitelistedTokens;
    mapping(address => uint256) private rewardPerBytePerToken;
    mapping(address => uint256) private clientUsagesInBytes;
    mapping(address => uint256) private tokenBalances;
    mapping(address => uint256) public freeUsageLastReset;
    mapping(address => uint256) public freeUsageUsed;

    // === Events ===
    event UsagePurchased(
        address client,
        uint256 totalPrice,
        uint256 usageBytes
    );
    event UsageSettledToNode(
        address client,
        address node,
        uint256 totalServedBytes,
        uint256 totalToken
    );
    event TokenWhitelisted(address token);
    event TokenUnwhitelisted(address token);
    event Withdrawn(address token, address to, uint256 amount);
    event MaintainFeePaid(
        address indexed payer,
        uint256 amount,
        uint256 timestamp
    );

    // === Custom Errors ===
    error UsageDepositor__AddressZero(string errorMessage);
    error UsageDepositor__InvalidCaller(string errorMessage);
    error UsageDepositor__TokenNotWhitelisted();
    error UsageDepositor__InvalidNodeAddress();
    error UsageDepositor__ExceedtokensLength(uint8);
    error UsageDepositor__InvalidTokenType();
    error UsageDepositor__InvalidNativeTokenAddress();
    error UsageDepositor__InsufficientMaintainFee();
    error UsageDepositor__WithdrawFailed();
    error UsageDepositor__MaintainFeeNotDueYet(
        uint256 lastPaidAt,
        uint256 nextEligibleAt,
        uint256 currentTime
    );
    error UsageDepositor__MaintainFeeNotPaid(
        uint256 lastPaidAt,
        uint256 currentTime
    );
    error UsageDepositor__TransferTokenFailed(
        address from,
        address to,
        address tokenAddress,
        uint256 amount
    );
    error UsageDepositor__InsufficientUsage();
    error UsageDepositor__InsufficientTokenBalance(
        uint256 requireAmount,
        uint256 currentBalance,
        address tokenAddress
    );

    // === Modifiers ===
    modifier onlySessionReceiptContract() {
        if (msg.sender != sessionReceiptContract) {
            revert UsageDepositor__InvalidCaller("Only SessionReceiptContract");
        }
        _;
    }

    /**
     * @notice Check if last reset free usage was more than FREE_USAGE_RESET_INTERVAL ago, if so reset it
     * @param client Client address
     */
    modifier checkAndResetFreeUsage(address client) {
        uint256 lastReset = freeUsageLastReset[client];
        uint256 todayStart = block.timestamp -
            (block.timestamp % FREE_USAGE_RESET_INTERVAL);
        if (lastReset < todayStart) {
            freeUsageLastReset[client] = todayStart;
            freeUsageUsed[client] = 0;
        }
        _;
    }

    /**
     * @notice Constructor
     * @param _sessionReceiptContract Session receipt contract
     * @param _nodesStorage Nodes storage contract
     */
    constructor(address _sessionReceiptContract, address _nodesStorage) {
        sessionReceiptContract = _sessionReceiptContract;
        nodesStorage = _nodesStorage;
    }

    // === Admin Functions ===

    /**
     * @notice Set daily free usage (called by owner)
     * @param _DAILY_FREE_USAGE Daily free usage in bytes
     */
    function setDailyFreeUsage(uint256 _DAILY_FREE_USAGE) external onlyOwner {
        DAILY_FREE_USAGE = _DAILY_FREE_USAGE;
    }

    /**
     * @notice Set maintain fee (called by owner)
     * @param _MAINTAIN_FEE Maintain fee in wei
     */
    function setMaintainFee(uint256 _MAINTAIN_FEE) external onlyOwner {
        MAINTAIN_FEE = _MAINTAIN_FEE;
    }

    /**
     * @notice Set session receipt contract address (called by owner)
     * @param _sessionReceiptContract Session receipt contract address
     */
    function setSessionReceiptContract(
        address _sessionReceiptContract
    ) external onlyOwner {
        sessionReceiptContract = _sessionReceiptContract;
    }

    /**
     * @notice Set nodes storage contract address (called by owner)
     * @param _nodesStorage Nodes storage contract address
     */
    function setNodesStorage(address _nodesStorage) external onlyOwner {
        if (_nodesStorage == address(0)) {
            revert UsageDepositor__InvalidNodeAddress();
        }
        nodesStorage = _nodesStorage;
    }

    /**
     * @notice Add tokens to whitelist list (called by owner)
     * @param tokens List of token addresses to add
     */
    function addWhitelistedTokens(
        address[] calldata tokens
    ) external onlyOwner {
        if (tokens.length > 50) {
            revert UsageDepositor__ExceedtokensLength(50);
        }
        for (uint256 i = 0; i < tokens.length; ++i) {
            whitelistedTokens[tokens[i]] = true;
            emit TokenWhitelisted(tokens[i]);
        }
    }

    /**
     * @notice Remove token by address from whitelisted tokens list (called by owner)
     * @param token Address of token to remove
     */
    function removeWhitelistedToken(address token) external onlyOwner {
        if (!whitelistedTokens[token]) {
            revert UsageDepositor__TokenNotWhitelisted();
        }
        delete whitelistedTokens[token];
        delete rewardPerBytePerToken[token];
        emit TokenUnwhitelisted(token);
    }

    /**
     * @notice Set reward per byte for a token (called by owner)
     * @param token Address of token
     * @param tokenAmount reward per byte (e.g., 1e12 = 0.000000000001 token per byte)
     */
    function setRewardPerByte(
        address token,
        uint256 tokenAmount
    ) external onlyOwner {
        if (!whitelistedTokens[token]) {
            revert UsageDepositor__TokenNotWhitelisted();
        }
        rewardPerBytePerToken[token] = tokenAmount;
    }

    /**
     * @notice Withdraw token or native balance (called by owner)
     * @param token Token address or zero address for native
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (to == address(0)) {
            revert UsageDepositor__AddressZero("Invalid recipient");
        }
        if (token == NATIVE_TOKEN_ADDRESS) {
            (bool success, ) = to.call{value: amount}("");
            if (!success) {
                revert UsageDepositor__WithdrawFailed();
            }
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit Withdrawn(token, to, amount);
    }

    // === Client Functions ===

    /**
     * @notice Get remaining client's usage (unit: byte)
     * @param client Client address
     */
    function getClientUsage(address client) external view returns (uint256) {
        return clientUsagesInBytes[client];
    }

    /**
     * @notice Get remaining free usage for the client
     * @param client Client address
     */
    function getClientFreeUsage(address client) public view returns (uint256) {
        return DAILY_FREE_USAGE - freeUsageUsed[client];
    }

    /**
     * @notice Get reward per byte for a token
     * @param token Address of token
     */
    function getRewardPerByte(address token) external view returns (uint256) {
        return rewardPerBytePerToken[token];
    }

    /**
     * @notice Check if client has already paid maintain fee this period (30 days)
     * @param client Client address
     */
    function isPaidMaintainFee(address client) external view returns (bool) {
        return
            lastMaintainFeePaidPerClient[client] + MAINTAIN_FEE_PAYMENT_PERIOD >
            block.timestamp;
    }

    /**
     * @notice Pay maintain fee (called by client)
     */
    function payMaintainFee() external payable nonReentrant whenNotPaused {
        if (msg.value < MAINTAIN_FEE) {
            revert UsageDepositor__InsufficientMaintainFee();
        }

        uint256 lastPaidAt = lastMaintainFeePaidPerClient[msg.sender];
        uint256 nextPaidAt = lastPaidAt + MAINTAIN_FEE_PAYMENT_PERIOD;

        if (lastPaidAt + MAINTAIN_FEE_PAYMENT_PERIOD > block.timestamp) {
            revert UsageDepositor__MaintainFeeNotDueYet(
                lastPaidAt,
                nextPaidAt,
                block.timestamp
            );
        }

        lastMaintainFeePaidPerClient[msg.sender] = block.timestamp;
        emit MaintainFeePaid(msg.sender, msg.value, block.timestamp);
    }

    /**
     * @notice Purchase usage for a client (called by client, only after paid maintain fee)
     * @param usageOrder Usage order details to purchase
     */
    function purchaseUsage(
        LibUsageOrder.UsageOrder calldata usageOrder
    ) external payable nonReentrant whenNotPaused {
        if (
            lastMaintainFeePaidPerClient[msg.sender] +
                MAINTAIN_FEE_PAYMENT_PERIOD <=
            block.timestamp
        ) {
            revert UsageDepositor__MaintainFeeNotPaid(
                lastMaintainFeePaidPerClient[msg.sender],
                block.timestamp
            );
        }

        uint256 requestedBytes = usageOrder.requestedBytes;
        TokenType tokenType = usageOrder.tokenType;
        address tokenAddress = usageOrder.tokenAddress;
        uint256 rewardPerByte = rewardPerBytePerToken[tokenAddress];
        uint256 totalPrice = requestedBytes * rewardPerByte;

        if (!whitelistedTokens[tokenAddress]) {
            revert UsageDepositor__TokenNotWhitelisted();
        }
        require(rewardPerByte > 0, "Reward per byte is not set");
        require(requestedBytes > 0, "Requested bytes must be > 0");

        if (tokenType == TokenType.NATIVE) {
            require(
                tokenAddress == NATIVE_TOKEN_ADDRESS,
                "Invalid native token address"
            );
            require(msg.value == totalPrice, "Incorrect amount of native sent");
        } else {
            require(
                tokenAddress != NATIVE_TOKEN_ADDRESS,
                "Invalid ERC20 token address"
            );
            require(msg.value == 0, "Native token not accepted with ERC20");
            IERC20(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                totalPrice
            );
        }

        tokenBalances[tokenAddress] += totalPrice;
        clientUsagesInBytes[msg.sender] += requestedBytes;

        emit UsagePurchased(msg.sender, totalPrice, requestedBytes);
    }

    /**
     * @notice Settle usage to node (transfer client's deposit token to node) (called by SessionReceiptContract)
     * @param request Request details to settle usage to node
     */
    function settleUsageToNode(
        LibUsageOrder.SettleUsageToNodeRequest calldata request
    )
        external
        onlySessionReceiptContract
        checkAndResetFreeUsage(request.client)
        nonReentrant
        whenNotPaused
    {
        address client = request.client;
        address node = request.node;
        address tokenAddress = request.tokenAddress;
        uint256 totalServedBytes = request.totalServedBytes;

        require(totalServedBytes > 0, "Total served bytes must be > 0");
        require(
            INodesStorage(nodesStorage).isValidNode(node),
            "Invalid node address"
        );

        if (!whitelistedTokens[tokenAddress]) {
            revert UsageDepositor__TokenNotWhitelisted();
        }

        uint256 clientFreeBytes = getClientFreeUsage(client);
        uint256 chargedServedBytes = totalServedBytes > clientFreeBytes
            ? totalServedBytes - clientFreeBytes
            : 0;
        uint256 usedFreeBytes = totalServedBytes - chargedServedBytes;

        if (clientUsagesInBytes[client] < chargedServedBytes) {
            revert UsageDepositor__InsufficientUsage();
        }

        uint256 rewardPerByte = rewardPerBytePerToken[tokenAddress];
        require(rewardPerByte > 0, "Reward per byte is not set");
        uint256 totalPrice = chargedServedBytes * rewardPerByte;

        uint256 rewardFreePerByte = rewardPerBytePerToken[NATIVE_TOKEN_ADDRESS];
        uint256 freeBytesPrice = usedFreeBytes * rewardFreePerByte;

        if (tokenBalances[tokenAddress] < totalPrice) {
            revert UsageDepositor__InsufficientTokenBalance(
                totalPrice,
                tokenBalances[tokenAddress],
                tokenAddress
            );
        }

        if (tokenBalances[NATIVE_TOKEN_ADDRESS] < freeBytesPrice) {
            revert UsageDepositor__InsufficientTokenBalance(
                freeBytesPrice,
                tokenBalances[NATIVE_TOKEN_ADDRESS],
                NATIVE_TOKEN_ADDRESS
            );
        }

        clientUsagesInBytes[client] -= chargedServedBytes;
        tokenBalances[tokenAddress] -= totalPrice;
        freeUsageUsed[client] += usedFreeBytes;

        if (tokenAddress == NATIVE_TOKEN_ADDRESS) {
            (bool success, ) = node.call{value: totalPrice + freeBytesPrice}(
                ""
            );
            if (!success) {
                revert UsageDepositor__TransferTokenFailed(
                    address(this),
                    node,
                    NATIVE_TOKEN_ADDRESS,
                    totalPrice + freeBytesPrice
                );
            }
        } else {
            IERC20(tokenAddress).safeTransfer(node, totalPrice);
            if (usedFreeBytes > 0) {
                (bool success, ) = node.call{value: freeBytesPrice}("");
                if (!success) {
                    revert UsageDepositor__TransferTokenFailed(
                        address(this),
                        node,
                        NATIVE_TOKEN_ADDRESS,
                        freeBytesPrice
                    );
                }
            }
        }

        emit UsageSettledToNode(client, node, chargedServedBytes, totalPrice);
    }

    // === Emergency Controls ===

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
