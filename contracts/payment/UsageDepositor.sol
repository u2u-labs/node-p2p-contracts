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

    address public constant NATIVE_TOKEN_ADDRESS = address(0);
    uint256 public DAILY_FREE_USAGE = 500 * 1024; // 500 KB (in bytes)
    uint256 public constant FREE_USAGE_RESET_INTERVAL = 1 days;
    // Period for which maintain fee must be paid
    uint256 public constant MAINTAIN_FEE_PAYMENT_PERIOD = 30 days;
    // fee to maintain using node streaming service (must be paid in native token)
    uint256 public MAINTAIN_FEE;

    address public nodesStorage;
    address public sessionReceiptContract;

    mapping(address => uint256) private lastMaintainFeePaidPerClient;
    mapping(address => bool) private whitelistedTokens;
    mapping(address => uint256) private rewardPerBytePerToken;
    mapping(address => uint256) private clientUsagesInBytes;
    mapping(address => uint256) private tokenBalances;
    // last reset timestamp per user
    mapping(address => uint256) public freeUsageLastReset;
    // how much free usage was used per client
    mapping(address => uint256) public freeUsageUsed;

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

    modifier onlySessionReceiptContract() {
        require(
            msg.sender == sessionReceiptContract,
            "Only SessionReceiptContract can call this function"
        );
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

    constructor(address _sessionReceiptContract, address _nodesStorage) {
        sessionReceiptContract = _sessionReceiptContract;
        nodesStorage = _nodesStorage;
    }

    /**
     * @notice Set daiily free usage (called by owner)
     * @param _DAILY_FREE_USAGE Daily free usage in bytes
     */
    function setDailyFreeUsage(uint256 _DAILY_FREE_USAGE) public onlyOwner {
        DAILY_FREE_USAGE = _DAILY_FREE_USAGE;
    }

    /**
     * @notice Set maintain fee (called by owner)
     * @param _MAINTAIN_FEE Maintain fee in wei
     */
    function setMaintainFee(uint256 _MAINTAIN_FEE) public onlyOwner {
        MAINTAIN_FEE = _MAINTAIN_FEE;
    }

    /**
     * @notice Set session receipt contract address (called by owner)
     * @param _sessionReceiptContract Session receipt contract address
     */
    function setSessionReceiptContract(
        address _sessionReceiptContract
    ) public onlyOwner {
        sessionReceiptContract = _sessionReceiptContract;
    }

    /**
     * @notice Set nodes storage contract address (called by owner)
     * @param _nodesStorage Nodes storage contract address
     */
    function setNodesStorage(address _nodesStorage) public onlyOwner {
        require(_nodesStorage != address(0), "Invalid nodes storage address");
        nodesStorage = _nodesStorage;
    }

    /**
     * @notice Get remaining client's usage (unit: byte)
     * @param client Client address
     */
    function getClientUsage(address client) public view returns (uint256) {
        return clientUsagesInBytes[client];
    }

    function getClientFreeUsage(address client) public view returns (uint256) {
        return DAILY_FREE_USAGE - freeUsageUsed[client];
    }

    /**
     * @notice Add tokens to whitelist list (called by owner)
     * @param tokens List of nodes addresses to add
     */
    function addWhitelistedTokens(
        address[] calldata tokens
    ) external onlyOwner {
        require(tokens.length <= 50, "Tokens length exceeds limit (50)");
        for (uint256 i = 0; i < tokens.length; ) {
            whitelistedTokens[tokens[i]] = true;
            emit TokenWhitelisted(tokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Remove token by address from whitelisted tokens list (called by owner)
     * @param token Address of token to remove
     */
    function removeWhitelistedToken(address token) external onlyOwner {
        require(whitelistedTokens[token], "Token is not whitelisted");
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
        require(whitelistedTokens[token], "Token is not whitelisted");
        rewardPerBytePerToken[token] = tokenAmount;
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
        require(msg.value == MAINTAIN_FEE, "Incorrect maintain fee");
        require(
            lastMaintainFeePaidPerClient[msg.sender] +
                MAINTAIN_FEE_PAYMENT_PERIOD <=
                block.timestamp,
            "Already paid recently"
        );

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
        require(
            lastMaintainFeePaidPerClient[msg.sender] +
                MAINTAIN_FEE_PAYMENT_PERIOD >
                block.timestamp,
            "Maintain fee not paid"
        );

        uint256 requestedBytes = usageOrder.requestedBytes;
        TokenType tokenType = usageOrder.tokenType;
        address tokenAddress = usageOrder.tokenAddress;
        uint256 rewardPerByte = rewardPerBytePerToken[tokenAddress];
        uint256 totalPrice = requestedBytes * rewardPerByte;

        require(whitelistedTokens[tokenAddress], "Token is not whitelisted");
        require(rewardPerByte > 0, "Reward per byte is not set");
        require(
            requestedBytes > 0,
            "Requested bytes data must be greater than 0"
        );

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
        checkAndResetFreeUsage(request.client)
        onlySessionReceiptContract
        nonReentrant
        whenNotPaused
    {
        uint256 totalServedBytes = request.totalServedBytes;

        address node = request.node;
        require(totalServedBytes > 0, "Total served bytes must be > 0");

        bool isValidNode = INodesStorage(nodesStorage).isValidNode(node);
        require(isValidNode, "Invalid node address");

        address tokenAddress = request.tokenAddress;
        require(whitelistedTokens[tokenAddress], "Token is not whitelisted");

        address client = request.client;
        uint256 clientFreeBytes = getClientFreeUsage(client);

        uint256 chargedServedBytes = totalServedBytes > clientFreeBytes
            ? totalServedBytes - clientFreeBytes
            : 0;
        require(
            clientUsagesInBytes[client] >= chargedServedBytes,
            "Insufficient usage"
        );

        uint256 usedFreeBytes = totalServedBytes > clientFreeBytes
            ? clientFreeBytes
            : totalServedBytes;
        if (usedFreeBytes > 0) {
            require(
                rewardPerBytePerToken[NATIVE_TOKEN_ADDRESS] > 0,
                "Free usage reward not configured"
            );
        }

        uint256 rewardPerByte = rewardPerBytePerToken[tokenAddress];
        require(rewardPerByte > 0, "Reward per byte is not set");

        //Calculate price for charged served bytes
        uint256 totalPrice = chargedServedBytes * rewardPerByte;
        require(
            tokenBalances[tokenAddress] >= totalPrice,
            "Insufficient token balance"
        );

        //Calculate free bytes price for used free bytes (currently free bytes are paid in native token)
        uint256 rewardFreeBytesPerByte = rewardPerBytePerToken[
            NATIVE_TOKEN_ADDRESS
        ];
        uint256 freeBytesPrice = rewardFreeBytesPerByte * usedFreeBytes;
        require(
            tokenBalances[NATIVE_TOKEN_ADDRESS] >= freeBytesPrice,
            "Insufficient native token balance"
        );

        clientUsagesInBytes[client] -= chargedServedBytes;
        tokenBalances[tokenAddress] -= totalPrice;
        freeUsageUsed[client] += usedFreeBytes;

        if (tokenAddress == NATIVE_TOKEN_ADDRESS) {
            // If node is native token, transfer both charged and free bytes to node
            (bool success, ) = node.call{value: totalPrice + freeBytesPrice}(
                ""
            );
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(node, totalPrice);
            // If there are free bytes used, transfer them to node
            if (usedFreeBytes > 0) {
                (bool success, ) = node.call{value: freeBytesPrice}("");
                require(success, "Transfer failed");
            }
        }

        emit UsageSettledToNode(client, node, chargedServedBytes, totalPrice);
    }

    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        if (token == NATIVE_TOKEN_ADDRESS) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "Withdraw failed");
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

    receive() external payable {}
}
