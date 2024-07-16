// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/oracles/FixedOracle.sol";
import "src/factory/ERC20PaymasterFactory.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";


contract FixedOracleTest is Test {
    address oracleOperator;
    FixedOracle oracle;
    ERC20PaymasterFactory paymasterFactory;

    function setUp() external {
        oracleOperator = makeAddr("oracleOperator");
        paymasterFactory = new ERC20PaymasterFactory(oracleOperator);

        vm.startPrank(oracleOperator);
        address _oracle = paymasterFactory.deployFixedOracle("0x00", 2e3);
        vm.stopPrank();
        oracle = FixedOracle(_oracle);
    }

    function testPrice() external {
        (,int256 price,,,) = oracle.latestRoundData();

        assertEq(price, 2e3);
    }
}
