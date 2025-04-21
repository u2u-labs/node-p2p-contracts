import { ethers, run } from "hardhat";
import { writeFileSync } from "fs";
import { join } from "path";
import { ZeroAddress } from "ethers";

async function main() {
  console.log("Starting deployment process...");

  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deploying contracts with the account: ${deployerAddress}`);

  console.log("Deploying Voting contract...");
  const VotingContractFactory = await ethers.getContractFactory("Voting");
  const voting = await VotingContractFactory.deploy(51);
  await voting.waitForDeployment();
  const votingAddress = await voting.getAddress();
  console.log(`Voting deployed to: ${votingAddress}`);
  await run("verify:verify", {
    address: votingAddress,
    constructorArguments: [51],
  });
  console.log("Voting verified successfully");

  const deploymentData = {
    contractAddress: votingAddress,
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
  };

  const deploymentsDir = join(__dirname, "..", "deployments");
  const filePath = join(
    deploymentsDir,
    `deployment-voting-${deploymentData.network}.json`
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
