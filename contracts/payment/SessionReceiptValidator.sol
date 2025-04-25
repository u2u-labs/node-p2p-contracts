// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./libraries/Types.sol";
import "./libraries/LibSessionReceipt.sol";

abstract contract SessionReceiptValidator is EIP712 {
    using ECDSA for bytes32;

    constructor(
        string memory name,
        string memory version
    ) EIP712(name, version) {}

    function hashSession(
        LibSessionReceipt.SessionReceipt memory sessionReceipt
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(LibSessionReceipt.hash(sessionReceipt));
    }
}
