import { expect } from "chai";
import { ethers } from "hardhat";
import {
  BigNumberish,
  Contract,
  ContractFactory,
  TypedDataDomain,
  ZeroAddress,
} from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import {
  MockERC20,
  MockERC20__factory,
  NodesStorage,
  NodesStorage__factory,
  UsageDepositor,
  UsageDepositor__factory,
} from "../typechain-types";

describe("UsageDepositor", function () {
  let UsageDepositor: UsageDepositor__factory;
  let MockERC20: MockERC20__factory;
  let MockNodesStorage: NodesStorage__factory;
  let usageDepositor: UsageDepositor;
  let mockERC20: MockERC20;
  let mockNodesStorage: NodesStorage;
  let owner: HardhatEthersSigner;
  let client: HardhatEthersSigner;
  let node: HardhatEthersSigner;
  let usageBillingAdmin: HardhatEthersSigner;
  let sessionReceiptContract: HardhatEthersSigner;
  let otherAccount: HardhatEthersSigner;

  // EIP-712 domain parameters
  const DOMAIN_NAME = "UsageDepositor";
  const DOMAIN_VERSION = "1";
  const USAGE_ORDER_TYPE = {
    UsageOrder: [
      { name: "client", type: "address" },
      { name: "tokenType", type: "uint8" },
      { name: "tokenAddress", type: "address" },
      { name: "requestedSeconds", type: "uint256" },
      { name: "totalPrice", type: "uint256" },
      { name: "nonce", type: "uint256" },
    ],
  };

  beforeEach(async function () {
    [
      owner,
      client,
      node,
      usageBillingAdmin,
      sessionReceiptContract,
      otherAccount,
    ] = await ethers.getSigners();

    // Deploy mock ERC20 token
    MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = await MockERC20.deploy("Mock Token", "MTK", 18);
    await mockERC20.waitForDeployment();

    // Mint some tokens to the client
    await mockERC20.mint(client.address, ethers.parseEther("1000"));

    // Deploy mock NodesStorage
    MockNodesStorage = await ethers.getContractFactory("NodesStorage");
    mockNodesStorage = await MockNodesStorage.deploy([]);
    await mockNodesStorage.waitForDeployment();

    // Register node as valid
    await mockNodesStorage.addNodes([node.address]);

    // Deploy UsageDepositor
    UsageDepositor = await ethers.getContractFactory("UsageDepositor");
    usageDepositor = await UsageDepositor.deploy(
      usageBillingAdmin.address,
      sessionReceiptContract.address,
      mockNodesStorage.target
    );
    await usageDepositor.waitForDeployment();
  });

  describe("Initialization", function () {
    it("Should set the correct owner", async function () {
      expect(await usageDepositor.owner()).to.equal(owner.address);
    });

    it("Should initialize with correct admin addresses", async function () {
      // We'll test by updating the admin
      await usageDepositor.setUsageBillingAdmin(otherAccount.address);

      // Create a usage order to test with the new admin
      const nonce = await usageDepositor.getNonce(client.address);
      const requestedSeconds = 3600;
      const totalPrice = ethers.parseEther("10");

      const orderData = {
        client: client.address,
        requestedSeconds,
        totalPrice,
        tokenType: TokenType.ERC20,
        tokenAddress: mockERC20.target,
        nonce,
      };

      // Create the digest for signing
      const domain: any = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target,
      };

      // Sign with the new admin
      const signature = await otherAccount.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      // Complete the usage order with signature
      const usageOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };

      // Approve tokens for the contract
      await mockERC20
        .connect(client)
        .approve(usageDepositor.target, totalPrice);

      // This should succeed with the new admin
      await expect(
        usageDepositor.connect(client).purchaseUsage(usageOrder)
      ).to.emit(usageDepositor, "UsagePurchased");
    });
  });

  describe("Admin functions", function () {
    it("Should allow owner to change usage billing admin", async function () {
      await usageDepositor.setUsageBillingAdmin(otherAccount.address);
      // Validation done in another test
    });

    it("Should not allow non-owner to change usage billing admin", async function () {
      await expect(
        usageDepositor
          .connect(otherAccount)
          .setUsageBillingAdmin(otherAccount.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should not allow setting zero address as usage billing admin", async function () {
      await expect(
        usageDepositor.setUsageBillingAdmin(ZeroAddress)
      ).to.be.revertedWith("Invalid usage billing admin");
    });

    it("Should allow owner to change session receipt contract", async function () {
      await usageDepositor.setSessionReceiptContract(otherAccount.address);
      await usageDepositor.addWhitelistedTokens([mockERC20.target]);
      // No direct getter, but can be tested via the modifier functionality
      const requestedSeconds = 3600;
      const totalPrice = ethers.parseEther("10");

      // First have client purchase some usage
      await purchaseUsageHelper(
        client,
        requestedSeconds,
        totalPrice,
        TokenType.ERC20,
        mockERC20.target as any
      );

      // Try settling with the new session receipt contract
      await expect(
        usageDepositor
          .connect(otherAccount)
          .settleUsageToNode(
            client.address,
            node.address,
            requestedSeconds / 2,
            mockERC20.target,
            totalPrice / BigInt(2)
          )
      ).to.not.be.revertedWith(
        "Only SessionReceiptContract can call this function"
      );
    });

    it("Should allow owner to change nodes storage address", async function () {
      const newMockNodesStorage = await MockNodesStorage.deploy([]);
      await newMockNodesStorage.waitForDeployment();

      await usageDepositor.setNodesStorage(newMockNodesStorage.target);

      // Add the node to the new storage
      await newMockNodesStorage.addNodes([node.address]);

      // Purchase usage
      const requestedSeconds = 3600;
      const totalPrice = ethers.parseEther("10");
      await purchaseUsageHelper(
        client,
        requestedSeconds,
        totalPrice,
        TokenType.ERC20,
        mockERC20.target as any
      );

      // Settlement should succeed with the new nodes storage
      await expect(
        usageDepositor
          .connect(sessionReceiptContract)
          .settleUsageToNode(
            client.address,
            node.address,
            requestedSeconds / 2,
            mockERC20.target,
            totalPrice / BigInt(2)
          )
      ).to.not.be.revertedWith("Invalid node address");
    });

    it("Should not allow setting zero address as nodes storage", async function () {
      await expect(
        usageDepositor.setNodesStorage(ZeroAddress)
      ).to.be.revertedWith("Invalid nodes storage address");
    });
  });

  describe("purchaseUsage", function () {
    const requestedSeconds = 3600; // 1 hour
    const totalPrice = ethers.parseEther("10");
    let nonce: number;
    let usageOrder: any;

    beforeEach(async function () {
      nonce = 0; // First transaction for the client

      // Approve tokens for the contract
      await mockERC20
        .connect(client)
        .approve(usageDepositor.target, totalPrice);

      // Create a usage order without signature
      const orderData = {
        client: client.address,
        requestedSeconds,
        totalPrice,
        tokenType: TokenType.ERC20,
        tokenAddress: mockERC20.target,
        nonce,
      };

      // Create the domain separator for EIP-712
      const domain: TypedDataDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target as any,
      };

      // Sign the order with EIP-712
      const signature = await usageBillingAdmin.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      // Complete the usage order with signature
      usageOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };
    });

    it("Should allow client to purchase usage with ERC20 tokens", async function () {
      await expect(usageDepositor.connect(client).purchaseUsage(usageOrder))
        .to.emit(usageDepositor, "UsagePurchased")
        .withArgs(client.address, totalPrice, requestedSeconds);

      // Verify client usage increased
      expect(await usageDepositor.getClientUsage(client.address)).to.equal(
        requestedSeconds
      );

      // Verify nonce increased
      expect(await usageDepositor.getNonce(client.address)).to.equal(1);
    });

    it("Should allow client to purchase usage with native token", async function () {
      // Create a new usage order for native token payment
      const orderData = {
        client: client.address,
        requestedSeconds,
        totalPrice,
        tokenType: TokenType.NATIVE,
        tokenAddress: ZeroAddress,
        nonce,
      };

      // Create the domain separator for EIP-712
      const domain: TypedDataDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target as any,
      };

      // Sign with EIP-712
      const signature = await usageBillingAdmin.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      const nativeUsageOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };

      await expect(
        usageDepositor
          .connect(client)
          .purchaseUsage(nativeUsageOrder, { value: totalPrice })
      )
        .to.emit(usageDepositor, "UsagePurchased")
        .withArgs(client.address, totalPrice, requestedSeconds);

      // Verify client usage increased
      expect(await usageDepositor.getClientUsage(client.address)).to.equal(
        requestedSeconds
      );
    });

    it("Should reject if signer is not usage billing admin", async function () {
      // Sign with wrong account
      const orderData = {
        client: client.address,
        requestedSeconds,
        totalPrice,
        tokenType: TokenType.ERC20,
        tokenAddress: mockERC20.target,
        nonce,
      };

      const domain: TypedDataDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target as any,
      };

      // Use wrong signer
      const signature = await otherAccount.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      const invalidOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };

      await expect(
        usageDepositor.connect(client).purchaseUsage(invalidOrder)
      ).to.be.revertedWith("Signer is not usage billing admin");
    });

    it("Should reject if caller is not the client in the order", async function () {
      await expect(
        usageDepositor.connect(otherAccount).purchaseUsage(usageOrder)
      ).to.be.revertedWith("Client is not the caller");
    });

    it("Should reject if requested seconds is zero", async function () {
      const orderData = {
        client: client.address,
        requestedSeconds: 0, // Invalid value
        totalPrice,
        tokenType: TokenType.ERC20,
        tokenAddress: mockERC20.target,
        nonce,
      };

      const domain: TypedDataDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target as any,
      };

      const signature = await usageBillingAdmin.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      const invalidOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };

      await expect(
        usageDepositor.connect(client).purchaseUsage(invalidOrder)
      ).to.be.revertedWith("Requested seconds must be greater than 0");
    });

    it("Should reject if nonce is invalid", async function () {
      const orderData = {
        client: client.address,
        requestedSeconds,
        totalPrice,
        tokenType: TokenType.ERC20,
        tokenAddress: mockERC20.target,
        nonce: 1, // Invalid nonce, should be 0 for first transaction
      };

      const domain: TypedDataDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target as any,
      };

      const signature = await usageBillingAdmin.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      const invalidOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };

      await expect(
        usageDepositor.connect(client).purchaseUsage(invalidOrder)
      ).to.be.revertedWith("Invalid nonce");
    });

    it("Should reject if sent native token amount is incorrect", async function () {
      // Create native token order
      const orderData = {
        client: client.address,
        requestedSeconds,
        totalPrice,
        tokenType: TokenType.NATIVE,
        tokenAddress: ZeroAddress,
        nonce,
      };

      const domain: TypedDataDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target as any,
      };

      const signature = await usageBillingAdmin.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      const nativeOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };

      // Send incorrect amount
      await expect(
        usageDepositor
          .connect(client)
          .purchaseUsage(nativeOrder, { value: totalPrice - BigInt(1) })
      ).to.be.revertedWith("Incorrect amount of native sent");
    });

    it("Should handle multiple purchases correctly", async function () {
      // First purchase
      await usageDepositor.connect(client).purchaseUsage(usageOrder);

      await mockERC20.connect(client).approve(usageDepositor.target, totalPrice);

      // Second purchase with incremented nonce
      const orderData = {
        client: client.address,
        requestedSeconds,
        totalPrice,
        tokenType: TokenType.ERC20,
        tokenAddress: mockERC20.target,
        nonce: 1, // Incremented nonce
      };

      const domain: TypedDataDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: usageDepositor.target as any,
      };

      const signature = await usageBillingAdmin.signTypedData(
        domain,
        USAGE_ORDER_TYPE,
        orderData
      );

      const secondOrder = {
        ...orderData,
        usageBillingAdminSig: signature,
      };

      await usageDepositor.connect(client).purchaseUsage(secondOrder);

      // Verify client usage increased correctly
      expect(await usageDepositor.getClientUsage(client.address)).to.equal(
        requestedSeconds * 2
      );

      // Verify nonce increased
      expect(await usageDepositor.getNonce(client.address)).to.equal(2);
    });
  });

  describe("settleUsageToNode", async function () {
    const requestedSeconds = 3600; // 1 hour
    const totalPrice = ethers.parseEther("10");
    const servedUsage = 1800; // Half hour actually used
    const paymentAmount = ethers.parseEther("5"); // Half of the payment

    await usageDepositor.connect(owner).addWhitelistedTokens([mockERC20.target]);

    beforeEach(async function () {
      // First have client purchase some usage
      await purchaseUsageHelper(
        client,
        requestedSeconds,
        totalPrice,
        TokenType.ERC20,
        mockERC20.target as any
      );
    });

    it("Should settle ERC20 tokens to node correctly", async function () {
      const nodeBefore = await mockERC20.balanceOf(node.address);

      await expect(
        usageDepositor
          .connect(sessionReceiptContract)
          .settleUsageToNode(
            client.address,
            node.address,
            servedUsage,
            mockERC20.target,
            paymentAmount
          )
      )
        .to.emit(usageDepositor, "UsageSettledToNode")
        .withArgs(client.address, node.address, servedUsage, paymentAmount);

      // Verify client's remaining usage
      expect(await usageDepositor.getClientUsage(client.address)).to.equal(
        requestedSeconds - servedUsage
      );

      // Verify node received tokens
      const nodeAfter = await mockERC20.balanceOf(node.address);
      expect(nodeAfter - nodeBefore).to.equal(paymentAmount);
    });

    it("Should settle native tokens to node correctly", async function () {
      // First have client purchase some usage with native token
      await purchaseUsageHelper(
        client,
        requestedSeconds,
        totalPrice,
        TokenType.NATIVE,
        ZeroAddress
      );

      // Get node's balance before settlement
      const nodeBefore = await ethers.provider.getBalance(node.address);

      await expect(
        usageDepositor.connect(sessionReceiptContract).settleUsageToNode(
          client.address,
          node.address,
          servedUsage,
          ZeroAddress, // Native token
          paymentAmount
        )
      )
        .to.emit(usageDepositor, "UsageSettledToNode")
        .withArgs(client.address, node.address, servedUsage, paymentAmount);

      // Verify client's remaining usage
      const expectedRemainingUsage = requestedSeconds * 2 - servedUsage; // From both purchases
      expect(await usageDepositor.getClientUsage(client.address)).to.equal(
        expectedRemainingUsage
      );

      // Verify node received native tokens
      const nodeAfter = await ethers.provider.getBalance(node.address);
      expect(nodeAfter - nodeBefore).to.equal(paymentAmount);
    });

    it("Should reject settlement if caller is not session receipt contract", async function () {
      await expect(
        usageDepositor
          .connect(otherAccount)
          .settleUsageToNode(
            client.address,
            node.address,
            servedUsage,
            mockERC20.target,
            paymentAmount
          )
      ).to.be.revertedWith(
        "Only SessionReceiptContract can call this function"
      );
    });

    it("Should reject settlement if node is not valid", async function () {
      // Remove node from valid nodes list
      await mockNodesStorage.removeNode(node.address);

      await expect(
        usageDepositor
          .connect(sessionReceiptContract)
          .settleUsageToNode(
            client.address,
            node.address,
            servedUsage,
            mockERC20.target,
            paymentAmount
          )
      ).to.be.revertedWith("Invalid node address");
    });

    it("Should reject settlement if client does not have enough usage", async function () {
      const excessiveUsage = requestedSeconds + 1;

      await expect(
        usageDepositor
          .connect(sessionReceiptContract)
          .settleUsageToNode(
            client.address,
            node.address,
            excessiveUsage,
            mockERC20.target,
            paymentAmount
          )
      ).to.be.revertedWith("Insufficient usage");
    });

    it("Should reject settlement if contract does not have enough tokens", async function () {
      const excessivePayment = totalPrice + BigInt(1);

      await expect(
        usageDepositor
          .connect(sessionReceiptContract)
          .settleUsageToNode(
            client.address,
            node.address,
            servedUsage,
            mockERC20.target,
            excessivePayment
          )
      ).to.be.revertedWith("Insufficient token balance");
    });
  });

  // Helper function to purchase usage
  async function purchaseUsageHelper(
    client: HardhatEthersSigner,
    requestedSeconds: number,
    totalPrice: BigNumberish,
    tokenType: TokenType,
    tokenAddress: string
  ) {
    const nonce = await usageDepositor.getNonce(client.address);

    // Create order data
    const orderData = {
      client: client.address,
      requestedSeconds,
      totalPrice,
      tokenType,
      tokenAddress,
      nonce,
    };

    // Create domain for EIP-712
    const domain: TypedDataDomain = {
      name: DOMAIN_NAME,
      version: DOMAIN_VERSION,
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: usageDepositor.target as any,
    };

    // Sign with EIP-712
    const signature = await usageBillingAdmin.signTypedData(
      domain,
      USAGE_ORDER_TYPE,
      orderData
    );

    const usageOrder = {
      ...orderData,
      usageBillingAdminSig: signature,
    };

    // Handle token approvals and value
    if (tokenType === TokenType.ERC20) {
      await mockERC20
        .connect(client)
        .approve(usageDepositor.target as any, totalPrice as any);
      await usageDepositor.connect(client).purchaseUsage(usageOrder as any);
    } else {
      await usageDepositor
        .connect(client)
        .purchaseUsage(usageOrder, { value: totalPrice });
    }
  }
});

// The mock contracts remain the
export enum TokenType {
  NATIVE = 0,
  ERC20 = 1,
}
