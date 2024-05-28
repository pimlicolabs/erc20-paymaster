// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {FixedOracle} from "./../oracles/FixedOracle.sol";
import {ManualOracle} from "./../oracles/ManualOracle.sol";
import {TwapOracle} from "./../oracles/TwapOracle.sol";

import {Create2} from "@openzeppelin-v5.0.0/contracts/utils/Create2.sol";


abstract contract FactoryOracle {
    event DeployedFixedOracle(
        address oracle,
        int256 price
    );

    event DeployedManualOracle(
        string tag,
        address oracle,
        int256 price
    );

    event DeployedTwapOracle(
        address oracle,
        address pool,
        uint32 twapAge,
        address baseToken
    );

    function deployFixedOracle(
        int256 _price
    ) external returns (address oracle) {
        bytes memory constructorArgs = abi.encode(_price);

        oracle = Create2.deploy(
            0,
            keccak256(constructorArgs),
            abi.encodePacked(
                type(FixedOracle).creationCode,
                constructorArgs
            )
        );

        emit DeployedFixedOracle(
            oracle,
            _price
        );
    }

    function deployManualOracle(
        string memory _tag,
        int256 _price,
        address _owner
    ) external returns (address oracle) {
        bytes memory constructorArgs = abi.encode(
            _price,
            _owner
        );

        oracle = Create2.deploy(
            0,
            keccak256(abi.encode(_tag, constructorArgs)),
            abi.encodePacked(
                type(ManualOracle).creationCode,
                constructorArgs
            )
        );

        emit DeployedManualOracle(
            _tag,
            oracle,
            _price
        );        
    }

    function deployTwapOracle(
        address _pool,
        uint32 _twapAge,
        address _baseToken
    ) external returns (address oracle) {
        bytes memory constructorArgs = abi.encode(
            _pool,
            _twapAge,
            _baseToken
        );

        oracle = Create2.deploy(
            0,
            keccak256(constructorArgs),
            abi.encodePacked(
                type(TwapOracle).creationCode,
                constructorArgs
            )
        );

        emit DeployedTwapOracle(
            address(oracle),
            _pool,
            _twapAge,
            _baseToken
        );
    }
}