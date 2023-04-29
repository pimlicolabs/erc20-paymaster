// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./interfaces/IOracle.sol";
import "@account-abstraction/contracts/core/EntryPoint.sol";
import "./utils/SafeTransferLib.sol";

/// @title PimlicoERC20Paymaster
/// @notice An ERC-4337 Paymaster contract by Pimlico which is able to sponsor gas fees in exchange for ERC20 tokens.
/// The contract refunds excess tokens if the actual gas cost is lower than the initially provided amount.
/// It also allows updating price configuration and withdrawing tokens by the contract owner.
/// The contract uses an Oracle to fetch the latest token prices.
/// @dev Inherits from BasePaymaster.

contract PimlicoERC20Paymaster is BasePaymaster {
    uint256 public constant priceDenominator = 1e6;
    uint256 public constant REFUND_POSTOP_COST = 40000; // Estimated gas cost for refunding tokens after the transaction is completed

    IERC20 public immutable token; // The ERC20 token used for transaction fee payments
    uint256 public immutable tokenDecimals;
    IOracle public immutable tokenOracle; // The Oracle contract used to fetch the latest token prices
    IOracle public immutable nativeAssetOracle; // The Oracle contract used to fetch the latest ETH prices

    uint192 public previousPrice; // The cached token price from the Oracle
    uint32 public priceMarkup; // The price markup percentage applied to the token price (1e6 = 100%)
    uint32 public priceUpdateThreshold; // The price update threshold percentage that triggers a price update (1e6 = 100%)

    event ConfigUpdated(uint32 priceMarkup, uint32 updateThreshold);

    event UserOperationSponsored(address indexed user, uint256 actualTokenNeeded, uint256 actualGasCost);

    /// @notice Initializes the PimlicoERC20Paymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The EntryPoint contract used in the Account Abstraction infrastructure.
    /// @param _tokenOracle The Oracle contract used to fetch the latest token prices.
    constructor(IERC20Metadata _token, IEntryPoint _entryPoint, IOracle _tokenOracle, IOracle _ethOracle, address _owner) BasePaymaster(_entryPoint) {
        token = _token;
        tokenOracle= _tokenOracle; // oracle for token -> usd
        nativeAssetOracle = _ethOracle; // oracle for eth -> usd
        priceMarkup = 110e4; // 110%  1e6 = 100%
        priceUpdateThreshold = 25e3; // 2.5%  1e6 = 100%
        transferOwnership(_owner);
        tokenDecimals = 10 ** _token.decimals();
    }

    /// @notice Updates the price markup and price update threshold configurations.
    /// @param _priceMarkup The new price markup percentage (1e6 = 100%).
    /// @param _updateThreshold The new price update threshold percentage (1e6 = 100%).
    function updateConfig(uint32 _priceMarkup, uint32 _updateThreshold) external onlyOwner {
        require(_priceMarkup <= 120e4, "price markup too high");
        require(_priceMarkup >= 1e6, "price markeup too low");
        require(_updateThreshold <= 1e6, "update threshold too high");
        priceMarkup = _priceMarkup;
        priceUpdateThreshold = _updateThreshold;
        emit ConfigUpdated(_priceMarkup, _updateThreshold);
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address to, uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransfer(address(token),to,amount);
    }

    /// @notice Updates the token price by fetching the latest price from the Oracle.
    function updatePrice() external {
        // This function updates the cached ERC20/ETH price ratio
        uint192 tokenPrice = fetchPrice(tokenOracle);
        uint192 ethPrice = fetchPrice(nativeAssetOracle);
        previousPrice = ethPrice * uint192(tokenDecimals) / tokenPrice;
    }

    /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
    /// @param userOp The user operation data.
    /// @param requiredPreFund The amount of tokens required for pre-funding.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund)
        internal
        override
        returns (bytes memory context, uint256 validationResult)
    {
        unchecked {
            uint256 cachedPrice = previousPrice;
            require(cachedPrice != 0, "price not set");
            uint256 length = userOp.paymasterAndData.length - 20;
            // 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffdf is the mask for the last 6 bits 011111 which mean length should be 100000(32) || 000000(0)
            require(
                length & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffdf == 0, "invalid data length"
            );
            uint256 tokenAmount = (requiredPreFund + (REFUND_POSTOP_COST) * userOp.maxFeePerGas)
                * priceMarkup * cachedPrice /  (1e18*priceDenominator);
            if (length == 32) {
                require(tokenAmount <= uint256(bytes32(userOp.paymasterAndData[20:52])), "token amount too high");
            }
            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, userOp.sender);
            // No return here since validationData == 0 and we have context saved in memory
            validationResult = 0;
        }
    }

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
    /// @param mode The post-operation mode (either successful or reverted).
    /// @param context The context containing the token amount and user sender address.
    /// @param actualGasCost The actual gas cost of the transaction.
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        if (mode == PostOpMode.postOpReverted) {
            return; // Do nothing here to not revert the whole bundle and harm reputatokenOracle
        }
        unchecked {
        uint192 tokenPrice = fetchPrice(tokenOracle);
        uint192 ethPrice = fetchPrice(nativeAssetOracle);
        uint256 cachedPrice = previousPrice;
        uint192 price = ethPrice * uint192(tokenDecimals) / tokenPrice;
        uint256 cachedUpdateThreshold = priceUpdateThreshold;
            if (
                uint256(price) * priceDenominator / cachedPrice > priceDenominator + cachedUpdateThreshold
                    || uint256(price) * priceDenominator / cachedPrice < priceDenominator - cachedUpdateThreshold
            ) {
                previousPrice = uint192(int192(price));
                cachedPrice = uint192(int192(price));
            }
            // Refund tokens based on actual gas cost
            uint256 actualTokenNeeded =
                (actualGasCost + REFUND_POSTOP_COST * tx.gasprice) * priceMarkup * cachedPrice /  (1e18*priceDenominator); // We use tx.gasprice here since we don't know the actual gas price used by the user
            if (uint256(bytes32(context[0:32])) > actualTokenNeeded) {
                // If the initially provided token amount is greater than the actual amount needed, refund the difference
                SafeTransferLib.safeTransfer(address(token), address(bytes20(context[32:52])), uint256(bytes32(context[0:32])) - actualTokenNeeded);
            } // If the token amount is not greater than the actual amount needed, no refund occurs

            emit UserOperationSponsored(address(bytes20(context[32:52])), actualTokenNeeded, actualGasCost);
        }
    }

    function fetchPrice(IOracle _oracle) internal view returns(uint192 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();

        require(answer > 0, "Chainlink price <= 0");
        require(updatedAt >= block.timestamp - 60*60*24*2, "Incomplete round");
        require(answeredInRound >= roundId, "Stale price");
        price = uint192(int192(answer));
    }
}
