import { expect } from "chai";
import { ethers } from "hardhat";
import {
  SessionReceipt,
  NodesStorage,
  UsageDepositor,
} from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ZeroAddress } from "ethers";

describe("SessionReceipt", function () {
  let sessionReceipt: SessionReceipt;
  let nodesStorage: NodesStorage;
  let usageDepositor: UsageDepositor;
  let owner: HardhatEthersSigner;
  let node: HardhatEthersSigner;
  let client: HardhatEthersSigner;
  let otherAccount: HardhatEthersSigner;
  let usageBillingAdmin: HardhatEthersSigner;

  let nodeAddress: string;
  let clientAddress: string;

  const TOKEN_TYPE = {
    NATIVE: 0,
    ERC20: 1,
  };

  const RECEIPT_STATUS = {
    PENDING: 0,
    CONFIRMED: 1,
    PAID: 2,
  };

  beforeEach(async function () {
    // Get signers
    [owner, node, client, usageBillingAdmin, otherAccount] =
      await ethers.getSigners();
    nodeAddress = await node.getAddress();
    clientAddress = await client.getAddress();

    // Deploy mock NodesStorage
    const NodesStorageMock = await ethers.getContractFactory("NodesStorage");
    nodesStorage = await NodesStorageMock.deploy([]);

    // Deploy mock UsageDepositor
    const UsageDepositorMock = await ethers.getContractFactory(
      "UsageDepositor"
    );
    usageDepositor = await UsageDepositorMock.deploy(
      usageBillingAdmin.getAddress(),
      ZeroAddress,
      nodesStorage.target
    );

    // Deploy SessionReceipt contract
    const SessionReceiptFactory = await ethers.getContractFactory(
      "SessionReceipt"
    );
    sessionReceipt = await SessionReceiptFactory.deploy(
      await nodesStorage.getAddress(),
      await usageDepositor.getAddress()
    );

    usageDepositor
      .connect(owner)
      .setSessionReceiptContract(sessionReceipt.getAddress());

    // Whitelist the node in NodesStorage mock
    await nodesStorage.addNodes([nodeAddress]);
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await sessionReceipt.owner()).to.equal(await owner.getAddress());
    });

    it("Should set the correct NodesStorage address", async function () {
      expect(await sessionReceipt.nodesStorage()).to.equal(
        await nodesStorage.getAddress()
      );
    });

    it("Should set the correct UsageDepositor address", async function () {
      expect(await sessionReceipt.usageDepositor()).to.equal(
        await usageDepositor.getAddress()
      );
    });
  });

  describe("Session Receipt Creation", function () {
    it("Should create a session receipt", async function () {
      const totalSecondsServed = BigInt(3600); // 1 hour
      const tokenAddress = ZeroAddress; // ETH address
      const tokenType = TOKEN_TYPE.NATIVE;
      const pricePerSecond = ethers.parseEther("0.0001"); // 0.0001 ETH per second
      const nonce = 0;

      // Create receipt from node
      await expect(
        sessionReceipt
          .connect(node)
          .createSessionReceipt(
            clientAddress,
            totalSecondsServed,
            tokenAddress,
            tokenType,
            pricePerSecond,
            nonce
          )
      )
        .to.emit(sessionReceipt, "SessionReceiptCreated")
        .withArgs(
          clientAddress,
          nodeAddress,
          totalSecondsServed,
          tokenAddress,
          totalSecondsServed * BigInt(pricePerSecond)
        );

      // Verify receipt data
      const receipt = await sessionReceipt.getSessionReceipt(
        clientAddress,
        nonce
      );
      expect(receipt.client).to.equal(clientAddress);
      expect(receipt.node).to.equal(nodeAddress);
      expect(receipt.totalSecondsServed).to.equal(totalSecondsServed);
      expect(receipt.tokenType).to.equal(tokenType);
      expect(receipt.tokenAddress).to.equal(tokenAddress);
      expect(receipt.status).to.equal(RECEIPT_STATUS.PENDING);
      expect(receipt.totalPrice).to.equal(
        totalSecondsServed * BigInt(pricePerSecond)
      );
      expect(receipt.nonce).to.equal(nonce);

      // Verify nonce increment
      expect(await sessionReceipt.getNonce(clientAddress)).to.equal(1);
    });

    it("Should revert if sender is not a valid node", async function () {
      const totalSecondsServed = 3600;
      const tokenAddress = ZeroAddress;
      const tokenType = TOKEN_TYPE.NATIVE;
      const pricePerSecond = ethers.parseEther("0.0001");
      const nonce = 0;

      // Try to create receipt from non-node account
      await expect(
        sessionReceipt
          .connect(client)
          .createSessionReceipt(
            clientAddress,
            totalSecondsServed,
            tokenAddress,
            tokenType,
            pricePerSecond,
            nonce
          )
      ).to.be.revertedWith("Node is not whitelisted");
    });

    it("Should revert if nonce is invalid", async function () {
      const totalSecondsServed = 3600;
      const tokenAddress = ZeroAddress;
      const tokenType = TOKEN_TYPE.NATIVE;
      const pricePerSecond = ethers.parseEther("0.0001");
      const invalidNonce = 1; // Should be 0

      await expect(
        sessionReceipt
          .connect(node)
          .createSessionReceipt(
            clientAddress,
            totalSecondsServed,
            tokenAddress,
            tokenType,
            pricePerSecond,
            invalidNonce
          )
      ).to.be.revertedWith("Invalid nonce");
    });
  });

  describe("Session Receipt Confirmation", function () {
    beforeEach(async function () {
      // Create a receipt first
      const totalSecondsServed = 3600;
      const tokenAddress = ZeroAddress;
      const tokenType = TOKEN_TYPE.NATIVE;
      const pricePerSecond = ethers.parseEther("0.0001");
      const nonce = 0;

      await sessionReceipt
        .connect(node)
        .createSessionReceipt(
          clientAddress,
          totalSecondsServed,
          tokenAddress,
          tokenType,
          pricePerSecond,
          nonce
        );
    });

    it("Should confirm a session receipt", async function () {
      const nonce = 0;

      await expect(sessionReceipt.connect(client).confirmSessionReceipt(nonce))
        .to.emit(sessionReceipt, "SessionReceiptConfirmed")
        .withArgs(clientAddress, nodeAddress, nonce);

      const receipt = await sessionReceipt.getSessionReceipt(
        clientAddress,
        nonce
      );
      expect(receipt.status).to.equal(RECEIPT_STATUS.CONFIRMED);
    });

    it("Should revert if trying to confirm a non-pending receipt", async function () {
      const nonce = 0;

      // Confirm once
      await sessionReceipt.connect(client).confirmSessionReceipt(nonce);

      // Try to confirm again
      await expect(
        sessionReceipt.connect(client).confirmSessionReceipt(nonce)
      ).to.be.revertedWith("Session receipt is not pending");
    });
  });

  describe("Session Receipt Redemption", function () {
    beforeEach(async function () {
      // Create and confirm a receipt first
      await usageDepositor.connect(owner).addWhitelistedTokens([ZeroAddress]);
      const totalSecondsServed = 3600;
      const tokenAddress = ZeroAddress;
      const tokenType = TOKEN_TYPE.NATIVE;
      const pricePerSecond = ethers.parseEther("0.0001");
      const nonce = 0;

      await sessionReceipt
        .connect(node)
        .createSessionReceipt(
          clientAddress,
          totalSecondsServed,
          tokenAddress,
          tokenType,
          pricePerSecond,
          nonce
        );

      await sessionReceipt.connect(client).confirmSessionReceipt(nonce);
    });

    it("Should redeem a confirmed receipt", async function () {
      const nonce = 0;

      // Redeem the receipt
      await sessionReceipt.connect(node).redeemReceipt(clientAddress, nonce);

      // Check status changed to PAID
      const receiptAfter = await sessionReceipt.getSessionReceipt(
        clientAddress,
        nonce
      );
      expect(receiptAfter.status).to.equal(RECEIPT_STATUS.PAID);
    });

    it("Should revert if trying to redeem a non-confirmed receipt", async function () {
      // Create a new receipt without confirming it
      const totalSecondsServed = 1800;
      const tokenAddress = ZeroAddress;
      const tokenType = TOKEN_TYPE.NATIVE;
      const pricePerSecond = ethers.parseEther("0.0001");
      const nonce = 1;

      await sessionReceipt
        .connect(node)
        .createSessionReceipt(
          clientAddress,
          totalSecondsServed,
          tokenAddress,
          tokenType,
          pricePerSecond,
          nonce
        );

      // Try to redeem without confirming
      await expect(
        sessionReceipt.connect(node).redeemReceipt(clientAddress, nonce)
      ).to.be.revertedWith("Session receipt is not confirmed");
    });

    it("Should revert if non-node tries to redeem", async function () {
      const nonce = 0;

      // Try to redeem from a different node
      await expect(
        sessionReceipt.connect(otherAccount).redeemReceipt(clientAddress, nonce)
      ).to.be.revertedWith("Node is not whitelisted");
    });

    it("Should revert if different node tries to redeem", async function () {
      const nonce = 0;

      // Whitelist another account as a node
      const otherNodeAddress = await otherAccount.getAddress();
      await nodesStorage.addNodes([otherNodeAddress]);

      // Try to redeem from a different node
      await expect(
        sessionReceipt.connect(otherAccount).redeemReceipt(clientAddress, nonce)
      ).to.be.revertedWith("Sender is not node in session's receipt");
    });
  });

  describe("Multiple Session Receipts", function () {
    it("Should handle multiple receipts for the same client", async function () {
      // Create first receipt
      await sessionReceipt.connect(node).createSessionReceipt(
        clientAddress,
        3600, // 1 hour
        ZeroAddress,
        TOKEN_TYPE.NATIVE,
        ethers.parseEther("0.0001"),
        0
      );

      // Create second receipt
      await sessionReceipt.connect(node).createSessionReceipt(
        clientAddress,
        1800, // 30 minutes
        ZeroAddress,
        TOKEN_TYPE.NATIVE,
        ethers.parseEther("0.0002"),
        1
      );

      // Verify both receipts
      const receipt1 = await sessionReceipt.getSessionReceipt(clientAddress, 0);
      const receipt2 = await sessionReceipt.getSessionReceipt(clientAddress, 1);

      expect(receipt1.totalSecondsServed).to.equal(3600);
      expect(receipt2.totalSecondsServed).to.equal(1800);
      expect(receipt1.totalPrice).to.equal(
        BigInt(3600) * BigInt(ethers.parseEther("0.0001"))
      );
      expect(receipt2.totalPrice).to.equal(
        BigInt(1800) * BigInt(ethers.parseEther("0.0002"))
      );

      // Verify nonce increment
      expect(await sessionReceipt.getNonce(clientAddress)).to.equal(2);
    });
  });
});
