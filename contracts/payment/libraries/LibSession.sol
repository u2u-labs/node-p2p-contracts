// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";
import "./LibPayment.sol";

library LibSession {
    bytes32 private constant SESSION_TYPEHASH =
        keccak256(
            "Session(address node,Payment payment,uint256 startTimestamp,uint256 nonce)Payment(uint8 tokenType,address tokenAddress,uint256 unitPrice)"
        );

    struct Session {
        address node;
        LibPayment.Payment payment;
        uint256 startTimestamp;
        uint256 nonce;
    }

    function hash(Session memory session) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    session.node,
                    LibPayment.hash(session.payment),
                    session.startTimestamp,
                    session.nonce
                )
            );
    }
}
