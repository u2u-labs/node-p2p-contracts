// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/INodesStorage.sol";

contract NodeAdmin is Ownable {
    address public voting;
    INodesStorage public storageContract;

    function setVoting(address _voting) external onlyOwner {
        require(_voting != address(0), "Zero address");

        voting = _voting;
    }

    function setNodesStorage(address _storage) external onlyOwner {
        require(_storage != address(0), "Zero address");

        storageContract = INodesStorage(_storage);
    }

    function remove(address node) external {
        require(msg.sender == voting, "Only voting can call");
        storageContract.removeNode(node);
    }
}
