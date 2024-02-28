// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

// Import the required libraries and contracts
import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./interfaces/IOracle.sol";
import "@account-abstraction/contracts/core/EntryPoint.sol";
import "@account-abstraction/contracts/core/UserOperationLib.sol";
import "./utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title PimlicoERC20Paymaster
/// @notice An ERC-4337 Paymaster contract by Pimlico which is able to sponsor gas fees in exchange for ERC20 tokens.
/// The contract refunds excess tokens if the actual gas cost is lower than the initially provided amount.
/// It also allows updating price configuration and withdrawing tokens by the contract owner.
/// The contract uses an Oracle to fetch the latest token prices.
/// @dev Inherits from BasePaymaster.
///
contract PimlicoERC20Paymaster is BasePaymaster {
    using UserOperationLib for PackedUserOperation;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The paymaster data mode is invalid.
    error InvalidPaymasterDataMode();

    /// @dev The token amount is higher than the limit set.
    error TokenAmountTooHigh();

    /// @dev The token limit is set to zero in a paymaster mode that uses a limit.
    error TokenLimitZero();

    /// @dev The price markup selected is higher than the price markup limit.
    error PriceMarkupTooHigh();

    /// @dev The price markup selected is lower than break-even.
    error PriceMarkupTooLow();

    /// @dev The oracle price is incomplete.
    error IncompleteOracleRound();

    /// @dev The oracle price is stale.
    error StaleOraclePrice();

    /// @dev The oracle price is less than or equal to zero.
    error OraclePriceZero();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The precision used for token price calculations.
    uint256 public constant PRICE_DENOMINATOR = 1e6;

    /// @dev The estimated gas cost for refunding tokens after the transaction is completed.
    uint256 public constant REFUND_POSTOP_COST = 30000;

    /// @dev The ERC20 token used for transaction fee payments.
    IERC20 public immutable token;

    /// @dev The number of decimals used by the ERC20 token.
    uint256 public immutable tokenDecimals;

    /// @dev The oracle contract used to fetch the latest ERC20 to USD token prices.
    IOracle public immutable tokenOracle;

    /// @dev The Oracle contract used to fetch the latest native asset (e.g. ETH) to USD prices.
    IOracle public immutable nativeAssetOracle;

    /// @dev The maximum price markup percentage allowed (1e6 = 100%).
    uint32 public immutable priceMarkupLimit;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The price markup percentage applied to the token price (1e6 = 100%).
    uint32 public priceMarkup;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when the price markup is updated.
    event MarkupUpdated(uint32 priceMarkup);

    /// @notice Emitted when a user operation is sponsored by the paymaster.
    event UserOperationSponsored(
        address indexed user,
        address indexed guarantor,
        uint256 tokenAmountPaid,
        uint256 tokenPrice,
        bool paidByGuarantor
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the PimlicoERC20Paymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The EntryPoint contract used in the Account Abstraction infrastructure.
    /// @param _tokenOracle The Oracle contract used to fetch the latest token prices.
    /// @param _nativeAssetOracle The Oracle contract used to fetch the latest native asset (ETH, Matic, Avax, etc.) prices.
    /// @param _owner The address that will be set as the owner of the contract.
    /// @param _priceMarkupLimit The maximum price markup percentage allowed (1e6 = 100%).
    /// @param _priceMarkup The initial price markup percentage applied to the token price (1e6 = 100%).
    constructor(
        IERC20Metadata _token,
        IEntryPoint _entryPoint,
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        address _owner,
        uint32 _priceMarkupLimit,
        uint32 _priceMarkup
    ) BasePaymaster(_entryPoint) {
        token = _token;
        tokenOracle = _tokenOracle; // oracle for token -> usd
        nativeAssetOracle = _nativeAssetOracle; // oracle for native asset(eth/matic/avax..) -> usd
        priceMarkupLimit = _priceMarkupLimit;
        priceMarkup = _priceMarkup;
        transferOwnership(_owner);
        tokenDecimals = 10 ** _token.decimals();
        require(_tokenOracle.decimals() == 8, "PP-ERC20: token oracle decimals must be 8");
        require(_nativeAssetOracle.decimals() == 8, "PP-ERC20: native asset oracle decimals must be 8");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-4337 PAYMASTER FUNCTIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
    /// @param userOp The user operation data.
    /// @param maxCost The amount of tokens required for pre-funding.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        internal
        override
        returns (bytes memory context, uint256 validationResult)
    {
        // paymasterData (the data after the first 52 bytes of paymasterAndData) should either be one of the following modes:
        // 0. empty (no limit, no guarantor)
        // 1. hex"01" + token spend limit (32 bytes)
        // 2. hex"02" + guarantor address (20 bytes) + validUntil (6 bytes) + validAfter (6 bytes) + guarantor signature (dynamic bytes)
        // 3. hex"03" + token spend limit (32 bytes) + guarantor address (20 bytes) + validUntil (6 bytes) + validAfter (6 bytes) + guarantor signature (dynamic bytes)
        (uint8 mode, bytes calldata paymasterConfig) = _parsePaymasterAndData(userOp.paymasterAndData);

        require(
            mode == uint8(0) || mode == uint8(1) || mode == uint8(2) || mode == uint8(3),
            "PP-ERC20: invalid paymaster data mode"
        );

        uint192 tokenPrice = getPrice();
        uint256 tokenAmount;
        {
            uint256 maxFeePerGas = UserOperationLib.unpackMaxFeePerGas(userOp);
            tokenAmount =
                (maxCost + (REFUND_POSTOP_COST) * maxFeePerGas) * priceMarkup * tokenPrice / (1e18 * PRICE_DENOMINATOR);
        }

        if (mode == uint8(0)) {
            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender);
            validationResult = 0;
        } else if (mode == uint8(1)) {
            require(uint256(bytes32(paymasterConfig[0:32])) > 0, "PP-ERC20: token limit = 0");
            require(tokenAmount <= uint256(bytes32(paymasterConfig[0:32])), "PP-ERC20: token amount too high");
            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender);
            validationResult = 0;
        } else if (mode == uint8(2)) {
            address guarantor = address(bytes20(paymasterConfig[0:20]));
            uint48 validUntil = uint48(bytes6(paymasterConfig[20:26]));
            uint48 validAfter = uint48(bytes6(paymasterConfig[26:32]));

            if (
                !SignatureChecker.isValidSignatureNow(
                    guarantor, getHash(userOp, validUntil, validAfter, 0), paymasterConfig[32:]
                )
            ) {
                // don not revert on signature failure: return SIG_VALIDATION_FAILED
                validationResult = _packValidationData(true, validUntil, validAfter);
                return ("", validationResult);
            }

            SafeTransferLib.safeTransferFrom(address(token), guarantor, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, guarantor);
            validationResult = _packValidationData(false, validUntil, validAfter);
        } else {
            address guarantor = address(bytes20(paymasterConfig[32:52]));
            uint48 validUntil = uint48(bytes6(paymasterConfig[52:58]));
            uint48 validAfter = uint48(bytes6(paymasterConfig[58:64]));

            require(uint256(bytes32(paymasterConfig[0:32])) > 0, "PP-ERC20: token limit = 0");
            require(tokenAmount <= uint256(bytes32(paymasterConfig[0:32])), "PP-ERC20: token amount too high");

            if (
                !SignatureChecker.isValidSignatureNow(
                    guarantor,
                    getHash(userOp, validUntil, validAfter, uint256(bytes32(paymasterConfig[0:32]))),
                    paymasterConfig[64:]
                )
            ) {
                // don not revert on signature failure: return SIG_VALIDATION_FAILED
                validationResult = _packValidationData(true, validUntil, validAfter);
                return ("", validationResult);
            }

            SafeTransferLib.safeTransferFrom(address(token), guarantor, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, guarantor);
            validationResult = _packValidationData(false, validUntil, validAfter);
        }
    }

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
    /// Emits a {UserOperationSponsored} event.
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param context The context containing the token amount and user sender address.
    /// @param actualGasCost The actual gas cost of the transaction.
    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        internal
        override
    {
        uint256 prefundTokenAmount = uint256(bytes32(context[0:32]));
        uint192 tokenPrice = uint192(bytes24(context[32:56]));
        address sender = address(bytes20(context[56:76]));
        uint256 actualTokenNeeded = (actualGasCost + REFUND_POSTOP_COST * actualUserOpFeePerGas) * priceMarkup
            * tokenPrice / (1e18 * PRICE_DENOMINATOR); // We use tx.gasprice here since we don't know the actual gas price used by the user

        if (context.length == 96) {
            address guarantor = address(bytes20(context[76:96]));

            bool success = _safeTransferFrom(address(token), sender, address(this), actualTokenNeeded);
            if (success) {
                // If the token transfer is successful, transfer the held tokens back to the guarantor
                SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount);
                emit UserOperationSponsored(sender, guarantor, actualTokenNeeded, tokenPrice, false);
            } else {
                // If the token transfer fails, the guarantor is deemed responsible for the token payment
                SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount - actualTokenNeeded);
                emit UserOperationSponsored(sender, guarantor, actualTokenNeeded, tokenPrice, true);
            }
        } else {
            SafeTransferLib.safeTransfer(address(token), sender, prefundTokenAmount - actualTokenNeeded);
            emit UserOperationSponsored(sender, address(0), actualTokenNeeded, tokenPrice, false);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates the price markup.
    /// @param _priceMarkup The new price markup percentage (1e6 = 100%).
    function updateMarkup(uint32 _priceMarkup) external onlyOwner {
        require(_priceMarkup <= priceMarkupLimit, "PP-ERC20: price markup too high");
        require(_priceMarkup >= 1e6, "PP-ERC20: price markeup too low");
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
        uint192 tokenPrice = _fetchPrice(tokenOracle);
        uint192 nativeAsset = _fetchPrice(nativeAssetOracle);
        uint192 price = nativeAsset * uint192(tokenDecimals) / tokenPrice;

        return price;
    }

    /// @notice Hashes the user operation data.
    /// @param userOp The user operation data.
    /// @param validUntil The timestamp until which the user operation is valid.
    /// @param validAfter The timestamp after which the user operation is valid.
    /// @param tokenLimit The maximum amount of tokens allowed for the user operation. 0 if no limit.
    function getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter, uint256 tokenLimit)
        public
        view
        returns (bytes32)
    {
        address sender = userOp.getSender();
        return keccak256(
            abi.encode(
                sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter,
                tokenLimit
            )
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL HELPERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sends `amount` of ERC20 `token` from the contract to `to`.
    /// @dev Doesn't revert on failure, but returns false.
    /// The `from` account must have at least `amount` approved for
    /// the current contract to manage.
    /// See https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol
    /// @param _token The ERC20 token to transfer.
    /// @param _from The address to transfer the tokens from.
    /// @param _to The address to transfer the tokens to.
    /// @param _amount The amount of tokens to transfer.
    /// @return success Whether the transfer was successful.
    function _safeTransferFrom(address _token, address _from, address _to, uint256 _amount)
        internal
        returns (bool success)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.

            mstore(0x60, _amount) // Store the `amount` argument.
            mstore(0x40, _to) // Store the `to` argument.
            mstore(0x2c, shl(96, _from)) // Store the `from` argument.
            // Store the function selector of `transferFrom(address,address,uint256)`.
            mstore(0x0c, 0x23b872dd000000000000000000000000)

            success :=
                and( // The arguments of `and` are evaluated from right to left.
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(eq(mload(0x00), 1), iszero(returndatasize())),
                    call(gas(), _token, 0, 0x1c, 0x64, 0x00, 0x20)
                )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /// @notice Parses the paymasterAndData field of the user operation and returns the paymaster mode and data.
    /// @param _paymasterAndData The paymasterAndData field of the user operation.
    /// @return mode The paymaster mode.
    /// @return paymasterConfig The paymaster configuration data.
    function _parsePaymasterAndData(bytes calldata _paymasterAndData) internal pure returns (uint8, bytes calldata) {
        if (_paymasterAndData.length < 53) {
            return (0, msg.data[0:0]);
        }
        return (uint8(_paymasterAndData[52]), _paymasterAndData[53:]);
    }

    /// @notice Fetches the latest price from the given oracle.
    /// @dev This function is used to get the latest price from the tokenOracle or nativeAssetOracle.
    /// @param _oracle The oracle contract to fetch the price from.
    /// @return price The latest price fetched from the oracle.
    function _fetchPrice(IOracle _oracle) internal view returns (uint192 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();
        require(answer > 0, "PP-ERC20: Oracle price <= 0");
        // 2 days old price is considered stale since the price is updated every 24 hours
        require(updatedAt >= block.timestamp - 60 * 60 * 24 * 2, "PP-ERC20: Incomplete round");
        require(answeredInRound >= roundId, "PP-ERC20: Stale price");
        price = uint192(int192(answer));
    }
}
