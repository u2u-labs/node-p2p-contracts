// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/Types.sol";
import "./SessionReceiptValidator.sol";
import "../interfaces/INodesStorage.sol";
import "../interfaces/IUsageDepositor.sol";

contract SessionReceipt is ReentrancyGuard, Ownable, SessionReceiptValidator {
    INodesStorage public nodesStorage;
    IUsageDepositor public usageDepositor;

    mapping(address => mapping(uint256 => LibSessionReceipt.SessionReceipt))
        private sessionsReceipts;
    mapping(address => uint256) private nonces;

    event SessionReceiptCreated(
        address client,
        address node,
        uint256 totalSecondsServed,
        address tokenAddress,
        uint256 totalPrice
    );

    event SessionReceiptConfirmed(address client, address node, uint256 nonce);

    modifier onlyValidNode() {
        require(
            nodesStorage.isValidNode(msg.sender),
            "Node is not whitelisted"
        );
        _;
    }

    constructor(
        address _nodesStorage,
        address _usageDepositor
    ) SessionReceiptValidator("SessionReceipt", "1") {
        nodesStorage = INodesStorage(_nodesStorage);
        usageDepositor = IUsageDepositor(_usageDepositor);
    }

    function getSessionReceipt(
        address client,
        uint256 nonce
    ) external view returns (LibSessionReceipt.SessionReceipt memory) {
        return sessionsReceipts[client][nonce];
    }

    function getNonce(address client) external view returns (uint256) {
        return nonces[client];
    }

    function createSessionReceipt(
        address client,
        uint256 totalSecondsServed,
        address tokenAddress,
        TokenType tokenType,
        uint256 pricePerSecond,
        uint256 nonce
    ) external nonReentrant onlyValidNode {
        require(nonce == nonces[client], "Invalid nonce");

        uint256 totalPrice = totalSecondsServed * pricePerSecond;

        LibSessionReceipt.SessionReceipt
            memory sessionReceipt = LibSessionReceipt.SessionReceipt({
                client: client,
                node: msg.sender,
                totalSecondsServed: totalSecondsServed,
                tokenType: tokenType,
                tokenAddress: tokenAddress,
                status: LibSessionReceipt.SessionReceiptStatus.PENDING,
                totalPrice: totalPrice,
                nonce: nonce
            });

        sessionsReceipts[client][nonce] = sessionReceipt;
        nonces[client]++;

        emit SessionReceiptCreated(
            client,
            msg.sender,
            totalSecondsServed,
            tokenAddress,
            totalPrice
        );
    }

    function confirmSessionReceipt(uint256 nonce) external nonReentrant {
        LibSessionReceipt.SessionReceipt
            storage sessionReceipt = sessionsReceipts[msg.sender][nonce];

        require(
            sessionReceipt.status ==
                LibSessionReceipt.SessionReceiptStatus.PENDING,
            "Session receipt is not pending"
        );

        sessionReceipt.status = LibSessionReceipt
            .SessionReceiptStatus
            .CONFIRMED;

        emit SessionReceiptConfirmed(
            sessionReceipt.client,
            sessionReceipt.node,
            sessionReceipt.nonce
        );
    }

    function redeemReceipt(
        address client,
        uint256 nonce
    ) external onlyValidNode nonReentrant {
        LibSessionReceipt.SessionReceipt
            storage sessionReceipt = sessionsReceipts[client][nonce];

        require(
            sessionReceipt.status ==
                LibSessionReceipt.SessionReceiptStatus.CONFIRMED,
            "Session receipt is not confirmed"
        );
        require(
            sessionReceipt.node == msg.sender,
            "Sender is not node in session's receipt"
        );

        // Move external call before the state update
        usageDepositor.settleUsageToNode(
            sessionReceipt.client,
            sessionReceipt.node,
            sessionReceipt.totalSecondsServed,
            sessionReceipt.tokenAddress,
            sessionReceipt.totalPrice
        );

        sessionReceipt.status = LibSessionReceipt.SessionReceiptStatus.PAID;
    }
}
