// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./lib/LibTypes.sol";

abstract contract BillValidator is EIP712 {
    using ECDSA for bytes32;

    // Use the shared structs
    using ECDSA for bytes32;

    bytes32 private constant DATA_PLAN_TYPEHASH =
        keccak256("DataPlan(uint256 unitPrice)");
    bytes32 private constant PAYMENT_TYPEHASH =
        keccak256("Payment(uint8 tokenType,address tokenAddress)");
    bytes32 private constant BILL_TYPEHASH =
        keccak256(
            "Bill(address node,address client,DataPlan dataPlan,Payment payment,uint256 usedAmount,uint256 nonce)DataPlan(uint256 unitPrice)Payment(uint8 tokenType,address tokenAddress)"
        );

    constructor(string memory name, string memory version)
        EIP712(name, version)
    {}

    function hashDataPlan(DataPlan memory dataPlan)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DATA_PLAN_TYPEHASH, dataPlan.unitPrice));
    }

    function hashPayment(Payment memory payment)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    PAYMENT_TYPEHASH,
                    payment.tokenType,
                    payment.tokenAddress
                )
            );
    }

    function hashBill(Bill memory bill) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        BILL_TYPEHASH,
                        bill.node,
                        bill.client,
                        hashDataPlan(bill.dataPlan),
                        hashPayment(bill.payment),
                        bill.usedAmount,
                        bill.nonce
                    )
                )
            );
    }
}
