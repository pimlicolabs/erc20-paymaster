// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;


import {ERC20PaymasterV06} from "./../ERC20PaymasterV06.sol";
import {ERC20PaymasterV07} from "./../ERC20PaymasterV07.sol";
import {IOracle} from "./../interfaces/oracles/IOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Create2} from "@openzeppelin-v5.0.0/contracts/utils/Create2.sol";

import "@openzeppelin-v5.0.0/contracts/access/Ownable.sol";


enum PaymasterVersion {
    V06,
    V07
}

abstract contract PaymasterFactory is Ownable {
    event DeployedPaymaster(
        bytes32 salt,
        PaymasterVersion version,
        address token,
        address tokenOracle,
        address nativeAssetOracle,
        address entryPoint,
        address paymaster
    );

    function deployPaymaster(
        bytes32 salt,
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
    ) public onlyOwner returns (address paymaster) {
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
            salt,
            abi.encodePacked(
                bytecode,
                constructorArgs
            )
        );

        emit DeployedPaymaster(
            salt,
            _version,
            address(_token),
            address(_tokenOracle),
            address(_nativeAssetOracle),
            _entryPoint,
            paymaster
        );
    }

    function deployPaymasters(
        bytes32 salt,
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
    ) external onlyOwner {
        deployPaymaster(
            salt,
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
            salt,
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