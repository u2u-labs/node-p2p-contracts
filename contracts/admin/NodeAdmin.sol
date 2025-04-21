// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/INodesStorage.sol";

contract NodeAdmin {
    address public voting;
    INodesStorage public storageContract;

    constructor(address _voting, address _storage) {
        voting = _voting;
        storageContract = INodesStorage(_storage);
    }

    function remove(address node) external {
        require(msg.sender == voting, "Only voting can call");
        storageContract.removeNode(node);
    }
}
