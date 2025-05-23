import { ethers, run } from "hardhat";
import { writeFileSync } from "fs";
import { join } from "path";

async function main() {
  console.log("Starting deployment process...");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deploying contracts with the account: ${deployerAddress}`);

  console.log("Deploying SessionReceipt contract...");
  const SessionReceiptContractFactory = await ethers.getContractFactory(
    "SessionReceipt"
  );
  const nodeStorageAddress = "0x8B0b7E0c9C5a6B48F5bA0352713B85c2C4973B78";
  const usageDespositorAddress = "0x7BD15c4eE33f9E928020c1735E773AaBD0a6c8D0";
  const SessionReceipt = await SessionReceiptContractFactory.deploy(
    nodeStorageAddress,
    usageDespositorAddress
  );
  await SessionReceipt.waitForDeployment();
  const SessionReceiptAddress = await SessionReceipt.getAddress();
  console.log(`SessionReceipt deployed to: ${SessionReceiptAddress}`);
  await run("verify:verify", {
    address: SessionReceiptAddress,
    constructorArguments: [nodeStorageAddress, usageDespositorAddress],
  });
  console.log("SessionReceipt verified successfully");

  const deploymentData = {
    contractAddress: SessionReceiptAddress,
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
  };

  const deploymentsDir = join(__dirname, "..", "deployments");
  const filePath = join(
    deploymentsDir,
    `deployment-session-receipt-${deploymentData.network}.json`
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
