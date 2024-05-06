// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/oracles/ManualOracle.sol";
import {ForkNetwork, Fork} from "./../utils/Fork.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


contract ManualOracleTest is Test, Fork {
    ManualOracle oracle;

    function setUp() onFork(ForkNetwork.MAINNET, 19641719) external {
        oracle = new ManualOracle(
            3e8
        );
    }

    function testSetPrice() external {
        (,int256 price,,,) = oracle.latestRoundData();

        assertEq(price, 3e8);
        
        // Update the price
        oracle.setPrice(4e8);

        (,price,,,) = oracle.latestRoundData();
        assertEq(price, 4e8);
    }
}
