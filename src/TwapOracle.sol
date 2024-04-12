// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOracle} from "./interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OracleLibrary} from "@v3-periphery/contracts/libraries/OracleLibrary.sol";

contract TwapOracle is IOracle, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    error InvalidTwapAge();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev The Uniswap V3 pool address
    address public immutable pool;

    /// @dev The base token address (the one which price is being fetched)
    address public immutable baseToken;

    /// @dev The base token decimals
    uint8 public immutable baseTokenDecimals;

    /// @dev The quote token address (WETH or USD stable coin)
    address public immutable quoteToken;

    /// @dev The quote token decimals
    uint8 public immutable quoteTokenDecimals;

    /// @dev Default TWAP age, used to fetch the price
    uint32 public twapAge;

    uint32 public constant MINIMUM_TWAP_AGE = 1 minutes;
    uint32 public constant MAXIMUM_TWAP_AGE = 7 days;

    constructor(
        address _pool,
        address _baseToken,
        address _owner
    ) Ownable(_owner) {
        pool = _pool;
        baseToken = _baseToken;
    }

    function decimals() external override pure returns (uint8) {
        return 8;
    }

    function setTwapAge(
        uint32 _twapAge
    ) public onlyOwner() {
        if (_twapAge < MINIMUM_TWAP_AGE || _twapAge > MAXIMUM_TWAP_AGE) {
            revert InvalidTwapAge();
        }

        twapAge = _twapAge;
    }

    function latestRoundData() external override view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        uint256 _price = _fetchTwap();

        // Convert the price to 8 decimals
        uint256 price = _price * (10 ** 8) / (10 ** quoteTokenDecimals);

        return (0, int256(price), 0, block.timestamp - 1, 0);
    }

    function _fetchTwap() internal returns (uint256) {
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(pool, twapAge);

        // Base token amount is equal to 1
        uint256 baseAmount = 10 ** baseTokenDecimals;

        return OracleLibrary.getQuoteAmount(
            arithmeticMeanTick,
            baseAmount,
            baseToken,
            quoteToken
        );
    }
}