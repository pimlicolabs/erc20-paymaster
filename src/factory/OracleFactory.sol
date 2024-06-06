// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {FixedOracle} from "./../oracles/FixedOracle.sol";
import {ManualOracle} from "./../oracles/ManualOracle.sol";
import {TwapOracle} from "./../oracles/TwapOracle.sol";

import {Create2} from "@openzeppelin-v5.0.0/contracts/utils/Create2.sol";
import "@openzeppelin-v5.0.0/contracts/access/Ownable.sol";


abstract contract OracleFactory is Ownable {
    event DeployedFixedOracle(
        bytes32 salt,
        address oracle,
        int256 price
    );

    event DeployedManualOracle(
        bytes32 salt,
        address oracle,
        int256 price
    );

    event DeployedTwapOracle(
        bytes32 salt,
        address oracle,
        address pool,
        uint32 twapAge,
        address baseToken
    );

    function deployFixedOracle(
        bytes32 salt,
        int256 _price
    ) external onlyOwner returns (address oracle) {
        bytes memory constructorArgs = abi.encode(_price);

        oracle = Create2.deploy(
            0,
            salt,
            abi.encodePacked(
                type(FixedOracle).creationCode,
                constructorArgs
            )
        );

        emit DeployedFixedOracle(
            salt,
            oracle,
            _price
        );
    }

    function deployManualOracle(
        bytes32 salt,
        int256 _price,
        address _owner
    ) external onlyOwner returns (address oracle) {
        bytes memory constructorArgs = abi.encode(
            _price,
            _owner
        );

        oracle = Create2.deploy(
            0,
            salt,
            abi.encodePacked(
                type(ManualOracle).creationCode,
                constructorArgs
            )
        );

        emit DeployedManualOracle(
            salt,
            oracle,
            _price
        );        
    }

    function deployTwapOracle(
        bytes32 salt,
        address _pool,
        uint32 _twapAge,
        address _baseToken
    ) external onlyOwner returns (address oracle) {
        bytes memory constructorArgs = abi.encode(
            _pool,
            _twapAge,
            _baseToken
        );

        oracle = Create2.deploy(
            0,
            salt,
            abi.encodePacked(
                type(TwapOracle).creationCode,
                constructorArgs
            )
        );

        emit DeployedTwapOracle(
            salt,
            oracle,
            _pool,
            _twapAge,
            _baseToken
        );
    }
}