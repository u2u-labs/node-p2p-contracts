import { expect } from "chai";
import { ethers } from "hardhat";
import { NodesStorage } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("NodesStorage", function () {
  let nodesStorage: NodesStorage;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let addr3: SignerWithAddress;
  let addr4: SignerWithAddress;
  let initialNodes: string[];

  beforeEach(async function () {
    // Get signers
    [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    
    // Set up initial nodes for deployment
    initialNodes = [addr1.address, addr2.address];
    
    // Deploy the contract
    const NodesStorageFactory = await ethers.getContractFactory("NodesStorage");
    nodesStorage = await NodesStorageFactory.deploy(initialNodes) as NodesStorage;
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await nodesStorage.owner()).to.equal(owner.address);
    });

    it("Should initialize with the correct nodes", async function () {
      expect(await nodesStorage.isValidNode(addr1.address)).to.be.true;
      expect(await nodesStorage.isValidNode(addr2.address)).to.be.true;
      expect(await nodesStorage.isValidNode(addr3.address)).to.be.false;
      
      const validNodes = await nodesStorage.getValidNodes();
      expect(validNodes.length).to.equal(2);
      expect(validNodes).to.include(addr1.address);
      expect(validNodes).to.include(addr2.address);
      
      const totalNodes = await nodesStorage.getTotalValidNodes();
      expect(totalNodes).to.equal(2);
    });
  });

  describe("Node Management", function () {
    it("Should add new nodes correctly", async function () {
      await nodesStorage.addNodes([addr3.address]);
      
      expect(await nodesStorage.isValidNode(addr3.address)).to.be.true;
      
      const validNodes = await nodesStorage.getValidNodes();
      expect(validNodes.length).to.equal(3);
      expect(validNodes).to.include(addr3.address);
      
      const totalNodes = await nodesStorage.getTotalValidNodes();
      expect(totalNodes).to.equal(3);
    });

    it("Should revert when adding an already active node", async function () {
      await expect(nodesStorage.addNodes([addr1.address]))
        .to.be.revertedWith("NodeStorage: Node already added");
    });

    it("Should remove nodes correctly", async function () {
      await nodesStorage.removeNode(addr1.address);
      
      expect(await nodesStorage.isValidNode(addr1.address)).to.be.false;
      
      const validNodes = await nodesStorage.getValidNodes();
      expect(validNodes.length).to.equal(1);
      expect(validNodes).to.not.include(addr1.address);
      expect(validNodes).to.include(addr2.address);
      
      const totalNodes = await nodesStorage.getTotalValidNodes();
      expect(totalNodes).to.equal(1);
    });

    it("Should revert when removing a non-existent node", async function () {
      await expect(nodesStorage.removeNode(addr3.address))
        .to.be.revertedWith("NodeStorage: Node not found");
    });

    it("Should correctly re-add a previously removed node", async function () {
      // First remove a node
      await nodesStorage.removeNode(addr1.address);
      expect(await nodesStorage.isValidNode(addr1.address)).to.be.false;
      
      // Re-add the removed node
      await nodesStorage.addNodes([addr1.address]);
      expect(await nodesStorage.isValidNode(addr1.address)).to.be.true;
      
      // Check the node is in the list of valid nodes
      const validNodes = await nodesStorage.getValidNodes();
      expect(validNodes.length).to.equal(2);
      expect(validNodes).to.include(addr1.address);
      
      // Check the total count is correct
      const totalNodes = await nodesStorage.getTotalValidNodes();
      expect(totalNodes).to.equal(2);
    });

    it("Should not add duplicate entries to nodeList when re-adding removed nodes", async function () {
      // Add a new node, remove it, then re-add it
      await nodesStorage.addNodes([addr3.address]);
      await nodesStorage.removeNode(addr3.address);
      await nodesStorage.addNodes([addr3.address]);
      
      // Get total count
      const totalNodes = await nodesStorage.getTotalValidNodes();
      expect(totalNodes).to.equal(3); // original 2 + 1 re-added
      
      // Check for duplicates indirectly by verifying node counts
      const validNodes = await nodesStorage.getValidNodes();
      expect(validNodes.length).to.equal(3);
      
      // Perform multiple removals and re-adds to verify consistency
      await nodesStorage.removeNode(addr1.address);
      await nodesStorage.removeNode(addr2.address);
      await nodesStorage.addNodes([addr1.address]);
      
      const totalNodesAfter = await nodesStorage.getTotalValidNodes();
      expect(totalNodesAfter).to.equal(2); // addr1 and addr3 should be valid
    });
  });

  describe("Access Control", function () {
    it("Should allow only owner to add nodes", async function () {
      await expect(nodesStorage.connect(addr1).addNodes([addr3.address]))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow only owner to remove nodes", async function () {
      await expect(nodesStorage.connect(addr1).removeNode(addr2.address))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow ownership transfer", async function () {
      await nodesStorage.transferOwnership(addr1.address);
      expect(await nodesStorage.owner()).to.equal(addr1.address);
      
      // Now addr1 can add nodes
      await nodesStorage.connect(addr1).addNodes([addr3.address]);
      expect(await nodesStorage.isValidNode(addr3.address)).to.be.true;
    });
  });

  describe("Events", function () {
    it("Should emit NodeAdded event when adding a node", async function () {
      await expect(nodesStorage.addNodes([addr3.address]))
        .to.emit(nodesStorage, "NodeAdded")
        .withArgs(addr3.address);
    });

    it("Should emit NodeRemoved event when removing a node", async function () {
      await expect(nodesStorage.removeNode(addr1.address))
        .to.emit(nodesStorage, "NodeRemoved")
        .withArgs(addr1.address);
    });

    it("Should emit NodeAdded event when re-adding a removed node", async function () {
      await nodesStorage.removeNode(addr1.address);
      
      await expect(nodesStorage.addNodes([addr1.address]))
        .to.emit(nodesStorage, "NodeAdded")
        .withArgs(addr1.address);
    });
  });

  describe("View Functions", function () {
    it("Should correctly count valid nodes after complex operations", async function () {
      // Add new nodes
      await nodesStorage.addNodes([addr3.address, addr4.address]);
      expect(await nodesStorage.getTotalValidNodes()).to.equal(4);
      
      // Remove some nodes
      await nodesStorage.removeNode(addr1.address);
      await nodesStorage.removeNode(addr3.address);
      expect(await nodesStorage.getTotalValidNodes()).to.equal(2);
      
      // Re-add a removed node
      await nodesStorage.addNodes([addr1.address]);
      expect(await nodesStorage.getTotalValidNodes()).to.equal(3);
      
      // Verify the list of valid nodes
      const validNodes = await nodesStorage.getValidNodes();
      expect(validNodes.length).to.equal(3);
      expect(validNodes).to.include.members([addr1.address, addr2.address, addr4.address]);
      expect(validNodes).to.not.include(addr3.address);
    });

    it("Should handle a large number of nodes with removals and re-adds", async function () {
      // Create 10 random addresses
      const randomAddresses = Array.from({ length: 10 }, () => 
        ethers.Wallet.createRandom().address
      );
      
      // Add them to the contract
      await nodesStorage.addNodes(randomAddresses);
      expect(await nodesStorage.getTotalValidNodes()).to.equal(12); // 2 initial + 10 new
      
      // Remove 5 random nodes
      for (let i = 0; i < 5; i++) {
        await nodesStorage.removeNode(randomAddresses[i]);
      }
      expect(await nodesStorage.getTotalValidNodes()).to.equal(7); // 12 - 5
      
      // Re-add 3 of the removed nodes
      await nodesStorage.addNodes([
        randomAddresses[0],
        randomAddresses[1],
        randomAddresses[2]
      ]);
      expect(await nodesStorage.getTotalValidNodes()).to.equal(10); // 7 + 3
      
      // Remove some initial nodes
      await nodesStorage.removeNode(addr1.address);
      await nodesStorage.removeNode(addr2.address);
      expect(await nodesStorage.getTotalValidNodes()).to.equal(8); // 10 - 2
      
      // Verify some key nodes
      expect(await nodesStorage.isValidNode(randomAddresses[0])).to.be.true;
      expect(await nodesStorage.isValidNode(randomAddresses[4])).to.be.false;
      expect(await nodesStorage.isValidNode(addr1.address)).to.be.false;
    });
    
    it("Should ensure consistent node list without duplicates", async function () {
      // This test specifically targets the _nodeExistsInList functionality
      
      // Add the same node multiple times
      await nodesStorage.addNodes([addr3.address]);
      await nodesStorage.removeNode(addr3.address);
      await nodesStorage.addNodes([addr3.address]);
      await nodesStorage.removeNode(addr3.address);
      await nodesStorage.addNodes([addr3.address]);
      
      // Check total count - should only be 3 (initial 2 + addr3)
      const validNodes = await nodesStorage.getValidNodes();
      expect(validNodes.length).to.equal(3);
      
      // Check the total count with the specific function
      const totalNodes = await nodesStorage.getTotalValidNodes();
      expect(totalNodes).to.equal(3);
      
      // Remove and re-add in a different order
      await nodesStorage.removeNode(addr1.address);
      await nodesStorage.removeNode(addr2.address);
      await nodesStorage.removeNode(addr3.address);
      
      await nodesStorage.addNodes([addr3.address, addr1.address, addr2.address]);
      
      // Verify counts remain consistent
      const finalNodes = await nodesStorage.getValidNodes();
      expect(finalNodes.length).to.equal(3);
    });
  });
});