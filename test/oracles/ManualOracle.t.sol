// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/oracles/ManualOracle.sol";
import "src/factory/PimlicoFactory.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";


contract ManualOracleTest is Test {
    address oracleOperator;
    PimlicoFactory pimlicoFactory;
    ManualOracle oracle;

    function setUp() external {
        oracleOperator = makeAddr("oracleOperator");
        pimlicoFactory = new PimlicoFactory();

        address _oracle = pimlicoFactory.deployManualOracle(
            "test-manual-oracle",
            3e8,
            oracleOperator
        );
        oracle = ManualOracle(_oracle);
    }

    function testSetPrice() external {
        (,int256 price,,,) = oracle.latestRoundData();

        assertEq(price, 3e8);
        
        // Update the price
        vm.startPrank(oracleOperator);
        oracle.setPrice(4e8);
        vm.stopPrank();

        (,price,,,) = oracle.latestRoundData();
        assertEq(price, 4e8);
    }
}
