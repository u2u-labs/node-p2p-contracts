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

    address public nodesStorage;
    address public sessionReceiptContract;

    mapping(address => bool) private whitelistedTokens;
    mapping(address => uint256) private rewardPerSecondPerToken;
    mapping(address => uint256) private tokenBalances;
    mapping(address => uint256) private clientUsages;

    event UsagePurchased(address client, uint256 totalPrice, uint256 usage);
    event UsageSettledToNode(
        address client,
        address node,
        uint256 totalServedUsage,
        uint256 totalToken
    );
    event TokenWhitelisted(address token);
    event TokenUnwhitelisted(address token);
    event Withdrawn(address token, address to, uint256 amount);

    modifier onlySessionReceiptContract() {
        require(
            msg.sender == sessionReceiptContract,
            "Only SessionReceiptContract can call this function"
        );
        _;
    }

    constructor(address _sessionReceiptContract, address _nodesStorage) {
        sessionReceiptContract = _sessionReceiptContract;
        nodesStorage = _nodesStorage;
    }

    function getClientUsage(address client) public view returns (uint256) {
        return clientUsages[client];
    }

    function setSessionReceiptContract(
        address _sessionReceiptContract
    ) public onlyOwner {
        sessionReceiptContract = _sessionReceiptContract;
    }

    function setNodesStorage(address _nodesStorage) public onlyOwner {
        require(_nodesStorage != address(0), "Invalid nodes storage address");
        nodesStorage = _nodesStorage;
    }

    function addWhitelistedTokens(
        address[] calldata tokens
    ) external onlyOwner {
        require(tokens.length <= 50, "Tokens length exceeds limit (50)");
        for (uint256 i = 0; i < tokens.length; i++) {
            whitelistedTokens[tokens[i]] = true;
            emit TokenWhitelisted(tokens[i]);
        }
    }

    function removeWhitelistedToken(address token) external onlyOwner {
        require(whitelistedTokens[token], "Token is not whitelisted");
        delete whitelistedTokens[token];
        delete rewardPerSecondPerToken[token];
        emit TokenUnwhitelisted(token);
    }

    function setRewardPerSecond(
        address token,
        uint256 tokenAmount
    ) external onlyOwner {
        require(whitelistedTokens[token], "Token is not whitelisted");
        rewardPerSecondPerToken[token] = tokenAmount;
    }

    function getRewardPerSecond(address token) external view returns (uint256) {
        return rewardPerSecondPerToken[token];
    }

    function purchaseUsage(
        LibUsageOrder.UsageOrder calldata usageOrder
    ) external payable nonReentrant whenNotPaused {
        uint256 requestedSeconds = usageOrder.requestedSeconds;
        TokenType tokenType = usageOrder.tokenType;
        address tokenAddress = usageOrder.tokenAddress;
        uint256 rewardPerSecond = rewardPerSecondPerToken[tokenAddress];

        require(whitelistedTokens[tokenAddress], "Token is not whitelisted");
        require(rewardPerSecond > 0, "Reward per second is not set");
        require(
            requestedSeconds > 0,
            "Requested seconds must be greater than 0"
        );

        uint256 totalPrice = requestedSeconds * rewardPerSecond;

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
        clientUsages[msg.sender] += requestedSeconds;
        emit UsagePurchased(msg.sender, totalPrice, requestedSeconds);
    }

    function settleUsageToNode(
        LibUsageOrder.SettleUsageToNodeRequest calldata request
    ) external onlySessionReceiptContract nonReentrant whenNotPaused {
        address node = request.node;
        address client = request.client;
        uint256 totalServedUsage = request.totalServedUsage;
        address tokenAddress = request.tokenAddress;
        uint256 rewardPerSecond = rewardPerSecondPerToken[tokenAddress];
        bool isValidNode = INodesStorage(nodesStorage).isValidNode(node);
        uint256 totalPrice = totalServedUsage * rewardPerSecond;

        // Check if request's data is valid
        require(totalServedUsage > 0, "Total served usage must be > 0");
        require(isValidNode, "Invalid node address");
        require(clientUsages[client] >= totalServedUsage, "Insufficient usage");
        require(whitelistedTokens[tokenAddress], "Token is not whitelisted");
        require(rewardPerSecond > 0, "Reward per second is not set");
        require(
            tokenBalances[tokenAddress] >= totalPrice,
            "Insufficient token balance"
        );

        clientUsages[client] -= totalServedUsage;
        tokenBalances[tokenAddress] -= totalPrice;

        if (tokenAddress == NATIVE_TOKEN_ADDRESS) {
            (bool success, ) = node.call{value: totalPrice}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(node, totalPrice);
        }

        emit UsageSettledToNode(client, node, totalServedUsage, totalPrice);
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
