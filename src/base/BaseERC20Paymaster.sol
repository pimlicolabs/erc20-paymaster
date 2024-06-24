// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./BasePaymaster.sol";

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SafeTransferLib} from "./../utils/SafeTransferLib.sol";
import {IOracle} from "./../interfaces/oracles/IOracle.sol";

abstract contract BaseERC20Paymaster is BasePaymaster {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The paymaster data mode is invalid. The mode should be 0, 1, 2, or 3.
    error PaymasterDataModeInvalid();

    /// @dev The paymaster data length is invalid for the selected mode.
    error PaymasterDataLengthInvalid();

    /// @dev The token amount is higher than the limit set.
    error TokenAmountTooHigh();

    /// @dev The token limit is set to zero in a paymaster mode that uses a limit.
    error TokenLimitZero();

    /// @dev The price markup selected is higher than the price markup limit.
    error PriceMarkupTooHigh();

    /// @dev The price markup selected is lower than break-even.
    error PriceMarkupTooLow();

    /// @dev The oracle price is stale.
    error OraclePriceStale();

    /// @dev The oracle price is less than or equal to zero.
    error OraclePriceNotPositive();

    /// @dev The oracle decimals are not set to 8.
    error OracleDecimalsInvalid();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ENUMS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    enum PaymasterType {
        V06,
        V07
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when the price markup is updated.
    event MarkupUpdated(uint32 priceMarkup);

    /// @dev Emitted when a user operation is sponsored by the paymaster.
    event UserOperationSponsored(
        bytes32 indexed userOpHash,
        address indexed user,
        address indexed guarantor,
        uint256 tokenAmountPaid,
        uint256 tokenPrice,
        bool paidByGuarantor
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The precision used for token price calculations.
    uint256 public constant PRICE_DENOMINATOR = 1e6;

    /// @dev The estimated gas cost for refunding tokens after the transaction is completed.
    uint256 public immutable refundPostOpCost;

    /// @dev The estimated gas cost for refunding tokens after the transaction is completed with a guarantor.
    uint256 public immutable refundPostOpCostWithGuarantor;

    /// @dev The ERC20 token used for transaction fee payments.
    IERC20 public immutable token;

    /// @dev The number of decimals used by the ERC20 token.
    uint256 public immutable tokenDecimals;

    /// @dev The oracle contract used to fetch the latest ERC20 to USD token prices.
    IOracle public immutable tokenOracle;

    /// @dev The Oracle contract used to fetch the latest native asset (e.g. ETH) to USD prices.
    IOracle public immutable nativeAssetOracle;

    // @dev The amount of time in seconds after which an oracle result should be considered stale.
    uint32 public immutable stalenessThreshold;

    /// @dev The maximum price markup percentage allowed (1e6 = 100%).
    uint32 public immutable priceMarkupLimit;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The price markup percentage applied to the token price (1e6 = 100%).
    uint32 public priceMarkup;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the ERC20Paymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The ERC-4337 EntryPoint contract.
    /// @param _tokenOracle The oracle contract used to fetch the latest token prices.
    /// @param _nativeAssetOracle The oracle contract used to fetch the latest native asset (ETH, Matic, Avax, etc.) prices.
    /// @param _owner The address that will be set as the owner of the contract.
    /// @param _priceMarkupLimit The maximum price markup percentage allowed (1e6 = 100%).
    /// @param _priceMarkup The initial price markup percentage applied to the token price (1e6 = 100%).
    /// @param _refundPostOpCost The estimated gas cost for refunding tokens after the transaction is completed.
    /// @param _refundPostOpCostWithGuarantor The estimated gas cost for refunding tokens after the transaction is completed with a guarantor.
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
    ) BasePaymaster(_entryPoint) {
        token = _token;
        tokenOracle = _tokenOracle; // oracle for token -> usd
        nativeAssetOracle = _nativeAssetOracle; // oracle for native asset(eth/matic/avax..) -> usd
        stalenessThreshold = _stalenessThreshold;
        priceMarkupLimit = _priceMarkupLimit;
        priceMarkup = _priceMarkup;
        refundPostOpCost = _refundPostOpCost;
        refundPostOpCostWithGuarantor = _refundPostOpCostWithGuarantor;
        transferOwnership(_owner);
        tokenDecimals = 10 ** _token.decimals();
        if (_priceMarkup < 1e6) {
            revert PriceMarkupTooLow();
        }
        if (_priceMarkup > _priceMarkupLimit) {
            revert PriceMarkupTooHigh();
        }
        if (_tokenOracle.decimals() != 8 || _nativeAssetOracle.decimals() != 8) {
            revert OracleDecimalsInvalid();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates the price markup.
    /// @param _priceMarkup The new price markup percentage (1e6 = 100%).
    function updateMarkup(uint32 _priceMarkup) external onlyOwner {
        if (_priceMarkup < 1e6) {
            revert PriceMarkupTooLow();
        }
        if (_priceMarkup > priceMarkupLimit) {
            revert PriceMarkupTooHigh();
        }
        priceMarkup = _priceMarkup;
        emit MarkupUpdated(_priceMarkup);
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address to, uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransfer(address(token), to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC HELPERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Fetches the latest token price.
    /// @return price The latest token price fetched from the oracles.
    function getPrice() public view returns (uint192) {
        uint256 price = Math.mulDiv(
            uint256(_fetchPrice(nativeAssetOracle)),
            tokenDecimals,
            uint256(_fetchPrice(tokenOracle)),
            Math.Rounding.Ceil
        );

        return uint192(price);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL HELPERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Parses the paymasterAndData field of the user operation and returns the paymaster mode and data.
    /// @param _paymasterAndData The paymasterAndData field of the user operation.
    /// @return mode The paymaster mode.
    /// @return paymasterConfig The paymaster configuration data.
    function _parsePaymasterAndData(bytes calldata _paymasterAndData) internal virtual pure returns (uint8, bytes calldata);

    /// @notice Fetches the latest price from the given oracle.
    /// @dev This function is used to get the latest price from the tokenOracle or nativeAssetOracle.
    /// @param _oracle The oracle contract to fetch the price from.
    /// @return price The latest price fetched from the oracle.
    function _fetchPrice(IOracle _oracle) internal view returns (uint192 price) {
        (, int256 answer,, uint256 updatedAt,) = _oracle.latestRoundData();
        if (answer <= 0) {
            revert OraclePriceNotPositive();
        }
        if (updatedAt < block.timestamp - stalenessThreshold) {
            revert OraclePriceStale();
        }
        price = uint192(int192(answer));
    }
}