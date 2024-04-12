// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/TwapOracle.sol";
import "./utils/TestUniswapV3Pool.sol";
import "./utils/TestERC20.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract TwapOracleTest is Test {
    address owner;

    TestERC20 baseToken;
    TestERC20 quoteToken;
    TestUniswapV3Pool pool;
    TwapOracle oracle;

    function setUp() external {
        owner = makeAddr("owner");

        baseToken = new TestERC20(18);
        quoteToken = new TestERC20(18);

        // 0xc9034c3e7f58003e6ae0c8438e7c8f4598d5acaa
        // weth/degen
        // base, block 13065501
        pool = new TestUniswapV3Pool(
            address(baseToken),
            address(quoteToken),
            [
                int56(1187440464978),
                int56(1187856501264)
            ],
            [
                uint160(6047764207030777331073),
                uint160(6048299056841155705324)
            ]
        );

        oracle = new TwapOracle(
            address(pool),
            1 hours,
            address(baseToken),
            owner
        );
    }

    function testLatestRoundData() external {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(answeredInRound, 0);
        assertEq(updatedAt, block.timestamp - 1);

        console.log("answer: %d", uint256(answer));
    }
}