import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, ZeroAddress, ZeroHash } from "ethers";
import { Vault, MockERC20 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

// Define interface for SpendingLimit structure
interface SpendingLimit {
  maxPerSession: bigint;
  maxPerPeriod: bigint;
  periodStart: number;
  spentInPeriod: bigint;
  initialized: boolean;
}

describe("Vault Contract", () => {
  let vault: Vault;
  let owner: HardhatEthersSigner;
  let depositOperator: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;
  let mockToken: MockERC20;
  const ZERO_ADDRESS: string = ZeroAddress;
  const DEPOSIT_OPERATOR_ROLE: string = ethers.keccak256(
    ethers.toUtf8Bytes("DEPOSIT_OPERATOR_ROLE")
  );

  beforeEach(async () => {
    [owner, depositOperator, user1, user2] = await ethers.getSigners();

    // Deploy mock ERC20 token
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Mock Token", "MTK", 18);
    await mockToken.waitForDeployment();

    // Deploy the Vault contract
    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy();
    await vault.waitForDeployment();

    // Grant deposit operator role
    await vault.grantTransferOperatorRole(depositOperator.address);

    // Mint some tokens to users for testing
    await mockToken.mint(user1.address, ethers.parseEther("1000"));
    await mockToken.mint(user2.address, ethers.parseEther("1000"));

    // Approve vault to spend user tokens
    await mockToken
      .connect(user1)
      .approve(vault.target, ethers.parseEther("1000"));
    await mockToken
      .connect(user2)
      .approve(vault.target, ethers.parseEther("1000"));
  });

  describe("Role Management", () => {
    it("Should set the owner as the default admin", async () => {
      expect(await vault.hasRole(ZeroHash, owner.address)).to.equal(true);
    });

    it("Should grant deposit operator role correctly", async () => {
      expect(
        await vault.hasRole(DEPOSIT_OPERATOR_ROLE, depositOperator.address)
      ).to.equal(true);
    });

    it("Should fail if non-admin tries to grant roles", async () => {
      await expect(
        vault.connect(user1).grantTransferOperatorRole(user2.address)
      ).to.be.reverted;
    });
  });

  describe("Period Duration", () => {
    it("Should allow deposit operator to set period duration", async () => {
      const newDuration: number = 172800; // 2 days
      await vault.connect(depositOperator).setPeriodDuration(newDuration);
      expect(await vault.periodDuration()).to.equal(newDuration);
    });

    it("Should fail if non-deposit operator tries to set period duration", async () => {
      await expect(vault.connect(user1).setPeriodDuration(172800)).to.be
        .reverted;
    });
  });

  describe("Deposits", () => {
    it("Should allow ETH deposits", async () => {
      const depositAmount: bigint = ethers.parseEther("1");

      await expect(
        vault.connect(user1).deposit(0, ZERO_ADDRESS, { value: depositAmount })
      )
        .to.emit(vault, "Deposited")
        .withArgs(user1.address, depositAmount);

      expect(await vault.getDeposit(user1.address, ZERO_ADDRESS)).to.equal(
        depositAmount
      );
    });

    it("Should allow ERC20 token deposits", async () => {
      const depositAmount: bigint = ethers.parseEther("10");

      await expect(
        vault.connect(user1).deposit(depositAmount, mockToken.target)
      )
        .to.emit(vault, "Deposited")
        .withArgs(user1.address, depositAmount);

      expect(await vault.getDeposit(user1.address, mockToken.target)).to.equal(
        depositAmount
      );
      expect(await mockToken.balanceOf(vault.target)).to.equal(depositAmount);
    });

    it("Should fail ETH deposit with zero amount", async () => {
      await expect(
        vault.connect(user1).deposit(0, ZERO_ADDRESS)
      ).to.be.revertedWith("Deposit amount must be greater than 0");
    });

    it("Should fail ERC20 deposit with zero amount", async () => {
      await expect(
        vault.connect(user1).deposit(0, mockToken.target)
      ).to.be.revertedWith("Deposit amount must be greater than 0");
    });
  });

  describe("Withdrawals", () => {
    beforeEach(async () => {
      // Prepare deposits
      await vault
        .connect(user1)
        .deposit(0, ZERO_ADDRESS, { value: ethers.parseEther("5") });
      await vault
        .connect(user1)
        .deposit(ethers.parseEther("50"), mockToken.target);
    });

    it("Should allow ETH withdrawals", async () => {
      const withdrawAmount: bigint = ethers.parseEther("2");
      const initialBalance: bigint = await ethers.provider.getBalance(
        user1.address
      );

      const tx = await vault
        .connect(user1)
        .withdraw(withdrawAmount, ZERO_ADDRESS);
      const receipt = await tx.wait();
      if (!receipt) {
        return;
      }
      const gasCost: bigint = receipt.gasUsed * tx.gasPrice;

      expect(await vault.getDeposit(user1.address, ZERO_ADDRESS)).to.equal(
        ethers.parseEther("3")
      );

      const finalBalance: bigint = await ethers.provider.getBalance(
        user1.address
      );
      expect(finalBalance + gasCost - initialBalance).to.equal(withdrawAmount);
    });

    it("Should allow ERC20 token withdrawals", async () => {
      const withdrawAmount: bigint = ethers.parseEther("20");
      const initialBalance: bigint = await mockToken.balanceOf(user1.address);

      await expect(
        vault.connect(user1).withdraw(withdrawAmount, mockToken.target)
      )
        .to.emit(vault, "Withdrawn")
        .withArgs(user1.address, withdrawAmount);

      expect(await vault.getDeposit(user1.address, mockToken.target)).to.equal(
        ethers.parseEther("30")
      );
      expect(await mockToken.balanceOf(user1.address)).to.equal(
        initialBalance + withdrawAmount
      );
    });

    it("Should fail withdrawal with zero amount", async () => {
      await expect(
        vault.connect(user1).withdraw(0, ZERO_ADDRESS)
      ).to.be.revertedWith("Withdrawal amount must be greater than 0");
    });

    it("Should fail withdrawal with insufficient balance", async () => {
      await expect(
        vault.connect(user1).withdraw(ethers.parseEther("10"), ZERO_ADDRESS)
      ).to.be.revertedWith("Insufficient balance");
    });
  });

  describe("Transfers", () => {
    beforeEach(async () => {
      // Prepare deposits
      await vault
        .connect(user1)
        .deposit(0, ZERO_ADDRESS, { value: ethers.parseEther("5") });
      await vault
        .connect(user1)
        .deposit(ethers.parseEther("50"), mockToken.target);
    });

    it("Should allow transfer of ETH by deposit operator", async () => {
      const transferAmount: bigint = ethers.parseEther("2");
      const initialBalance: bigint = await ethers.provider.getBalance(
        user2.address
      );

      await expect(
        vault
          .connect(depositOperator)
          .transfer(user1.address, user2.address, ZERO_ADDRESS, transferAmount)
      )
        .to.emit(vault, "Transferred")
        .withArgs(user1.address, user2.address, transferAmount);

      expect(await vault.getDeposit(user1.address, ZERO_ADDRESS)).to.equal(
        ethers.parseEther("3")
      );
      const finalBalance: bigint = await ethers.provider.getBalance(
        user2.address
      );
      expect(finalBalance - initialBalance).to.equal(transferAmount);
    });

    it("Should allow transfer of ERC20 tokens by deposit operator", async () => {
      const transferAmount: bigint = ethers.parseEther("20");
      const initialBalance: bigint = await mockToken.balanceOf(user2.address);

      await expect(
        vault
          .connect(depositOperator)
          .transfer(
            user1.address,
            user2.address,
            mockToken.target,
            transferAmount
          )
      )
        .to.emit(vault, "Transferred")
        .withArgs(user1.address, user2.address, transferAmount);

      expect(await vault.getDeposit(user1.address, mockToken.target)).to.equal(
        ethers.parseEther("30")
      );
      expect(await mockToken.balanceOf(user2.address)).to.equal(
        initialBalance + transferAmount
      );
    });

    it("Should fail if non-deposit operator tries to transfer", async () => {
      await expect(
        vault
          .connect(user2)
          .transfer(
            user1.address,
            user2.address,
            ZERO_ADDRESS,
            ethers.parseEther("1")
          )
      ).to.be.reverted;
    });

    it("Should fail transfer with zero amount", async () => {
      await expect(
        vault
          .connect(depositOperator)
          .transfer(user1.address, user2.address, ZERO_ADDRESS, 0)
      ).to.be.revertedWith("Transfer amount must be greater than 0");
    });

    it("Should fail transfer with insufficient balance", async () => {
      await expect(
        vault
          .connect(depositOperator)
          .transfer(
            user1.address,
            user2.address,
            ZERO_ADDRESS,
            ethers.parseEther("10")
          )
      ).to.be.revertedWith("Insufficient balance");
    });
  });

  describe("Spending Limits", () => {
    beforeEach(async () => {
      // Prepare deposits
      await vault
        .connect(user1)
        .deposit(0, ZERO_ADDRESS, { value: ethers.parseEther("100") });

      // Set spending limits for user1
      await vault.connect(user1).setSpendingLimit({
        maxPerSession: ethers.parseEther("10"),
        maxPerPeriod: ethers.parseEther("30"),
        periodStart: 0, // Will be set by contract
        spentInPeriod: 0, // Will be set by contract
        initialized: false, // Will be set by contract
      });
    });

    it("Should enforce per-session spending limit", async () => {
      // Transfer within limit should succeed
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("10")
        );

      // Transfer exceeding per-session limit should fail
      await expect(
        vault
          .connect(depositOperator)
          .transfer(
            user1.address,
            user2.address,
            ZERO_ADDRESS,
            ethers.parseEther("10.1")
          )
      ).to.be.revertedWith("Exceeds per-session limit");
    });

    it("Should enforce per-period spending limit", async () => {
      // First transfer
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("10")
        );

      // Second transfer
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("10")
        );

      // Third transfer
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("10")
        );

      // Fourth transfer should fail as it exceeds period limit
      await expect(
        vault
          .connect(depositOperator)
          .transfer(
            user1.address,
            user2.address,
            ZERO_ADDRESS,
            ethers.parseEther("0.1")
          )
      ).to.be.revertedWith("Exceeds period limit");
    });

    it("Should reset period spending when period duration passes", async () => {
      // First transfer
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("10")
        );

      // Second transfer
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("10")
        );

      // Advance time by more than period duration (1 day)
      await time.increase(86401);

      // Third transfer should succeed as period has reset
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("10")
        );
    });

    it("Should allow removing spending limit", async () => {
      await expect(vault.connect(user1).removeSpendingLimit())
        .to.emit(vault, "SpendingLimitRemoved")
        .withArgs(user1.address);

      // Should now be able to exceed previous limits
      await vault
        .connect(depositOperator)
        .transfer(
          user1.address,
          user2.address,
          ZERO_ADDRESS,
          ethers.parseEther("15")
        );
    });

    it("Should fail when trying to remove non-existent spending limit", async () => {
      await expect(
        vault.connect(user2).removeSpendingLimit()
      ).to.be.revertedWith("Spending limit not set");
    });
  });
});
