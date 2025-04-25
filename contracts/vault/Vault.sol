// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./libraries/Types.sol";
import "../interfaces/INodesStorage.sol";

contract Vault is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant TOLERANCE = 5; // 5 seconds tolerance

    INodesStorage public nodesStorage;

    // State variables
    uint32 public periodDuration = 86400; //1 day in seconds
    mapping(address => mapping(address => uint256)) private deposits;
    mapping(address => SpendingLimit) private spendingLimits;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Transferred(address from, address to, uint256 amount);
    event SpendingLimitSet(address indexed user, SpendingLimit limit);
    event SpendingLimitRemoved(address indexed user);
    event PeriodReset(address indexed user);

    bytes32 public constant DEPOSIT_OPERATOR_ROLE =
        keccak256("DEPOSIT_OPERATOR_ROLE");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setNodesStorage(
        address _nodesStorage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_nodesStorage != address(0), "Invalid nodes storage address");
        nodesStorage = INodesStorage(_nodesStorage);
    }

    // Allow deposit operator to set the period duration for spending limits
    function setPeriodDuration(
        uint32 _periodDuration
    ) external onlyRole(DEPOSIT_OPERATOR_ROLE) {
        periodDuration = _periodDuration;
    }

    // Get the deposit balance for a client
    function getDeposit(
        address client,
        address tokenAddress
    ) external view returns (uint256) {
        return deposits[client][tokenAddress];
    }

    // Allow admin to grant the deposit operator role to an address
    function grantTransferOperatorRole(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEPOSIT_OPERATOR_ROLE, account);
    }

    function isDepositOperator(address account) external view returns (bool) {
        return hasRole(DEPOSIT_OPERATOR_ROLE, account);
    }

    // Set spending limit for the caller (client/user)
    function setSpendingLimit(SpendingLimit calldata spendingLimit) external {
        SpendingLimit memory newLimit = SpendingLimit({
            maxPerSession: spendingLimit.maxPerSession,
            maxPerPeriod: spendingLimit.maxPerPeriod,
            periodStart: block.timestamp,
            spentInPeriod: 0,
            initialized: true
        });
        spendingLimits[msg.sender] = newLimit;
        emit SpendingLimitSet(msg.sender, newLimit);
    }

    // Remove the spending limit for the client
    function removeSpendingLimit() external {
        require(
            spendingLimits[msg.sender].initialized,
            "Spending limit not set"
        );

        delete spendingLimits[msg.sender];

        emit SpendingLimitRemoved(msg.sender);
    }

    // Perform a transfer from 'from' to 'to' while respecting spending limits
    function transfer(
        address from,
        address to,
        address tokenAddress,
        uint256 amount
    )
        external
        onlyRole(DEPOSIT_OPERATOR_ROLE)
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        // require(nodesStorage.isValidNode(to), "Invalid node address");

        uint256 balance = deposits[from][tokenAddress];

        // Process spending limit checks first
        if (spendingLimits[from].initialized) {
            checkSpendingLimit(from, amount);
        }

        // Ensure the transfer is valid and that the sender has enough balance
        require(amount > 0, "Transfer amount must be greater than 0");
        require(amount <= balance, "Insufficient balance");

        // Update the sender's deposit balance
        deposits[from][tokenAddress] = balance - amount;

        // Perform the transfer to the recipient
        if (tokenAddress == address(0)) {
            (success, ) = to.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(to, amount);
        }

        emit Transferred(from, to, amount);
    }

    // Deposit ETH into the vault
    function deposit(
        uint256 amount,
        address tokenAddress
    ) external payable nonReentrant whenNotPaused {
        if (tokenAddress == address(0)) {
            require(msg.value > 0, "Deposit amount must be greater than 0");
            deposits[msg.sender][tokenAddress] += msg.value;
        } else {
            require(amount > 0, "Deposit amount must be greater than 0");
            deposits[msg.sender][tokenAddress] += amount;
            IERC20(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        emit Deposited(
            msg.sender,
            tokenAddress == address(0) ? msg.value : amount
        );
    }

    // Withdraw ETH from the vault
    function withdraw(
        uint256 amount,
        address tokenAddress
    ) external nonReentrant whenNotPaused {
        uint256 balance = deposits[msg.sender][tokenAddress];

        require(amount > 0, "Withdrawal amount must be greater than 0");
        require(amount <= balance, "Insufficient balance");

        deposits[msg.sender][tokenAddress] = balance - amount;

        // Perform the withdrawal to the user
        bool success;
        if (tokenAddress == address(0)) {
            (success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, amount);
        }

        emit Withdrawn(msg.sender, amount);
    }

    // Internal function to process and check the spending limit for a client using BokkyPooBah's DateTime
    function checkSpendingLimit(
        address client,
        uint256 amountToSpend
    ) internal {
        SpendingLimit storage spendingLimit = spendingLimits[client];

        // Check if the period has ended using DateTime library
        uint256 periodEnd = spendingLimit.periodStart + periodDuration;

        if (block.timestamp >= periodEnd + TOLERANCE) {
            spendingLimit.periodStart = block.timestamp; // Update the period start time to the current time block timestamp
            spendingLimit.spentInPeriod = 0; // Reset spent amount if the period is over
            emit PeriodReset(client);
        }

        // Check if the amount exceeds the per-session limit
        require(
            amountToSpend <= spendingLimit.maxPerSession,
            "Exceeds per-session limit"
        );

        // Check if the amount exceeds the total allowed spending for the period
        require(
            spendingLimit.spentInPeriod + amountToSpend <=
                spendingLimit.maxPerPeriod,
            "Exceeds period limit"
        );

        // Update the spent amount in the current period
        spendingLimit.spentInPeriod += amountToSpend;
    }
}
