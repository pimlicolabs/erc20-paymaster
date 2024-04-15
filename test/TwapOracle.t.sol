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

        // Approx 60000$ per btc
        assertApproxEqAbs(
            answer / 10**8,
            60000,
            10000,
            "Wrong BTC/USDT price"
        );

        // Compare with Chainlink value
        IOracle chainLinkOracle = IOracle(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

        (,int256 _answer, , ,) = chainLinkOracle.latestRoundData();

        assertApproxEqAbs(
            answer / 10**8,
            _answer / 10**8,
            5000,
            "Chainlink and TWAP prices are too different"
        );
    }

    function testUsdcWeth() external {
        IUniswapV3Pool pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);

        TwapOracle oracle = new TwapOracle(
            address(pool),
            1 hours,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 // weth
        );

        (,int256 answer,,,) = oracle.latestRoundData();

        // Approx 3000$ per eth
        assertApproxEqAbs(
            answer / 10**8,
            3000,
            500,
            "Wrong USDC/WETH price"
        );

        // Compare with Chainlink value
        IOracle chainLinkOracle = IOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

        (,int256 _answer, , ,) = chainLinkOracle.latestRoundData();

        assertApproxEqAbs(
            answer / 10**8,
            _answer / 10**8,
            500,
            "Chainlink and TWAP prices are too different"
        );
    }
}