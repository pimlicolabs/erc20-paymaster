// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/oracles/ManualOracle.sol";
import "src/factory/ERC20PaymasterFactory.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";


contract ManualOracleTest is Test {
    address oracleOperator;
    ERC20PaymasterFactory paymasterFactory;
    ManualOracle oracle;

    function setUp() external {
        oracleOperator = makeAddr("oracleOperator");
        paymasterFactory = new ERC20PaymasterFactory(oracleOperator);

        vm.startPrank(oracleOperator);
        address _oracle = paymasterFactory.deployManualOracle(
            "0x00",
            3e8,
            oracleOperator
        );
        vm.stopPrank();
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
