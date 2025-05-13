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

    // ========================
    // ======== CONSTS ========
    // ========================

    address public constant NATIVE_TOKEN_ADDRESS = address(0);
    uint256 public constant FREE_USAGE_RESET_INTERVAL = 1 days;
    uint256 public constant MAINTAIN_FEE_PAYMENT_PERIOD = 30 days;

    // ========================
    // ===== CONFIG PARAM =====
    // ========================

    uint256 public DAILY_FREE_USAGE = 500 * 1024; // 500 KB in bytes
    uint256 public MAINTAIN_FEE;

    // ========================
    // ====== EXTERNALS =======
    // ========================

    address public nodesStorage;
    address public sessionReceiptContract;

    // ========================
    // ======= STORAGE ========
    // ========================

    mapping(address => uint256) private lastMaintainFeePaidPerClient;
    mapping(address => bool) private whitelistedTokens;
    mapping(address => uint256) private rewardPerBytePerToken;
    mapping(address => uint256) private clientUsagesInBytes;
    mapping(address => uint256) private tokenBalances;
    mapping(address => uint256) public freeUsageLastReset;
    mapping(address => uint256) public freeUsageUsed;

    // ========================
    // ========= EVENTS =======
    // ========================

    event UsagePurchased(
        address indexed client,
        uint256 totalPrice,
        uint256 usageBytes
    );
    event UsageSettledToNode(
        address indexed client,
        address indexed node,
        uint256 servedBytes,
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

    // ========================
    // ======== ERRORS ========
    // ========================

    error UsageDepositor__AddressZero(string reason);
    error UsageDepositor__InvalidCaller(string reason);
    error UsageDepositor__TokenNotWhitelisted();
    error UsageDepositor__InvalidNodeAddress();
    error UsageDepositor__ExceedtokensLength(uint8 maxAllowed);
    error UsageDepositor__InvalidTotalServedBytes();
    error UsageDepositor__InvalidNativeTokenAddress();
    error UsageDepositor__InvalidERC20Address();
    error UsageDepositor__InsufficientMaintainFee();
    error UsageDepositor__InsufficientNodeFee();
    error UsageDepositor__WithdrawFailed();
    error UsageDepositor__NativeTokenNotAcceptedWithERC20();
    error UsageDepositor__MaintainFeeNotDueYet(
        uint256 lastPaid,
        uint256 nextEligible,
        uint256 nowTime
    );
    error UsageDepositor__MaintainFeeNotPaid(uint256 lastPaid, uint256 nowTime);
    error UsageDepositor__TransferTokenFailed(
        address from,
        address to,
        address token,
        uint256 amount
    );
    error UsageDepositor__InsufficientUsage();
    error UsageDepositor__InsufficientTokenBalance(
        uint256 required,
        uint256 balance,
        address token
    );
    error UsageDepositor__RewardPerByteNotSet(address token);

    // ========================
    // ======= MODIFIERS ======
    // ========================

    modifier onlySessionReceiptContract() {
        if (msg.sender != sessionReceiptContract) {
            revert UsageDepositor__InvalidCaller("Only SessionReceiptContract");
        }
        _;
    }

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

    // ========================
    // ======== INIT ==========
    // ========================

    constructor(address _sessionReceiptContract, address _nodesStorage) {
        sessionReceiptContract = _sessionReceiptContract;
        nodesStorage = _nodesStorage;
    }

    // ========================
    // ===== ADMIN FUNCTIONS ==
    // ========================

    function setDailyFreeUsage(uint256 _DAILY_FREE_USAGE) external onlyOwner {
        DAILY_FREE_USAGE = _DAILY_FREE_USAGE;
    }

    function setMaintainFee(uint256 _MAINTAIN_FEE) external onlyOwner {
        MAINTAIN_FEE = _MAINTAIN_FEE;
    }

    function setSessionReceiptContract(
        address _sessionReceiptContract
    ) external onlyOwner {
        sessionReceiptContract = _sessionReceiptContract;
    }

    function setNodesStorage(address _nodesStorage) external onlyOwner {
        if (_nodesStorage == address(0)) {
            revert UsageDepositor__InvalidNodeAddress();
        }
        nodesStorage = _nodesStorage;
    }

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

    function removeWhitelistedToken(address token) external onlyOwner {
        if (!whitelistedTokens[token]) {
            revert UsageDepositor__TokenNotWhitelisted();
        }
        delete whitelistedTokens[token];
        delete rewardPerBytePerToken[token];
        emit TokenUnwhitelisted(token);
    }

    function setRewardPerByte(
        address token,
        uint256 tokenAmount
    ) external onlyOwner {
        if (!whitelistedTokens[token]) {
            revert UsageDepositor__TokenNotWhitelisted();
        }
        rewardPerBytePerToken[token] = tokenAmount;
    }

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
            if (!success) revert UsageDepositor__WithdrawFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit Withdrawn(token, to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ========================
    // ===== CLIENT FUNCTIONS =
    // ========================

    function payMaintainFee() external payable nonReentrant whenNotPaused {
        if (msg.value < MAINTAIN_FEE)
            revert UsageDepositor__InsufficientMaintainFee();

        uint256 lastPaidAt = lastMaintainFeePaidPerClient[msg.sender];
        if (lastPaidAt + MAINTAIN_FEE_PAYMENT_PERIOD > block.timestamp) {
            revert UsageDepositor__MaintainFeeNotDueYet(
                lastPaidAt,
                lastPaidAt + MAINTAIN_FEE_PAYMENT_PERIOD,
                block.timestamp
            );
        }

        lastMaintainFeePaidPerClient[msg.sender] = block.timestamp;
        emit MaintainFeePaid(msg.sender, msg.value, block.timestamp);
    }

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
        address token = usageOrder.tokenAddress;
        uint256 pricePerByte = rewardPerBytePerToken[token];
        uint256 totalPrice = requestedBytes * pricePerByte;

        if (!whitelistedTokens[token])
            revert UsageDepositor__TokenNotWhitelisted();
        if (pricePerByte == 0)
            revert UsageDepositor__RewardPerByteNotSet(token);

        if (usageOrder.tokenType == TokenType.NATIVE) {
            if (token != NATIVE_TOKEN_ADDRESS)
                revert UsageDepositor__InvalidNativeTokenAddress();
            if (msg.value < totalPrice)
                revert UsageDepositor__InsufficientNodeFee();
        } else {
            if (token == NATIVE_TOKEN_ADDRESS)
                revert UsageDepositor__InvalidNativeTokenAddress();
            if (msg.value > 0)
                revert UsageDepositor__NativeTokenNotAcceptedWithERC20();
            IERC20(token).safeTransferFrom(
                msg.sender,
                address(this),
                totalPrice
            );
        }

        tokenBalances[token] += totalPrice;
        clientUsagesInBytes[msg.sender] += requestedBytes;

        emit UsagePurchased(msg.sender, totalPrice, requestedBytes);
    }

    // ========================
    // ===== SESSION RECEIPT FUNCTIONS =
    // ========================

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
        address token = request.tokenAddress;
        uint256 servedBytes = request.totalServedBytes;

        if (servedBytes == 0) revert UsageDepositor__InvalidTotalServedBytes();
        if (!INodesStorage(nodesStorage).isValidNode(node))
            revert UsageDepositor__InvalidNodeAddress();
        if (!whitelistedTokens[token])
            revert UsageDepositor__TokenNotWhitelisted();

        uint256 freeBytes = getClientFreeUsage(client);
        uint256 chargedBytes = servedBytes > freeBytes
            ? servedBytes - freeBytes
            : 0;
        uint256 usedFreeBytes = servedBytes - chargedBytes;

        if (clientUsagesInBytes[client] < chargedBytes)
            revert UsageDepositor__InsufficientUsage();

        uint256 pricePerByte = rewardPerBytePerToken[token];
        if (pricePerByte == 0)
            revert UsageDepositor__RewardPerByteNotSet(token);

        uint256 chargedTotal = chargedBytes * pricePerByte;
        uint256 rewardFree = rewardPerBytePerToken[NATIVE_TOKEN_ADDRESS];
        uint256 freeTotal = usedFreeBytes * rewardFree;

        if (tokenBalances[token] < chargedTotal)
            revert UsageDepositor__InsufficientTokenBalance(
                chargedTotal,
                tokenBalances[token],
                token
            );
        if (tokenBalances[NATIVE_TOKEN_ADDRESS] < freeTotal)
            revert UsageDepositor__InsufficientTokenBalance(
                freeTotal,
                tokenBalances[NATIVE_TOKEN_ADDRESS],
                NATIVE_TOKEN_ADDRESS
            );

        clientUsagesInBytes[client] -= chargedBytes;
        tokenBalances[token] -= chargedTotal;
        freeUsageUsed[client] += usedFreeBytes;

        if (token == NATIVE_TOKEN_ADDRESS) {
            (bool sent, ) = node.call{value: chargedTotal + freeTotal}("");
            if (!sent)
                revert UsageDepositor__TransferTokenFailed(
                    address(this),
                    node,
                    token,
                    chargedTotal + freeTotal
                );
        } else {
            IERC20(token).safeTransfer(node, chargedTotal);
            if (usedFreeBytes > 0) {
                (bool sent, ) = node.call{value: freeTotal}("");
                if (!sent)
                    revert UsageDepositor__TransferTokenFailed(
                        address(this),
                        node,
                        NATIVE_TOKEN_ADDRESS,
                        freeTotal
                    );
            }
        }

        emit UsageSettledToNode(client, node, chargedBytes, chargedTotal);
    }

    // ========================
    // ========= VIEWS ========
    // ========================

    function getClientUsage(address client) external view returns (uint256) {
        return clientUsagesInBytes[client];
    }

    function getClientFreeUsage(address client) public view returns (uint256) {
        return DAILY_FREE_USAGE - freeUsageUsed[client];
    }

    function getClientLastMaintainFeePaid(
        address client
    ) public view returns (uint256) {
        return lastMaintainFeePaidPerClient[client];
    }

    function getRewardPerByte(address token) external view returns (uint256) {
        return rewardPerBytePerToken[token];
    }

    function isPaidMaintainFee(address client) external view returns (bool) {
        return
            lastMaintainFeePaidPerClient[client] + MAINTAIN_FEE_PAYMENT_PERIOD >
            block.timestamp;
    }

    // ========================
    // ===== FALLBACK =========
    // ========================

    receive() external payable {}
}
