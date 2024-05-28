// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/oracles/FixedOracle.sol";
import "src/factory/PimlicoFactory.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";


contract FixedOracleTest is Test {
    FixedOracle oracle;
    PimlicoFactory pimlicoFactory;

    function setUp() external {
        pimlicoFactory = new PimlicoFactory();

        address _oracle = pimlicoFactory.deployFixedOracle(2e3);
        oracle = FixedOracle(_oracle);
    }

    function testPrice() external {
        (,int256 price,,,) = oracle.latestRoundData();

        assertEq(price, 2e3);
    }
}
