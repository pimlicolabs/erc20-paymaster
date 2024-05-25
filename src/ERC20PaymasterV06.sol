// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;


import {IEntryPoint} from "@account-abstraction-v6/contracts/interfaces/IEntryPoint.sol";
import {UserOperationLib, UserOperation} from "@account-abstraction-v6/contracts/interfaces/UserOperation.sol";
import {_packValidationData} from "@account-abstraction-v6/contracts/core/Helpers.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {BaseERC20Paymaster} from "./base/BaseERC20Paymaster.sol";
import {IOracle} from "./interfaces/oracles/IOracle.sol";


using UserOperationLib for UserOperation;


/// @title ERC20Paymaster
/// @author Pimlico (https://github.com/pimlicolabs/erc20-paymaster/blob/main/src/ERC20Paymaster.sol)
/// @author Using Solady (https://github.com/vectorized/solady)
/// @notice An ERC-4337 Paymaster contract which is able to sponsor gas fees in exchange for ERC-20 tokens.
/// The contract refunds excess tokens. It also allows updating price configuration and withdrawing tokens by the contract owner.
/// The contract uses oracles to fetch the latest token prices.
/// The paymaster supports standard and up-rebasing ERC-20 tokens. It does not support down-rebasing and fee-on-transfer tokens.
/// @dev Inherits from BaseERC20Paymaster.
/// @custom:security-contact security@pimlico.io
contract ERC20PaymasterV06 is BaseERC20Paymaster {
    constructor(
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
    ) BaseERC20Paymaster(
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
    ) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-4337 PAYMASTER FUNCTIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates the paymaster data, calculates the required token amount, and transfers the tokens.
    /// @dev The paymaster supports one of four modes:
    /// 0. user pays, no limit
    ///     empty bytes (or any bytes with the first byte = 0x00)
    /// 1. user pays, with a limit
    ///     hex"01" + token spend limit (32 bytes)
    /// 2. user pays with a guarantor, no limit
    ///     hex"02" + guarantor address (20 bytes) + validUntil (6 bytes) + validAfter (6 bytes) + guarantor signature (dynamic bytes)
    /// 3. user pays with a guarantor, with a limit
    ///     hex"03" + token spend limit (32 bytes) + guarantor address (20 bytes) + validUntil (6 bytes) + validAfter (6 bytes) + guarantor signature (dynamic bytes)
    /// Note: modes 2 and 3 are not compatible with the default storage access rules of ERC-4337 and require a whitelist for the guarantors.
    /// @param userOp The user operation.
    /// @param userOpHash The hash of the user operation.
    /// @param maxCost The maximum cost in native tokens of this user operation.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        override
        returns (bytes memory context, uint256 validationResult)
    {
        (uint8 mode, bytes calldata paymasterConfig) = _parsePaymasterAndData(userOp.paymasterAndData);

        // valid modes are 0, 1, 2, 3
        if (mode >= 4) {
            revert PaymasterDataModeInvalid();
        }

        uint192 tokenPrice = getPrice();
        uint256 tokenAmount;
        {
            uint256 maxFeePerGas = userOp.maxFeePerGas;
            if (mode == 0 || mode == 1) {
                tokenAmount = (maxCost + (refundPostOpCost) * maxFeePerGas) * priceMarkup * tokenPrice
                    / (1e18 * PRICE_DENOMINATOR);
            } else {
                tokenAmount = (maxCost + (refundPostOpCostWithGuarantor) * maxFeePerGas) * priceMarkup * tokenPrice
                    / (1e18 * PRICE_DENOMINATOR);
            }
        }

        if (mode == 0) {
            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash);
            validationResult = 0;
        } else if (mode == 1) {
            if (paymasterConfig.length != 32) {
                revert PaymasterDataLengthInvalid();
            }
            if (uint256(bytes32(paymasterConfig[0:32])) == 0) {
                revert TokenLimitZero();
            }
            if (tokenAmount > uint256(bytes32(paymasterConfig[0:32]))) {
                revert TokenAmountTooHigh();
            }
            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash);
            validationResult = 0;
        } else if (mode == 2) {
            if (paymasterConfig.length < 32) {
                revert PaymasterDataLengthInvalid();
            }

            address guarantor = address(bytes20(paymasterConfig[0:20]));

            bool signatureValid = SignatureChecker.isValidSignatureNow(
                guarantor,
                getHash(userOp, uint48(bytes6(paymasterConfig[20:26])), uint48(bytes6(paymasterConfig[26:32])), 0),
                paymasterConfig[32:]
            );

            SafeTransferLib.safeTransferFrom(address(token), guarantor, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash, guarantor);
            validationResult = _packValidationData(
                !signatureValid, uint48(bytes6(paymasterConfig[20:26])), uint48(bytes6(paymasterConfig[26:32]))
            );
        } else {
            if (paymasterConfig.length < 64) {
                revert PaymasterDataLengthInvalid();
            }

            address guarantor = address(bytes20(paymasterConfig[32:52]));

            if (uint256(bytes32(paymasterConfig[0:32])) == 0) {
                revert TokenLimitZero();
            }
            if (tokenAmount > uint256(bytes32(paymasterConfig[0:32]))) {
                revert TokenAmountTooHigh();
            }

            bool signatureValid = SignatureChecker.isValidSignatureNow(
                guarantor,
                getHash(
                    userOp,
                    uint48(bytes6(paymasterConfig[52:58])),
                    uint48(bytes6(paymasterConfig[58:64])),
                    uint256(bytes32(paymasterConfig[0:32]))
                ),
                paymasterConfig[64:]
            );

            SafeTransferLib.safeTransferFrom(address(token), guarantor, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash, guarantor);
            validationResult = _packValidationData(
                !signatureValid, uint48(bytes6(paymasterConfig[52:58])), uint48(bytes6(paymasterConfig[58:64]))
            );
        }
    }

    /// @notice Performs post-operation tasks, such as refunding excess tokens and attempting to pay back the guarantor if there is one.
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param context The context containing the token amount and user sender address.
    /// @param actualGasCost The actual gas cost of the transaction.
    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost)
        internal
        override
    {
        uint256 prefundTokenAmount = uint256(bytes32(context[0:32]));
        uint192 tokenPrice = uint192(bytes24(context[32:56]));
        address sender = address(bytes20(context[56:76]));
        bytes32 userOpHash = bytes32(context[76:108]);

        if (context.length == 128) {
            // A guarantor is used
            uint256 actualTokenNeeded = (actualGasCost + refundPostOpCostWithGuarantor)
                * priceMarkup * tokenPrice / (1e18 * PRICE_DENOMINATOR);
            address guarantor = address(bytes20(context[108:128]));

            bool success = SafeTransferLib.trySafeTransferFrom(address(token), sender, address(this), actualTokenNeeded);
            if (success) {
                // If the token transfer is successful, transfer the held tokens back to the guarantor
                SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount);
                emit UserOperationSponsored(userOpHash, sender, guarantor, actualTokenNeeded, tokenPrice, false);
            } else {
                // If the token transfer fails, the guarantor is deemed responsible for the token payment
                SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount - actualTokenNeeded);
                emit UserOperationSponsored(userOpHash, sender, guarantor, actualTokenNeeded, tokenPrice, true);
            }
        } else {
            uint256 actualTokenNeeded = (actualGasCost + refundPostOpCost) * priceMarkup
                * tokenPrice / (1e18 * PRICE_DENOMINATOR);

            SafeTransferLib.safeTransfer(address(token), sender, prefundTokenAmount - actualTokenNeeded);
            emit UserOperationSponsored(userOpHash, sender, address(0), actualTokenNeeded, tokenPrice, false);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC HELPERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getHash(
        UserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter,
        uint256 tokenLimit
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                block.chainid,
                address(this),
                validUntil,
                validAfter,
                tokenLimit
            )
        );
    }
}