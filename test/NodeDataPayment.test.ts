import { expect } from "chai";
import { ethers } from "hardhat";  // Import from Hardhat
import { Signer } from "ethers";
import { NodeDataPayment, NodesStorage, MockERC20 } from "../typechain-types"; // Adjust the path if necessary

describe("NodeDataPayment Contract", function () {
  let NodeDataPayment: NodeDataPayment;
  let token: MockERC20;
  let nodesStorage: NodesStorage;
  let node: Signer, client: Signer;

  const name = "BandwidthEscrow";
  const version = "1";

  let domain: {
    name: string;
    version: string;
    chainId: number;
    verifyingContract: string;
  };

  beforeEach(async () => {
    [node, client] = await ethers.getSigners(); // Get the signers (accounts)

    const nodeAddress = await node.getAddress();

    // Deploy NodesStorage and add the node
    const NodesStorageFactory = await ethers.getContractFactory("NodesStorage");
    nodesStorage = (await NodesStorageFactory.deploy([nodeAddress])) as NodesStorage;
    await nodesStorage.deployed();

    // Deploy MockERC20 token
    const Token = await ethers.getContractFactory("MockERC20");
    token = (await Token.deploy("MockToken", "MTK", 18)) as MockERC20;
    await token.deployed();

    const clientAddress = await client.getAddress();
    await token.mint(clientAddress, ethers.parseEther("1000"));
    await token.connect(client).approve(NodeDataPayment.target, ethers.MaxUint256); // Approve NodeDataPayment contract

    // Deploy NodeDataPayment contract
    const NodeDataPaymentFactory = await ethers.getContractFactory("NodeDataPayment");
    NodeDataPayment = (await NodeDataPaymentFactory.deploy(nodesStorage.target)) as NodeDataPayment;
    await NodeDataPayment.deployed();

    // Set up EIP-712 domain
    const network = await ethers.provider.getNetwork();
    domain = {
      name,
      version,
      chainId: Number(network.chainId),
      verifyingContract: NodeDataPayment.target.toString(),
    };
  });

  it("should fulfill an ERC20 bill successfully", async () => {
    const nonce = 0;
    const usedAmount = 5;
    const unitPrice = ethers.parseEther("1");
    const totalPrice = unitPrice * BigInt(usedAmount);

    const nodeAddress = await node.getAddress();
    const clientAddress = await client.getAddress();

    const dataPlan = { unitPrice };
    const payment = {
      tokenType: 1, // ERC20
      tokenAddress: token.target.toString(),
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

    const tx = await NodeDataPayment.connect(client).fulfillDataBill(bill, signature);
    await tx.wait();

    const balanceAfterNode = await token.balanceOf(nodeAddress);
    const balanceAfterClient = await token.balanceOf(clientAddress);

    // Check that the node has received the payment
    expect(balanceAfterNode).to.equal(balanceBeforeNode.add(totalPrice));
    expect(balanceAfterClient).to.equal(balanceBeforeClient.sub(totalPrice));
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

    const tx = await NodeDataPayment.connect(client).fulfillDataBill(bill, signature, {
      value: totalPrice,
    });
    await tx.wait();

    const balanceAfterNode = await ethers.provider.getBalance(nodeAddress);
    const balanceAfterClient = await ethers.provider.getBalance(clientAddress);

    // Check that the node has received the native payment
    expect(balanceAfterNode).to.equal(balanceBeforeNode.add(totalPrice));
    expect(balanceAfterClient).to.equal(balanceBeforeClient.sub(totalPrice));
  });
});
