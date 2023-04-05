// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./IOracle.sol";

/// @title PimlicoERC20Paymaster
/// @notice A Paymaster contract for the Pimlico network that handles ERC20 token payments for transaction fees.
/// The contract supports refunding excess tokens if the actual gas cost is lower than the initially provided amount.
/// It also allows updating price configuration and withdrawing tokens by the contract owner.
/// The contract uses an Oracle to fetch the latest token prices.
/// @dev Inherits from BasePaymaster and adheres to the UserOperation interface.
contract PimlicoERC20Paymaster is BasePaymaster {
    uint256 public constant priceDenominator = 1e6;
    uint256 public constant REFUND_POSTOP_COST = 40000; // Estimated gas cost for refunding tokens after the transaction is completed
    uint256 public constant NO_REFUND_POSTOP_COST = 20000; // Estimated gas cost for the post-operation when no refund is needed

    IERC20 immutable token; // The ERC20 token used for transaction fee payments
    IOracle public immutable oracle; // The Oracle contract used to fetch the latest token prices

    uint192 public previousPrice; // The cached token price from the Oracle
    uint32 public priceMarkup; // The price markup percentage applied to the token price (1e6 = 100%)
    uint32 public priceUpdateThreshold; // The price update threshold percentage that triggers a price update (1e6 = 100%)

    event ConfigUpdated(uint32 priceMarkup, uint32 updateThreshold);

    /// @notice Initializes the PimlicoERC20Paymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The EntryPoint contract used in the Account Abstraction infrastructure.
    /// @param _oracle The Oracle contract used to fetch the latest token prices.
    constructor(IERC20 _token, IEntryPoint _entryPoint, IOracle _oracle) BasePaymaster(_entryPoint) {
        token = _token;
        oracle = _oracle;
        priceMarkup = 110e4; // 110%  1e6 = 100%
        priceUpdateThreshold = 25e3; // 2.5%  1e6 = 100%
    }

    /// @notice Updates the price markup and price update threshold configurations.
    /// @param _priceMarkup The new price markup percentage (1e6 = 100%).
    /// @param _updateThreshold The new price update threshold percentage (1e6 = 100%).
    function updateConfig(uint32 _priceMarkup, uint32 _updateThreshold) external onlyOwner {
        require(_priceMarkup <= 120e4, "price markup too high");
        require(_priceMarkup >= 1e6, "price markeup too low");
        priceMarkup = _priceMarkup;
        priceUpdateThreshold = _updateThreshold;
        emit ConfigUpdated(_priceMarkup, _updateThreshold);
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address to, uint256 amount) external onlyOwner {
        token.transfer(to, amount);
    }

    /// @notice Updates the token price by fetching the latest price from the Oracle.
    function updatePrice() external { // This function updates the cached ERC20/ETH price ratio
        (, int256 answer, , , ) = oracle.latestRoundData();
        previousPrice = uint192(int192(answer));
    }

    /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
    /// @param userOp The user operation data.
    /// @param requiredPreFund The amount of tokens required for pre-funding.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund) internal override returns (bytes memory context, uint256 validationResult) {
        unchecked {
            uint256 cachedPrice = previousPrice;
            uint32 cachedMarkup = priceMarkup;
            require(cachedPrice != 0, "price not set");
            uint256 length = userOp.paymasterAndData.length - 20;
            require(length & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffde == 0 , "invalid data length");
            bool refund = length % 2 == 0;
            uint256 tokenAmount = (requiredPreFund + (refund ? REFUND_POSTOP_COST : NO_REFUND_POSTOP_COST) * userOp.maxFeePerGas) * cachedMarkup / cachedPrice;
            if(length > 2) {
                require(tokenAmount <= uint256(bytes32(userOp.paymasterAndData[20:52])), "token amount too high");
            }
            token.transferFrom(userOp.sender, address(this), tokenAmount);
            context = refund ? abi.encodePacked(tokenAmount, userOp.sender) : bytes(hex"00");
            // No return here since validationData == 0 and we have context saved in memory
            validationResult = 0;
        }
    }

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens (if applicable).
    /// @param mode The post-operation mode (either successful or reverted).
    /// @param context The context containing the token amount and user sender address (if applicable).
    /// @param actualGasCost The actual gas cost of the transaction.
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        if(mode == PostOpMode.postOpReverted) {
            return; // Do nothing here to not revert the whole bundle and harm reputation
        }
        (, int256 price, , , ) = oracle.latestRoundData();
        unchecked {
            if(
                uint256(price) * priceDenominator / previousPrice > priceDenominator + priceUpdateThreshold ||
                    uint256(price) * priceDenominator / previousPrice < priceDenominator - priceUpdateThreshold
            ){
                previousPrice = uint192(int192(price));
            }

            // Refund tokens
            if(context.length == 52) {
                uint256 tokenAmount = uint256(bytes32(context[0:32]));
                address sender = address(bytes20(context[32:52]));
                // Refund tokens based on actual gas cost
                uint256 actualTokenNeeded = (actualGasCost + REFUND_POSTOP_COST * tx.gasprice ) * priceMarkup / uint192(int192(price)); // We use tx.gasprice here since we don't know the actual gas price used by the user
                if(tokenAmount > actualTokenNeeded) {
                    // If the initially provided token amount is greater than the actual amount needed, refund the difference
                    token.transfer(sender, tokenAmount - actualTokenNeeded);
                } // If the token amount is not greater than the actual amount needed, no refund occurs
            }
        }
    }
}
