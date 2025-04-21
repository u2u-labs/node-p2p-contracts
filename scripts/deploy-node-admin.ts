import { ethers, run } from "hardhat";
import { writeFileSync } from "fs";
import { join } from "path";
import { ZeroAddress } from "ethers";

async function main() {
  console.log("Starting deployment process...");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deploying contracts with the account: ${deployerAddress}`);

  console.log("Deploying NodeAdmin contract...");
  const NodeAdminContractFactory = await ethers.getContractFactory("NodeAdmin");
  const nodeAdmin = await NodeAdminContractFactory.deploy();
  await nodeAdmin.waitForDeployment();
  const nodeAdminAddress = await nodeAdmin.getAddress();
  console.log(`NodeAdmin deployed to: ${nodeAdminAddress}`);
  await run("verify:verify", {
    address: nodeAdminAddress,
    constructorArguments: [],
  });
  console.log("NodeAdmin verified successfully");

  const deploymentData = {
    contractAddress: nodeAdminAddress,
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
  };

  const deploymentsDir = join(__dirname, "..", "deployments");
  const filePath = join(
    deploymentsDir,
    `deployment-node-admin-${deploymentData.network}.json`
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
