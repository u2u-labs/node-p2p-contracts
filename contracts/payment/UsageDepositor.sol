// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/Types.sol";
import "./libraries/LibUsageOrder.sol";
import "./libraries/LibSessionReceipt.sol";
import "./UsageOrderValidator.sol";
import "../interfaces/INodesStorage.sol";

contract UsageDepositor is
    ReentrancyGuard,
    Ownable,
    UsageOrderValidator
{
    using SafeERC20 for IERC20;

    INodesStorage private nodesStorage;

    address private usageBillingAdmin;
    address private sessionReceiptContract;
    mapping(address => uint256) private tokenBalances;
    mapping(address => uint256) private clientUsages;
    mapping(address => uint256) private nonces;

    event UsagePurchased(address client, uint256 totalPrice, uint256 usage);
    event UsageSettledToNode(
        address client,
        address node,
        uint256 totalServedUsage,
        uint256 totalToken
    );

    modifier onlySessionReceiptContract() {
        require(
            msg.sender == sessionReceiptContract,
            "Only SessionReceiptContract can call this function"
        );
        _;
    }

    constructor(
        address _usageBillingAdmin,
        address _sessionReceiptContract,
        address _nodesStorage
    ) UsageOrderValidator("NodeDataPayment", "1") {
        usageBillingAdmin = _usageBillingAdmin;
        sessionReceiptContract = _sessionReceiptContract;
        nodesStorage = INodesStorage(_nodesStorage);
    }

    function getNonce(address client) public view returns (uint256) {
        return nonces[client];
    }

    function getClientUsage(address client) public view returns (uint256) {
        return clientUsages[client];
    }

    function setUsageBillingAdmin(address _usageBillingAdmin) public onlyOwner {
        require(
            _usageBillingAdmin != address(0),
            "Invalid usage billing admin"
        );
        usageBillingAdmin = _usageBillingAdmin;
    }

    function setSessionReceiptContract(
        address _sessionReceiptContract
    ) public onlyOwner {
        sessionReceiptContract = _sessionReceiptContract;
    }

    function setNodesStorage(address _nodesStorage) public onlyOwner {
        require(_nodesStorage != address(0), "Invalid nodes storage address");
        nodesStorage = INodesStorage(_nodesStorage);
    }

    function purchaseUsage(
        LibUsageOrder.UsageOrder calldata usageOrder
    ) external payable nonReentrant {
        address client = usageOrder.client;
        uint256 requestedSeconds = usageOrder.requestedSeconds;
        uint256 totalPrice = usageOrder.totalPrice;
        TokenType tokenType = usageOrder.tokenType;
        address tokenAddress = usageOrder.tokenAddress;
        bytes memory usageBillingAdminSig = usageOrder.usageBillingAdminSig;
        uint256 nonce = usageOrder.nonce;

        require(client == msg.sender, "Client is not the caller");
        require(
            requestedSeconds > 0,
            "Requested seconds must be greater than 0"
        );

        bytes32 digest = hashUsageOrder(usageOrder);
        address signer = ECDSA.recover(digest, usageBillingAdminSig);
        require(
            signer == usageBillingAdmin,
            "Signer is not usage billing admin"
        );

        require(nonce == nonces[msg.sender], "Invalid nonce");
        nonces[msg.sender]++;

        if (tokenType == TokenType.NATIVE) {
            require(msg.value == totalPrice, "Incorrect amount of native sent");
            tokenBalances[address(0)] += totalPrice;
        } else {
            IERC20(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                totalPrice
            );
            tokenBalances[tokenAddress] += totalPrice;
        }

        clientUsages[msg.sender] += requestedSeconds;
        emit UsagePurchased(msg.sender, totalPrice, requestedSeconds);
    }

    function settleUsageToNode(
        address client,
        address node,
        uint256 totalServedUsage,
        address tokenAddress,
        uint256 totalToken
    ) external onlySessionReceiptContract nonReentrant {
        require(nodesStorage.isValidNode(node), "Invalid node address");
        require(clientUsages[client] >= totalServedUsage, "Insufficient usage");

        require(
            tokenBalances[tokenAddress] >= totalToken,
            "Insufficient token balance"
        );

        clientUsages[client] -= totalServedUsage;
        tokenBalances[tokenAddress] -= totalToken;

        if (tokenAddress == address(0)) {
            (bool success, ) = node.call{value: totalToken}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(node, totalToken);
        }

        emit UsageSettledToNode(client, node, totalServedUsage, totalToken);
    }
}
