// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "contracts/interfaces/INodesStorage.sol";

contract NodesStorage is Ownable, INodesStorage {
    mapping(address => bool) private _isNode;
    address[] private _nodeList;

    event NodeAdded(address indexed node);
    event NodeRemoved(address indexed node);

    constructor(address[] memory initialNodes) {
        for (uint256 i = 0; i < initialNodes.length; i++) {
            _addNode(initialNodes[i]);
        }
    }

    function isValidNode(address node) external view override returns (bool) {
        return _isNode[node];
    }

    function getValidNodes()
        external
        view
        override
        returns (address[] memory validNodes)
    {
        uint256 count = 0;

        for (uint256 i = 0; i < _nodeList.length; i++) {
            if (_isNode[_nodeList[i]]) {
                count++;
            }
        }

        validNodes = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < _nodeList.length; i++) {
            address node = _nodeList[i];
            if (_isNode[node]) {
                validNodes[index++] = node;
            }
        }
    }

    function getTotalValidNodes()
        external
        view
        override
        returns (uint256 total)
    {
        for (uint256 i = 0; i < _nodeList.length; i++) {
            if (_isNode[_nodeList[i]]) {
                total++;
            }
        }
    }

    function addNodes(address[] calldata newNodes) external onlyOwner {
        for (uint256 i = 0; i < newNodes.length; i++) {
            _addNode(newNodes[i]);
        }
    }

    function removeNode(address node) external onlyOwner {
        require(_isNode[node], "NodeStorage: Node not found");
        _isNode[node] = false;
        emit NodeRemoved(node);
    }

    function _addNode(address node) internal {
        if (!_isNode[node]) {
            _isNode[node] = true;
            _nodeList.push(node);
            emit NodeAdded(node);
        }
    }
}
