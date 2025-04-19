import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { MockERC20, NodeDataPayment, NodesStorage } from "../typechain-types";

describe("NodeDataPayment Contract", function () {
  let nodeDataPayment: NodeDataPayment;
  let token: MockERC20;
  let nodesStorage: NodesStorage;
  let node: HardhatEthersSigner, client: HardhatEthersSigner;

  const name = "NodeDataPayment";
  const version = "1";

  let domain: {
    name: string;
    version: string;
    chainId: number;
    verifyingContract: string;
  };

  beforeEach(async () => {
    // Get signers using hardhat-ethers integration
    const signers = await ethers.getSigners();
    node = signers[0];
    client = signers[1];

    const nodeAddress = await node.getAddress();

    // Deploy NodesStorage and add the node
    const NodesStorageFactory = await ethers.getContractFactory("NodesStorage");
    nodesStorage = await NodesStorageFactory.deploy([nodeAddress]);
    // In ethers v6, wait for deployment
    await nodesStorage.waitForDeployment();

    // Deploy MockERC20 token
    const Token = await ethers.getContractFactory("MockERC20");
    token = await Token.deploy("MockToken", "MTK", 18);
    await token.waitForDeployment();

    const clientAddress = await client.getAddress();
    await token.mint(clientAddress, ethers.parseEther("1000"));

    // Get contract address using getAddress() in ethers v6
    const tokenAddress = await token.getAddress();

    // Deploy NodeDataPayment contract
    const NodeDataPaymentFactory = await ethers.getContractFactory(
      "NodeDataPayment"
    );
    nodeDataPayment = await NodeDataPaymentFactory.deploy(
      await nodesStorage.getAddress()
    );
    await nodeDataPayment.waitForDeployment();

    // Approve after NodeDataPayment is deployed
    const nodeDataPaymentAddress = await nodeDataPayment.getAddress();
    await token
      .connect(client)
      .approve(nodeDataPaymentAddress, ethers.MaxUint256);

    // Set up EIP-712 domain
    const network = await ethers.provider.getNetwork();
    domain = {
      name,
      version,
      chainId: Number(network.chainId),
      verifyingContract: nodeDataPaymentAddress,
    };
  });

  it("should fulfill an ERC20 bill successfully", async () => {
    const nonce = 0;
    const usedAmount = 5;
    const unitPrice = ethers.parseEther("1");
    const totalPrice = unitPrice * BigInt(usedAmount);

    const nodeAddress = await node.getAddress();
    const clientAddress = await client.getAddress();
    const tokenAddress = await token.getAddress();

    const dataPlan = { unitPrice };
    const payment = {
      tokenType: 1, // ERC20
      tokenAddress: tokenAddress,
    };

    const bill = {
      node: nodeAddress,
      client: clientAddress,
      dataPlan,
      payment,
      usedAmount,
      nonce,
    };

    const types = {
      DataPlan: [{ name: "unitPrice", type: "uint256" }],
      Payment: [
        { name: "tokenType", type: "uint8" },
        { name: "tokenAddress", type: "address" },
      ],
      Bill: [
        { name: "node", type: "address" },
        { name: "client", type: "address" },
        { name: "dataPlan", type: "DataPlan" },
        { name: "payment", type: "Payment" },
        { name: "usedAmount", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    };

    const signature = await node.signTypedData(domain, types, bill);

    const balanceBeforeNode = await token.balanceOf(nodeAddress);
    const balanceBeforeClient = await token.balanceOf(clientAddress);

    const tx = await nodeDataPayment
      .connect(client)
      .fulfillDataBill(bill, signature);
    await tx.wait();

    const balanceAfterNode = await token.balanceOf(nodeAddress);
    const balanceAfterClient = await token.balanceOf(clientAddress);

    // Check that the node has received the payment
    expect(balanceAfterNode).to.equal(balanceBeforeNode + totalPrice);
    expect(balanceAfterClient).to.equal(balanceBeforeClient - totalPrice);
  });

  it("should fulfill a native payment bill successfully", async () => {
    const nonce = 0;
    const usedAmount = 5;
    const unitPrice = ethers.parseEther("1");
    const totalPrice = unitPrice * BigInt(usedAmount);

    const nodeAddress = await node.getAddress();
    const clientAddress = await client.getAddress();

    const dataPlan = { unitPrice };
    const payment = {
      tokenType: 0, // Native
      tokenAddress: ethers.ZeroAddress,
    };

    const bill = {
      node: nodeAddress,
      client: clientAddress,
      dataPlan,
      payment,
      usedAmount,
      nonce,
    };

    const types = {
      DataPlan: [{ name: "unitPrice", type: "uint256" }],
      Payment: [
        { name: "tokenType", type: "uint8" },
        { name: "tokenAddress", type: "address" },
      ],
      Bill: [
        { name: "node", type: "address" },
        { name: "client", type: "address" },
        { name: "dataPlan", type: "DataPlan" },
        { name: "payment", type: "Payment" },
        { name: "usedAmount", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    };

    const signature = await node.signTypedData(domain, types, bill);

    const balanceBeforeNode = await ethers.provider.getBalance(nodeAddress);
    const balanceBeforeClient = await ethers.provider.getBalance(clientAddress);

    const tx = await nodeDataPayment
      .connect(client)
      .fulfillDataBill(bill, signature, {
        value: totalPrice,
      });
    await tx.wait();

    const balanceAfterNode = await ethers.provider.getBalance(nodeAddress);

    // For native token tests, we need to account for gas costs
    // So we only check the node received the funds
    expect(balanceAfterNode).to.be.greaterThan(balanceBeforeNode);
  });

  it("should reject when signature doesn't match bill data", async () => {
    const nonce = 0;
    const usedAmount = 5;
    const unitPrice = ethers.parseEther("1");

    const nodeAddress = await node.getAddress();
    const clientAddress = await client.getAddress();
    const tokenAddress = await token.getAddress();

    // First, create a valid bill
    const validBill = {
      node: nodeAddress,
      client: clientAddress,
      dataPlan: { unitPrice },
      payment: {
        tokenType: 1, // ERC20
        tokenAddress: tokenAddress,
      },
      usedAmount,
      nonce,
    };

    const types = {
      DataPlan: [{ name: "unitPrice", type: "uint256" }],
      Payment: [
        { name: "tokenType", type: "uint8" },
        { name: "tokenAddress", type: "address" },
      ],
      Bill: [
        { name: "node", type: "address" },
        { name: "client", type: "address" },
        { name: "dataPlan", type: "DataPlan" },
        { name: "payment", type: "Payment" },
        { name: "usedAmount", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    };

    // Generate a signature for the valid bill
    const validSignature = await node.signTypedData(domain, types, validBill);

    // Now create a modified bill with different data
    const modifiedBill = {
      ...validBill,
      usedAmount: 10, // Change the usage amount
    };

    // Try to use the original signature with the modified bill data
    await expect(
      nodeDataPayment
        .connect(client)
        .fulfillDataBill(modifiedBill, validSignature)
    ).to.be.revertedWith("Signature mismatch");
  });

  it("should reject when signature is from wrong signer", async () => {
    const nonce = 0;
    const usedAmount = 5;
    const unitPrice = ethers.parseEther("1");

    const nodeAddress = await node.getAddress();
    const clientAddress = await client.getAddress();

    // Set up the bill
    const bill = {
      node: nodeAddress,
      client: clientAddress,
      dataPlan: { unitPrice },
      payment: {
        tokenType: 0, // Native
        tokenAddress: ethers.ZeroAddress,
      },
      usedAmount,
      nonce,
    };

    const types = {
      DataPlan: [{ name: "unitPrice", type: "uint256" }],
      Payment: [
        { name: "tokenType", type: "uint8" },
        { name: "tokenAddress", type: "address" },
      ],
      Bill: [
        { name: "node", type: "address" },
        { name: "client", type: "address" },
        { name: "dataPlan", type: "DataPlan" },
        { name: "payment", type: "Payment" },
        { name: "usedAmount", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    };

    // Generate signature using the client instead of the node
    // This should fail since the bill claims it's from the node
    const invalidSignature = await client.signTypedData(domain, types, bill);
    const totalPrice = unitPrice * BigInt(usedAmount);

    await expect(
      nodeDataPayment.connect(client).fulfillDataBill(bill, invalidSignature, {
        value: totalPrice,
      })
    ).to.be.revertedWith("Signature mismatch");
  });

  it("should reject if bill fields are tampered with", async () => {
    const nonce = 0;
    const usedAmount = 5;
    const unitPrice = ethers.parseEther("1");
    const originalTotalPrice = unitPrice * BigInt(usedAmount);

    const nodeAddress = await node.getAddress();
    const clientAddress = await client.getAddress();

    // Original bill with lower price
    const originalBill = {
      node: nodeAddress,
      client: clientAddress,
      dataPlan: { unitPrice },
      payment: {
        tokenType: 0, // Native
        tokenAddress: ethers.ZeroAddress,
      },
      usedAmount,
      nonce,
    };

    const types = {
      DataPlan: [{ name: "unitPrice", type: "uint256" }],
      Payment: [
        { name: "tokenType", type: "uint8" },
        { name: "tokenAddress", type: "address" },
      ],
      Bill: [
        { name: "node", type: "address" },
        { name: "client", type: "address" },
        { name: "dataPlan", type: "DataPlan" },
        { name: "payment", type: "Payment" },
        { name: "usedAmount", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    };

    // Get signature for original bill
    const signature = await node.signTypedData(domain, types, originalBill);

    // Create a tampered bill with lower unit price (trying to pay less)
    const tamperedBill = {
      ...originalBill,
      dataPlan: {
        unitPrice: ethers.parseEther("0.5"), // Half the original price
      },
    };
    const tamperedTotalPrice = ethers.parseEther("0.5") * BigInt(usedAmount);

    // Should reject the tampered bill with original signature
    await expect(
      nodeDataPayment.connect(client).fulfillDataBill(tamperedBill, signature, {
        value: tamperedTotalPrice,
      })
    ).to.be.revertedWith("Signature mismatch");
  });
});
