// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./SessionValidator.sol";
import "./libraries/Types.sol";
import "../interfaces/INodesStorage.sol";
import "../interfaces/IVault.sol";
import "../libraries/BokkyPooBahsDateTimeLibrary.sol";

contract NodeDataPayment is SessionValidator, ReentrancyGuard, AccessControl {
    INodesStorage public nodesStorage;
    IVault public vault;

    mapping(address => LibSession.Session) private sessions;

    mapping(address => uint256) public nonces;

    event SessionStarted(
        address indexed node,
        address indexed client,
        uint256 timestamp,
        uint256 nonce
    );

    event SessionEnded(
        address indexed node,
        address indexed client,
        uint256 timestamp,
        uint256 nonce
    );

    constructor(
        address admin,
        address nodesStorageAddress,
        address vaultAddress
    ) SessionValidator("NodeDataPayment", "1") {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        nodesStorage = INodesStorage(nodesStorageAddress);
        vault = IVault(vaultAddress);
    }

    function setNodeStorage(
        address nodesStorageAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        nodesStorage = INodesStorage(nodesStorageAddress);
    }

    function setVault(
        address vaultAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vault = IVault(vaultAddress);
    }

    function getSession(
        address client
    ) external view returns (LibSession.Session memory session) {
        return sessions[client];
    }

    function startSession(
        LibSession.Session calldata session,
        bytes calldata nodeSig
    ) external {
        address node = session.node;

        require(nodesStorage.isValidNode(node), "Node not registered");
        require(
            sessions[msg.sender].node == address(0),
            "Session already started"
        );
        require(session.nonce == nonces[msg.sender], "Invalid session nonce");

        bytes32 digest = hashSession(session);
        address signer = ECDSA.recover(digest, nodeSig);
        require(signer == node, "Signature mismatch");

        sessions[msg.sender] = session;
        nonces[msg.sender]++;

        emit SessionStarted(
            node,
            msg.sender,
            session.startTimestamp,
            session.nonce
        );
    }

    function endSession(
        address client,
        uint256 usedDataAmount
    ) external nonReentrant {
        require(
            nodesStorage.isValidNode(msg.sender),
            "Caller is not a node or not registered"
        );

        LibSession.Session storage session = sessions[client];

        require(session.node == msg.sender, "Invalid session");
        require(
            block.timestamp >= session.startTimestamp,
            "Start timestamp is in future"
        );

        uint256 sessionDuration = block.timestamp - session.startTimestamp;

        require(
            sessionDuration >= BokkyPooBahsDateTimeLibrary.SECONDS_PER_DAY,
            "Session duration must be at least 1 day"
        );

        uint256 totalPrice = session.payment.unitPrice * usedDataAmount;

        processPayment(client, session.node, session.payment, totalPrice);

        emit SessionEnded(session.node, client, block.timestamp, session.nonce);

        delete sessions[client];
    }

    function processPayment(
        address payer,
        address receiver,
        LibPayment.Payment memory payment,
        uint256 amount
    ) internal {
        bool success = vault.transfer(
            payer,
            receiver,
            payment.tokenAddress,
            amount
        );
        require(success, "Payment transfer failed");
    }
}
