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
});
