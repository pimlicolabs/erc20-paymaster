// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/oracles/FixedOracle.sol";
import {ForkNetwork, Fork} from "./../utils/Fork.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


contract FixedOracleTest is Test, Fork {
    FixedOracle oracle;

    function setUp() onFork(ForkNetwork.MAINNET, 19641719) external {
        oracle = new FixedOracle();
    }

    function testPrice() external {
        (,int256 price,,,) = oracle.latestRoundData();

        assertEq(price, 1e8);
    }
}
