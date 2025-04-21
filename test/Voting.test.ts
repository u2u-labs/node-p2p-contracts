import { expect } from "chai";
import { ethers } from "hardhat";
import { NodeAdmin, NodesStorage, Voting } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ZeroAddress } from "ethers";

describe("Voting Contract", function () {
  let voting: Voting;
  let nodeStorage: NodesStorage;
  let nodeAdmin: NodeAdmin;
  let owner: HardhatEthersSigner;
  let node1: HardhatEthersSigner;
  let node2: HardhatEthersSigner;
  let node3: HardhatEthersSigner;
  let node4: HardhatEthersSigner;
  let nonNode: HardhatEthersSigner;
  const INITIAL_QUORUM_PERCENT = 50; // 50% quorum threshold

  beforeEach(async function () {
    // Get signers
    [owner, node1, node2, node3, node4, nonNode] = await ethers.getSigners();

    // Deploy mock node storage contract
    const NodesStorage = await ethers.getContractFactory("NodesStorage");
    nodeStorage = (await NodesStorage.deploy([])) as NodesStorage;
    await nodeStorage.waitForDeployment();

    // Add nodes to the node storage
    await nodeStorage.addNodes([
      node1.address,
      node2.address,
      node3.address,
      node4.address,
    ]);

    // Deploy voting contract
    const Voting = await ethers.getContractFactory("Voting");
    voting = (await Voting.deploy(INITIAL_QUORUM_PERCENT)) as Voting;
    await voting.waitForDeployment();

    await voting.connect(owner).setNodesStorage(nodeStorage.target);

    // Deploy node admin contract
    const NodeAdmin = await ethers.getContractFactory("NodeAdmin");
    nodeAdmin = (await NodeAdmin.deploy()) as NodeAdmin;
    await nodeAdmin.waitForDeployment();
    await nodeAdmin.connect(owner).setVoting(voting.target);
    await nodeAdmin.connect(owner).setNodesStorage(nodeStorage.target);

    voting.connect(owner).setNodeAdmin(nodeAdmin.target);

    nodeStorage.connect(owner).transferOwnership(nodeAdmin.target);
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await voting.owner()).to.equal(owner.address);
    });

    it("Should set the node storage address correctly", async function () {
      expect(await voting.nodeStorage()).to.equal(nodeStorage.target);
    });

    it("Should set the initial quorum threshold correctly", async function () {
      expect(await voting.quorumThresholdPercent()).to.equal(
        INITIAL_QUORUM_PERCENT
      );
    });

    it("Should fail if deployed with invalid node storage address", async function () {
      const Voting = await ethers.getContractFactory("Voting");
      const voting = await Voting.deploy(INITIAL_QUORUM_PERCENT);
      await expect(voting.setNodesStorage(ZeroAddress)).to.be.revertedWith(
        "Invalid storage address"
      );
    });

    it("Should fail if deployed with invalid quorum percent", async function () {
      const Voting = await ethers.getContractFactory("Voting");
      await expect(Voting.deploy(0)).to.be.revertedWith("Invalid quorum %");

      await expect(Voting.deploy(101)).to.be.revertedWith("Invalid quorum %");
    });
  });

  describe("Reporting Nodes", function () {
    it("Should allow a valid node to report another node", async function () {
      await expect(voting.connect(node1).reportNode(node2.address))
        .to.emit(voting, "NodeReported")
        .withArgs(node1.address, node2.address, 1);

      expect(await voting.reportedNodes(node2.address)).to.equal(1);
      expect(await voting.reportLogs(node1.address, node2.address)).to.be.true;
    });

    it("Should not allow a non-node to report a node", async function () {
      await expect(
        voting.connect(nonNode).reportNode(node1.address)
      ).to.be.revertedWith("Not a valid node");
    });

    it("Should not allow reporting a non-node address", async function () {
      await expect(
        voting.connect(node1).reportNode(nonNode.address)
      ).to.be.revertedWith("Target is not a valid node");
    });

    it("Should not allow a node to report the same node twice", async function () {
      await voting.connect(node1).reportNode(node2.address);
      await expect(
        voting.connect(node1).reportNode(node2.address)
      ).to.be.revertedWith("Node already reported");
    });

    it("Should remove a node when quorum is reached", async function () {
      // With 4 nodes and 50% quorum, we need 2 reports to reach quorum
      // First report
      await voting.connect(node1).reportNode(node4.address);
      expect(await voting.reportedNodes(node4.address)).to.equal(1);

      // Second report should reach quorum and remove node4
      await expect(voting.connect(node2).reportNode(node4.address))
        .to.emit(voting, "NodeRemoved")
        .withArgs(node4.address);
    });

    it("Should calculate quorum threshold correctly with rounding up", async function () {
      // Update to 75% quorum with 4 nodes = 3 reports needed
      await voting.connect(owner).updateQuorumThreshold(75);

      // First report
      await voting.connect(node1).reportNode(node4.address);
      expect(await voting.reportedNodes(node4.address)).to.equal(1);

      // Second report
      await voting.connect(node2).reportNode(node4.address);
      expect(await voting.reportedNodes(node4.address)).to.equal(2);

      // Third report should reach quorum and remove node4
      await expect(voting.connect(node3).reportNode(node4.address))
        .to.emit(voting, "NodeRemoved")
        .withArgs(node4.address);
    });
  });

  describe("Updating Settings", function () {
    it("Should allow owner to update quorum threshold", async function () {
      const newQuorum = 70;
      await expect(voting.connect(owner).updateQuorumThreshold(newQuorum))
        .to.emit(voting, "QuorumThresholdUpdated")
        .withArgs(newQuorum);

      expect(await voting.quorumThresholdPercent()).to.equal(newQuorum);
    });

    it("Should not allow non-owner to update quorum threshold", async function () {
      await expect(
        voting.connect(node1).updateQuorumThreshold(70)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should not allow updating to invalid quorum percents", async function () {
      await expect(
        voting.connect(owner).updateQuorumThreshold(0)
      ).to.be.revertedWith("Invalid quorum percent");

      await expect(
        voting.connect(owner).updateQuorumThreshold(101)
      ).to.be.revertedWith("Invalid quorum percent");
    });

    it("Should allow owner to update node storage address", async function () {
      // Deploy a new mock node storage
      const NewNodesStorageMock = await ethers.getContractFactory(
        "NodesStorage"
      );
      const newNodeStorage = await NewNodesStorageMock.deploy([]);
      await newNodeStorage.waitForDeployment();

      await voting.connect(owner).updateNodeStorage(newNodeStorage.target);
      expect(await voting.nodeStorage()).to.equal(newNodeStorage.target);
    });

    it("Should not allow non-owner to update node storage address", async function () {
      const NewNodesStorageMock = await ethers.getContractFactory(
        "NodesStorage"
      );
      const newNodeStorage = await NewNodesStorageMock.deploy([]);
      await newNodeStorage.waitForDeployment();

      await expect(
        voting.connect(node1).updateNodeStorage(newNodeStorage.target)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should not allow updating to invalid node storage address", async function () {
      await expect(
        voting.connect(owner).updateNodeStorage(ZeroAddress)
      ).to.be.revertedWith("Invalid address");
    });
  });
});
