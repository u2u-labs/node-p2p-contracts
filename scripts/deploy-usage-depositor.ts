import { ethers, run } from "hardhat";
import { writeFileSync } from "fs";
import { join } from "path";
import { ZeroAddress } from "ethers";

async function main() {
  console.log("Starting deployment process...");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deploying contracts with the account: ${deployerAddress}`);

  console.log("Deploying UsageDepositor contract...");
  const UsageDepositorContractFactory = await ethers.getContractFactory(
    "UsageDepositor"
  );
  const UsageDepositor = await UsageDepositorContractFactory.deploy(
    "0x2743eEC46576f76f47334569074242F3D9a90B44",
    ZeroAddress,
    ZeroAddress
  );
  await UsageDepositor.waitForDeployment();
  const UsageDepositorAddress = await UsageDepositor.getAddress();
  console.log(`UsageDepositor deployed to: ${UsageDepositorAddress}`);
  await run("verify:verify", {
    address: UsageDepositorAddress,
    constructorArguments: [
      "0x2743eEC46576f76f47334569074242F3D9a90B44",
      ZeroAddress,
      ZeroAddress,
    ],
  });
  console.log("UsageDepositor verified successfully");

  const deploymentData = {
    contractAddress: UsageDepositorAddress,
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
  };

  const deploymentsDir = join(__dirname, "..", "deployments");
  const filePath = join(
    deploymentsDir,
    `deployment-usage-depositor-${deploymentData.network}.json`
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
