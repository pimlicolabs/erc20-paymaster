// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface ITestUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos)
        external
        view
    returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    function token0() external view returns (address);

    function token1() external view returns (address);
}