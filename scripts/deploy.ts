import { ethers } from "hardhat";

async function main() {
  const Lock = await ethers.getContractFactory("Lock");
  const lock = await Lock.deploy(1234567890);
  await lock.deployed();
  console.log(`Lock deployed to: ${lock.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
