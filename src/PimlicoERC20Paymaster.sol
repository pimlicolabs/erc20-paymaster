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

contract PimlicoERC20Paymaster is BasePaymaster {
    using UserOperationLib for PackedUserOperation;

    uint256 public constant priceDenominator = 1e6;
    uint256 public constant REFUND_POSTOP_COST = 30000; // Estimated gas cost for refunding tokens after the transaction is completed

    // The token, tokenOracle, and nativeAssetOracle are declared as immutable,
    // meaning their values cannot change after contract creation.
    IERC20 public immutable token; // The ERC20 token used for transaction fee payments
    uint256 public immutable tokenDecimals;
    IOracle public immutable tokenOracle; // The Oracle contract used to fetch the latest token prices
    IOracle public immutable nativeAssetOracle; // The Oracle contract used to fetch the latest ETH prices

    uint32 public priceMarkup; // The price markup percentage applied to the token price (1e6 = 100%)

    event ConfigUpdated(uint32 priceMarkup);

    event UserOperationSponsored(address indexed user, uint256 actualTokenNeeded, uint256 actualGasCost);

    /// @notice Initializes the PimlicoERC20Paymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The EntryPoint contract used in the Account Abstraction infrastructure.
    /// @param _tokenOracle The Oracle contract used to fetch the latest token prices.
    /// @param _nativeAssetOracle The Oracle contract used to fetch the latest native asset (ETH, Matic, Avax, etc.) prices.
    /// @param _owner The address that will be set as the owner of the contract.
    constructor(
        IERC20Metadata _token,
        IEntryPoint _entryPoint,
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        address _owner
    ) BasePaymaster(_entryPoint) {
        token = _token;
        tokenOracle = _tokenOracle; // oracle for token -> usd
        nativeAssetOracle = _nativeAssetOracle; // oracle for native asset(eth/matic/avax..) -> usd
        priceMarkup = 110e4; // 110%  1e6 = 100%
        transferOwnership(_owner);
        tokenDecimals = 10 ** _token.decimals();
        require(_tokenOracle.decimals() == 8, "PP-ERC20 : token oracle decimals must be 8");
        require(_nativeAssetOracle.decimals() == 8, "PP-ERC20 : native asset oracle decimals must be 8");
    }

    /// @notice Updates the price markup and price update threshold configurations.
    /// @param _priceMarkup The new price markup percentage (1e6 = 100%).
    function updateConfig(uint32 _priceMarkup) external onlyOwner {
        require(_priceMarkup <= 120e4, "PP-ERC20 : price markup too high");
        require(_priceMarkup >= 1e6, "PP-ERC20 : price markeup too low");
        priceMarkup = _priceMarkup;
        emit ConfigUpdated(_priceMarkup);
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address to, uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransfer(address(token), to, amount);
    }

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
        uint256 length = userOp.paymasterAndData.length - 52;
        require(length == 0 || userOp.paymasterAndData.length == 52, "PP-ERC20 : invalid paymaster data length");

        uint192 tokenPrice = getPrice();
        uint256 maxFeePerGas = UserOperationLib.unpackMaxFeePerGas(userOp);
        uint256 tokenAmount =
            (maxCost + (REFUND_POSTOP_COST) * maxFeePerGas) * priceMarkup * tokenPrice / (1e18 * priceDenominator);

        if (length == 52) {
            address guarantor = address(bytes20(userOp.paymasterAndData[52:72]));
            bytes memory signature = userOp.paymasterAndData[72:104];

            bytes32 paymasterHash = getHash(userOp);

            bool valid = SignatureChecker.isValidSignatureNow(guarantor, paymasterHash, signature);

            require(valid, "PP-ERC20 : invalid signature");
            SafeTransferLib.safeTransferFrom(address(token), guarantor, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, guarantor);
            validationResult = 0;
        } else {
            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender);
            validationResult = 0;
        }
    }

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param mode The post-operation mode (either successful or reverted).
    /// @param context The context containing the token amount and user sender address.
    /// @param actualGasCost The actual gas cost of the transaction.
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        internal
        override
    {
        uint256 prefundTokenAmount = uint256(bytes32(context[0:32]));
        uint192 tokenPrice = uint192(bytes24(context[32:56]));
        address sender = address(bytes20(context[56:76]));
        uint256 actualTokenNeeded = (actualGasCost + REFUND_POSTOP_COST * actualUserOpFeePerGas) * priceMarkup
            * tokenPrice / (1e18 * priceDenominator); // We use tx.gasprice here since we don't know the actual gas price used by the user

        // If the initially provided token amount is greater than the actual amount needed, refund the difference
        if (prefundTokenAmount > actualTokenNeeded) {
            if (context.length == 96) {
                address guarantor = address(bytes20(context[76:96]));

                // solhint-disable-next-line no-inline-assembly
                bool success = safeTransferFrom(address(token), sender, address(this), actualTokenNeeded);

                if (success) {
                    // If the token transfer is successful, transfer the held tokens back to the guarantor
                    SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount);
                } else {
                    // If the token transfer fails, the guarantor is deemed responsible for the token payment
                    SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount - actualTokenNeeded);
                }
            } else {
                SafeTransferLib.safeTransfer(address(token), sender, prefundTokenAmount - actualTokenNeeded);
            }
        } // If the token amount is not greater than the actual amount needed, no refund occurs

        emit UserOperationSponsored(sender, actualTokenNeeded, actualGasCost);
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for
    /// the current contract to manage.
    function safeTransferFrom(address _token, address _from, address _to, uint256 _amount)
        internal
        returns (bool success)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.

            mstore(0x60, _amount) // Store the `amount` argument.
            mstore(0x40, _to) // Store the `to` argument.
            mstore(0x2c, shl(96, _from)) // Store the `from` argument.
            // Store the function selector of `transferFrom(address,address,uint256)`.
            mstore(0x0c, 0x23b872dd000000000000000000000000)

            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(eq(mload(0x00), 1), iszero(returndatasize())),
                    call(gas(), _token, 0, 0x1c, 0x64, 0x00, 0x20)
                )
            ) {
                success := 0
                mstore(0x60, 0) // Restore the zero slot to zero.
                mstore(0x40, m) // Restore the free memory pointer.
                return(0, 0)
            }

            success := 1
            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    function getPrice() public view returns (uint192) {
        uint192 tokenPrice = fetchPrice(tokenOracle);
        uint192 nativeAsset = fetchPrice(nativeAssetOracle);
        uint192 price = nativeAsset * uint192(tokenDecimals) / tokenPrice;

        return price;
    }

    /// @notice Fetches the latest price from the given Oracle.
    /// @dev This function is used to get the latest price from the tokenOracle or nativeAssetOracle.
    /// @param _oracle The Oracle contract to fetch the price from.
    /// @return price The latest price fetched from the Oracle.
    function fetchPrice(IOracle _oracle) internal view returns (uint192 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();
        require(answer > 0, "PP-ERC20 : Chainlink price <= 0");
        // 2 days old price is considered stale since the price is updated every 24 hours
        require(updatedAt >= block.timestamp - 60 * 60 * 24 * 2, "PP-ERC20 : Incomplete round");
        require(answeredInRound >= roundId, "PP-ERC20 : Stale price");
        price = uint192(int192(answer));
    }

    /**
     * Hash the user operation data.
     * @param userOp - The user operation data.
     */
    function getHash(PackedUserOperation calldata userOp) public pure returns (bytes32) {
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
                address(this)
            )
        );
    }
}
