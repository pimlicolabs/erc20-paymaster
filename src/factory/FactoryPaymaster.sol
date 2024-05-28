// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;


import {ERC20PaymasterV06} from "./../ERC20PaymasterV06.sol";
import {ERC20PaymasterV07} from "./../ERC20PaymasterV07.sol";
import {IOracle} from "./../interfaces/oracles/IOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Create2} from "@openzeppelin-v5.0.0/contracts/utils/Create2.sol";


enum PaymasterVersion {
    V06,
    V07
}

contract FactoryPaymaster {
    event DeployedPaymaster(
        PaymasterVersion version,
        address token,
        address tokenOracle,
        address nativeAssetOracle,
        address entryPoint,
        address paymaster
    );

    function deployPaymaster(
        PaymasterVersion _version,
        IERC20Metadata _token,
        address _entryPoint,
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        uint32 _stalenessThreshold,
        address _owner,
        uint32 _priceMarkupLimit,
        uint32 _priceMarkup,
        uint256 _refundPostOpCost,
        uint256 _refundPostOpCostWithGuarantor
    ) public returns (address paymaster) {
        bytes memory bytecode;
        if (_version == PaymasterVersion.V06) {
            bytecode = type(ERC20PaymasterV06).creationCode;
        } else {
            bytecode = type(ERC20PaymasterV07).creationCode;
        }

        bytes memory constructorArgs = abi.encode(
            _token,
            _entryPoint,
            _tokenOracle,
            _nativeAssetOracle,
            _stalenessThreshold,
            _owner,
            _priceMarkupLimit,
            _priceMarkup,
            _refundPostOpCost,
            _refundPostOpCostWithGuarantor
        );

        paymaster = Create2.deploy(
            0,
            keccak256(abi.encode(_version, constructorArgs)),
            abi.encodePacked(
                bytecode,
                constructorArgs
            )
        );

        emit DeployedPaymaster(
            _version,
            address(_token),
            address(_tokenOracle),
            address(_nativeAssetOracle),
            _entryPoint,
            paymaster
        );
    }

    function deployPaymasters(
        IERC20Metadata _token,
        address _entryPoint,
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        uint32 _stalenessThreshold,
        address _owner,
        uint32 _priceMarkupLimit,
        uint32 _priceMarkup,
        uint256 _refundPostOpCost,
        uint256 _refundPostOpCostWithGuarantor
    ) external {
        deployPaymaster(
            PaymasterVersion.V06,
            _token,
            _entryPoint,
            _tokenOracle,
            _nativeAssetOracle,
            _stalenessThreshold,
            _owner,
            _priceMarkupLimit,
            _priceMarkup,
            _refundPostOpCost,
            _refundPostOpCostWithGuarantor
        );

        deployPaymaster(
            PaymasterVersion.V07,
            _token,
            _entryPoint,
            _tokenOracle,
            _nativeAssetOracle,
            _stalenessThreshold,
            _owner,
            _priceMarkupLimit,
            _priceMarkup,
            _refundPostOpCost,
            _refundPostOpCostWithGuarantor
        );
    }
}