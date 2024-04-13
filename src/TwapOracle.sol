// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOracle} from "./interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OracleLibrary} from "@v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3PoolImmutables} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";


import "forge-std/console.sol";

contract TwapOracle is IOracle, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Invalid TWAP age, either too low or too high
    error InvalidTwapAge();

    /// @dev Pool doesn't contain the base token
    error InvalidTokenOrPool();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    event UpdatedTwapAge(uint32 twapAge);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Fixed price mode, a price is always equal to 1e8
    /// @dev Used for the case when there's token/native coin
    /// @dev but no token/usdc pool available
    /// @dev The `nativeAssetOracle` would be a TWAP oracle for token/native coin pool
    /// @dev The `tokenOracle` would TWAP oracle in fixed price mode
    bool public immutable fixedPriceMode;

    /// @dev The Uniswap V3 pool address
    address public immutable pool;

    /// @dev The base token address (the one which price is being fetched)
    address public immutable baseToken;

    /// @dev The base token decimals
    uint256 public immutable baseTokenDecimals;

    /// @dev The quote token address (WETH or USD stable coin)
    address public immutable quoteToken;

    /// @dev The quote token decimals
    uint256 public immutable quoteTokenDecimals;

    /// @dev Default TWAP age, used to fetch the price
    uint32 public twapAge;

    uint32 public constant MINIMUM_TWAP_AGE = 1 minutes;
    uint32 public constant MAXIMUM_TWAP_AGE = 7 days;

    uint256 public constant ORACLE_DECIMALS = 1e8;

    constructor(
        bool _fixedPriceMode,
        address _pool,
        uint32 _twapAge,
        address _baseToken,
        address _owner
    ) Ownable(_owner) {
        fixedPriceMode = _fixedPriceMode;
        pool = _pool;
        _setTwapAge(_twapAge);

        address token0 = IUniswapV3PoolImmutables(_pool).token0();
        address token1 = IUniswapV3PoolImmutables(_pool).token1();

        if (_baseToken != token0 && _baseToken != token1) revert InvalidTokenOrPool();

        baseToken = _baseToken;
        baseTokenDecimals = 10 ** IERC20Metadata(baseToken).decimals();

        quoteToken = token0 == baseToken ? token1 : token0;
        quoteTokenDecimals = 10 ** IERC20Metadata(quoteToken).decimals();
    }

    function decimals() external override pure returns (uint8) {
        return 8;
    }

    function setTwapAge(
        uint32 _twapAge
    ) public onlyOwner() {
        _setTwapAge(_twapAge);
    }

    function latestRoundData() external override view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        if (fixedPriceMode) return _buildLatestRoundData(ORACLE_DECIMALS);

        uint256 _price = _fetchTwap();

        // Normalize the price to the oracle decimals
        uint256 price = _price * ORACLE_DECIMALS / quoteTokenDecimals;

        return _buildLatestRoundData(price);
    }

    function _setTwapAge(uint32 _twapAge) internal {
        if (_twapAge < MINIMUM_TWAP_AGE || _twapAge > MAXIMUM_TWAP_AGE) revert InvalidTwapAge();

        twapAge = _twapAge;

        emit UpdatedTwapAge(_twapAge);
    }

    function _buildLatestRoundData(uint256 price) internal view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (0, int256(price), 0, block.timestamp - 1, 0);
    }

    function _fetchTwap() internal view returns (uint256) {
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(pool, twapAge);

        return OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(baseTokenDecimals), // Base token amount is equal to 1 token
            baseToken,
            quoteToken
        );
    }
}