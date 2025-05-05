// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/Types.sol";
import "./libraries/LibUsageOrder.sol";
import "./libraries/LibSessionReceipt.sol";
import "../interfaces/INodesStorage.sol";

contract UsageDepositor is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

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
    ) external payable nonReentrant {
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
            require(tokenAddress == address(0), "Invalid native token address");
            require(msg.value == totalPrice, "Incorrect amount of native sent");
        } else {
            require(tokenAddress != address(0), "Invalid ERC20 token address");
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
        address client,
        address node,
        uint256 totalServedUsage,
        address tokenAddress
    ) external onlySessionReceiptContract nonReentrant {
        uint256 rewardPerSecond = rewardPerSecondPerToken[tokenAddress];

        require(whitelistedTokens[tokenAddress], "Token is not whitelisted");
        require(rewardPerSecond > 0, "Reward per second is not set");

        bool isValidNode = INodesStorage(nodesStorage).isValidNode(node);
        require(isValidNode, "Invalid node address");
        require(clientUsages[client] >= totalServedUsage, "Insufficient usage");

        uint256 totalPrice = totalServedUsage * rewardPerSecond;

        require(
            tokenBalances[tokenAddress] >= totalPrice,
            "Insufficient token balance"
        );

        clientUsages[client] -= totalServedUsage;
        tokenBalances[tokenAddress] -= totalPrice;

        if (tokenAddress == address(0)) {
            (bool success, ) = node.call{value: totalPrice}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(node, totalPrice);
        }

        emit UsageSettledToNode(client, node, totalServedUsage, totalPrice);
    }
}
