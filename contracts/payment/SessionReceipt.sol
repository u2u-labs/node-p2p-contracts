// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/Types.sol";
import "./libraries/LibUsageOrder.sol";
import "./libraries/LibSessionReceipt.sol";
import "../interfaces/INodesStorage.sol";
import "../interfaces/IUsageDepositor.sol";

contract SessionReceipt is ReentrancyGuard, Ownable {
    address public nodesStorage;
    address public usageDepositor;

    mapping(address => mapping(uint256 => LibSessionReceipt.SessionReceipt))
        private sessionsReceipts;
    mapping(address => uint256) private nonces;

    // Efficient tracking of confirmed receipts
    mapping(address => mapping(address => uint256[])) private confirmedNonces;

    event SessionReceiptCreated(
        address client,
        address node,
        uint256 totalSecondsServed,
        address tokenAddress
    );
    event SessionReceiptConfirmed(address client, address node, uint256 nonce);
    event SessionReceiptRedeemed(address client, address node, uint256 nonce);

    modifier onlyValidNode() {
        require(
            INodesStorage(nodesStorage).isValidNode(msg.sender),
            "Node is not whitelisted"
        );
        _;
    }

    constructor(address _nodesStorage, address _usageDepositor) {
        nodesStorage = _nodesStorage;
        usageDepositor = _usageDepositor;
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

    function getConfirmedNonces(
        address client,
        address node
    ) external view returns (uint256[] memory) {
        return confirmedNonces[client][node];
    }

    function getLatestReceipt(
        address client
    ) public view returns (LibSessionReceipt.SessionReceipt memory receipt) {
        if (nonces[client] > 0) {
            uint256 latestReceiptNonce = nonces[client] - 1;
            receipt = sessionsReceipts[client][latestReceiptNonce];
        }
    }

    function createSessionReceipt(
        address client,
        uint256 totalSecondsServed,
        address tokenAddress,
        TokenType tokenType,
        uint256 nonce
    ) external nonReentrant onlyValidNode {
        require(nonce == nonces[client], "Invalid nonce");

        LibSessionReceipt.SessionReceipt
            memory sessionReceipt = LibSessionReceipt.SessionReceipt({
                client: client,
                node: msg.sender,
                totalSecondsServed: totalSecondsServed,
                tokenType: tokenType,
                tokenAddress: tokenAddress,
                status: LibSessionReceipt.SessionReceiptStatus.PENDING,
                nonce: nonce
            });

        sessionsReceipts[client][nonce] = sessionReceipt;
        nonces[client]++;

        emit SessionReceiptCreated(
            client,
            msg.sender,
            totalSecondsServed,
            tokenAddress
        );
    }

    function confirmSessionReceipt(uint256 nonce) external nonReentrant {
        LibSessionReceipt.SessionReceipt
            storage sessionReceipt = sessionsReceipts[msg.sender][nonce];

        require(
            sessionReceipt.client == msg.sender,
            "Only client can confirm receipt"
        );
        require(
            msg.sender == sessionReceipt.client,
            "Only client can confirm receipt"
        );
        require(
            sessionReceipt.status ==
                LibSessionReceipt.SessionReceiptStatus.PENDING,
            "Session receipt is not pending"
        );

        sessionReceipt.status = LibSessionReceipt
            .SessionReceiptStatus
            .CONFIRMED;
        confirmedNonces[msg.sender][sessionReceipt.node].push(nonce);

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
            "Receipt not confirmed"
        );
        require(
            sessionReceipt.node == msg.sender,
            "Not the node in the receipt"
        );

        IUsageDepositor(usageDepositor).settleUsageToNode(
            LibUsageOrder.SettleUsageToNodeRequest({
                client: sessionReceipt.client,
                node: sessionReceipt.node,
                totalServedUsage: sessionReceipt.totalSecondsServed,
                tokenAddress: sessionReceipt.tokenAddress
            })
        );

        sessionReceipt.status = LibSessionReceipt.SessionReceiptStatus.PAID;
        _removeConfirmedNonce(client, msg.sender, nonce);

        emit SessionReceiptRedeemed(client, msg.sender, nonce);
    }

    function _removeConfirmedNonce(
        address client,
        address node,
        uint256 nonce
    ) internal {
        uint256[] storage noncesList = confirmedNonces[client][node];
        for (uint256 i = 0; i < noncesList.length; i++) {
            if (noncesList[i] == nonce) {
                noncesList[i] = noncesList[noncesList.length - 1];
                noncesList.pop();
                break;
            }
        }
    }
}
