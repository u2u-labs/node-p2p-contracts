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
    mapping(address => mapping(address => uint256[])) private confirmedNonces;
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        private confirmedNonceIndex;

    event SessionReceiptCreated(
        address indexed client,
        address indexed node,
        uint256 totalServedBytes,
        address tokenAddress,
        uint256 nonce
    );
    event SessionReceiptConfirmed(
        address indexed client,
        address indexed node,
        uint256 nonce
    );
    event SessionReceiptRedeemed(
        address indexed client,
        address indexed node,
        uint256 nonce
    );
    event SessionReceiptRejected(
        address indexed client,
        address indexed node,
        uint256 nonce
    );

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

    /**
     * @notice  Set nodes storage address (called by owner)
     * @param _nodesStorage Nodes storage address
     */
    function setNodesStorage(address _nodesStorage) external onlyOwner {
        require(_nodesStorage != address(0), "Invalid address");
        nodesStorage = _nodesStorage;
    }

    /**
     * @notice Set usage depositor address (called by owner)
     * @param _usageDepositor Usage depositor address
     */
    function setUsageDepositor(address _usageDepositor) external onlyOwner {
        require(_usageDepositor != address(0), "Invalid address");
        usageDepositor = _usageDepositor;
    }

    /**
     * @notice Get session receipt of client by nonce
     * @param client Client address
     * @param nonce Receipt's nonce
     */
    function getSessionReceipt(
        address client,
        uint256 nonce
    ) external view returns (LibSessionReceipt.SessionReceipt memory) {
        return sessionsReceipts[client][nonce];
    }

    /**
     * @notice Get client latest nonce
     * @param client Client address
     */
    function getNonce(address client) external view returns (uint256) {
        return nonces[client];
    }

    /**
     * @notice Get list of confirmed receipts nonces
     * @param client Client address
     * @param node Node address
     */
    function getConfirmedNonces(
        address client,
        address node
    ) external view returns (uint256[] memory) {
        return confirmedNonces[client][node];
    }

    /**
     * @notice Get client's latest receipt
     * @param client Client address
     */
    function getLatestReceipt(
        address client
    ) public view returns (LibSessionReceipt.SessionReceipt memory receipt) {
        if (nonces[client] > 0) {
            uint256 latestReceiptNonce = nonces[client] - 1;
            receipt = sessionsReceipts[client][latestReceiptNonce];
        }
    }

    /**
     * @notice Create session receipt (called by whitelisted nodes)
     * @param client Client address that node serves
     * @param totalServedBytes Total served bytes by node for given client
     * @param tokenAddress Token address of reward token
     * @param tokenType Token type of reward token
     * @param nonce Latest nonce of client (unused nonce)
     */
    function createSessionReceipt(
        address client,
        uint256 totalServedBytes,
        address tokenAddress,
        TokenType tokenType,
        uint256 nonce
    ) external nonReentrant onlyValidNode {
        require(nonce == nonces[client], "Invalid nonce");

        LibSessionReceipt.SessionReceipt
            memory sessionReceipt = LibSessionReceipt.SessionReceipt({
                client: client,
                node: msg.sender,
                totalServedBytes: totalServedBytes,
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
            totalServedBytes,
            tokenAddress,
            nonce
        );
    }

    /**
     * @notice Confirm session receipt (change status of receipt to CONFIRMED) (called by client)
     * @param nonce Receipt's nonce
     */
    function confirmSessionReceipt(uint256 nonce) external nonReentrant {
        LibSessionReceipt.SessionReceipt
            storage sessionReceipt = sessionsReceipts[msg.sender][nonce];

        require(
            sessionReceipt.client == msg.sender,
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
        uint256 idx = confirmedNonces[msg.sender][sessionReceipt.node].length;
        confirmedNonces[msg.sender][sessionReceipt.node].push(nonce);
        confirmedNonceIndex[msg.sender][sessionReceipt.node][nonce] = idx;

        emit SessionReceiptConfirmed(
            sessionReceipt.client,
            sessionReceipt.node,
            sessionReceipt.nonce
        );
    }

    /**
     * @notice Reject session receipt (change status of receipt to REJECTED) (called by client)
     * @param nonce Receipt's nonce
     */
    function rejectSessionReceipt(uint256 nonce) external nonReentrant {
        LibSessionReceipt.SessionReceipt
            storage sessionReceipt = sessionsReceipts[msg.sender][nonce];

        require(
            sessionReceipt.client == msg.sender,
            "Only client can reject receipt"
        );
        require(
            sessionReceipt.status ==
                LibSessionReceipt.SessionReceiptStatus.PENDING,
            "Session receipt is not pending"
        );

        sessionReceipt.status = LibSessionReceipt.SessionReceiptStatus.EMPTY;

        emit SessionReceiptRejected(
            sessionReceipt.client,
            sessionReceipt.node,
            sessionReceipt.nonce
        );
    }

    /**
     * @notice Redeem receipt (change status of receipt to PAID, node receive rewards) (called by whitelisted nodes)
     * @param client Receipt's client address
     * @param nonce Receipt's nonce
     */
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
                totalServedBytes: sessionReceipt.totalServedBytes,
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
        mapping(uint256 => uint256) storage indexMap = confirmedNonceIndex[
            client
        ][node];

        uint256 index = indexMap[nonce];
        uint256 lastIndex = noncesList.length - 1;

        if (index != lastIndex) {
            uint256 lastNonce = noncesList[lastIndex];
            noncesList[index] = lastNonce;
            indexMap[lastNonce] = index;
        }

        noncesList.pop();
        delete indexMap[nonce];
    }
}
