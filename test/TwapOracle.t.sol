// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/oracles/TwapOracle.sol";
import {ForkNetwork, Fork} from "./utils/Fork.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


contract TwapOracleTest is Test, Fork {
    address owner;

    function setUp() onFork(ForkNetwork.MAINNET, 19641719) external {}

    function testWbtcUsdt() external {
        IUniswapV3Pool pool = IUniswapV3Pool(0x9Db9e0e53058C89e5B94e29621a205198648425B);

        TwapOracle oracle = new TwapOracle(
            address(pool),
            1 hours,
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599 // wbtc
        );

        (,int256 answer,,uint256 updatedAt,) = oracle.latestRoundData();

        assertEq(updatedAt, block.timestamp - 1);
        assertApproxEqAbs(answer / 10**8, 60000, 10000, "Wrong BTC/USDT price");
    }

    function testUsdcWeth() external {
        IUniswapV3Pool pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);

        TwapOracle oracle = new TwapOracle(
            address(pool),
            1 hours,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 // usdc
        );

        (,int256 answer,,,) = oracle.latestRoundData();
 
        assertApproxEqAbs(answer, 30000, 5000, "Wrong USDC/WETH price");
    }
}