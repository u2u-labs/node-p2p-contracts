import { ethers, run } from "hardhat";
import { writeFileSync } from "fs";
import { join } from "path";
import { AddressLike } from "ethers";

async function main() {
  console.log("Starting deployment process...");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deploying contracts with the account: ${deployerAddress}`);

  const initialNodes: AddressLike[] = [];
  console.log("Deploying NodesStorage contract...");
  const NodesStorageFactory = await ethers.getContractFactory("NodesStorage");
  const nodesStorage = await NodesStorageFactory.deploy(initialNodes);
  await nodesStorage.waitForDeployment();
  const nodesStorageAddress = await nodesStorage.getAddress();
  console.log(`NodesStorage deployed to: ${nodesStorageAddress}`);
  await run("verify:verify", {
    address: nodesStorageAddress,
    constructorArguments: [initialNodes],
  });
  console.log("NodesStorage verified successfully");

  const deploymentData = {
    contractAddress: nodesStorageAddress,
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
  };

  const deploymentsDir = join(__dirname, "..", "deployments");
  const filePath = join(
    deploymentsDir,
    `deployment-nodes-storage-${deploymentData.network}.json`
  );

  try {
    writeFileSync(filePath, JSON.stringify(deploymentData, null, 2));
    console.log(`Deployment information saved to ${filePath}`);
  } catch (error) {
    console.error("Failed to save deployment information:", error);
  }

  console.log("Deployment completed successfully!");
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });
