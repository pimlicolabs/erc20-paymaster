// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./PaymasterFactory.sol";
import "./OracleFactory.sol";

import "@openzeppelin-v5.0.0/contracts/access/Ownable.sol";


contract ERC20PaymasterFactory is PaymasterFactory, OracleFactory {
    error RenounceOwnershipNotAllowed();

    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipNotAllowed();
    }

    constructor(
        address _owner
    ) Ownable(_owner) {}
}