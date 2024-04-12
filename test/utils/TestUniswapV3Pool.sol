pragma solidity ^0.8.0;

import {
    ITestUniswapV3Pool
} from "./../interfaces/ITestUniswapV3Pool.sol";

contract TestUniswapV3Pool is ITestUniswapV3Pool {
    address immutable _token0;
    address immutable _token1;
    int56[2] _tickCumulatives;
    uint160[2] _secondsPerLiquidityCumulativeX128s;

    constructor(
        address __token0,
        address __token1,
        int56[2] memory __tickCumulatives,
        uint160[2] memory __secondsPerLiquidityCumulativeX128s
    ) {
        _token0 = __token0;
        _token1 = __token1;
        _tickCumulatives = __tickCumulatives;
        _secondsPerLiquidityCumulativeX128s = __secondsPerLiquidityCumulativeX128s;
    }

    function token0() external override view returns (address) {
        return _token0;
    }

    function token1() external override view returns (address) {
        return _token1;
    }

    function observe(uint32[] calldata)
        external
        override
        view
    returns (
        int56[] memory,
        uint160[] memory
    ) {
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = _tickCumulatives[0];
        tickCumulatives[1] = _tickCumulatives[1];

        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);
        secondsPerLiquidityCumulativeX128s[0] = _secondsPerLiquidityCumulativeX128s[0];
        secondsPerLiquidityCumulativeX128s[1] = _secondsPerLiquidityCumulativeX128s[1];

        return (tickCumulatives, secondsPerLiquidityCumulativeX128s);
    }
}