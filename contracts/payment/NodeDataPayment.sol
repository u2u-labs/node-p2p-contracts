// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BillValidator.sol";
import "./PaymentProcessor.sol";
import "./lib/LibTypes.sol";
import "../interfaces/INodesStorage.sol";

contract NodeDataPayment is
    BillValidator,
    PaymentProcessor,
    ReentrancyGuard,
    Ownable
{
    using ECDSA for bytes32;

    INodesStorage public nodesStorage;

    mapping(address => uint256) public nonces;

    event FulfillBill(
        address indexed node,
        address indexed client,
        TokenType tokenType,
        address tokenAddress,
        uint256 unitPrice,
        uint256 usedAmount,
        uint256 totalPrice,
        uint256 nonce
    );

    constructor(address nodesStorageAddress)
        BillValidator("NodeDataPayment", "1")
    {
        nodesStorage = INodesStorage(nodesStorageAddress);
    }

    function setNodeStorage(address nodesStorageAddress) external onlyOwner {
        nodesStorage = INodesStorage(nodesStorageAddress);
    }

    function fulfillDataBill(Bill calldata bill, bytes calldata nodeSig)
        external
        payable
        nonReentrant
    {
        address client = bill.client;
        address node = bill.node;
        uint256 nonce = bill.nonce;

        require(msg.sender == client, "Invalid client address");
        require(nodesStorage.isValidNode(node), "Node not registered");

        require(nonce == nonces[client], "Invalid nonce");

        bytes32 digest = hashBill(bill);
        address signer = ECDSA.recover(digest, nodeSig);
        require(signer == node, "Signature mismatch");

        uint256 unitPrice = bill.dataPlan.unitPrice;
        uint256 usedAmount = bill.usedAmount;

        //Mark nonce used. Cient must pay latest bill in order to pay next bill
        nonces[client]++;

        uint256 totalPrice;
        unchecked {
            totalPrice = unitPrice * usedAmount;
        }

        processPayment(client, node, bill.payment, totalPrice);

        emit FulfillBill(
            node,
            client,
            bill.payment.tokenType,
            bill.payment.tokenAddress,
            unitPrice,
            usedAmount,
            totalPrice,
            nonce
        );
    }
}
