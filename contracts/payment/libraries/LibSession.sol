// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Types.sol";
import "./LibPayment.sol";

library LibSession {
    bytes32 private constant SESSION_TYPEHASH =
        keccak256(
            "Session(string sessionId,address client,Payment payment,uint256 requestedSeconds,uint16 nonce)Payment(address tokenAddress, uin256 amount)"
        );

    struct Session {
        string sessionId;
        address client;
        LibPayment.Payment payment;
        uint256 requestedSeconds;
        bytes gatewaySignature;
        uint256 nonce;
    }

    function hash(Session memory session) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    session.sessionId,
                    session.client,
                    LibPayment.hash(session.payment),
                    session.requestedSeconds,
                    session.nonce
                )
            );
    }
}
