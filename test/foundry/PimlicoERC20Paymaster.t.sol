// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "contracts/PimlicoERC20Paymaster.sol";
import "contracts/TestERC20.sol";
import "contracts/TestOracle.sol";
import "@account-abstraction/contracts/core/EntryPoint.sol";
import "@account-abstraction/contracts/samples/SimpleAccountFactory.sol";
import "forge-std/Test.sol";

contract PimlicoERC20PaymasterTest is Test {
    EntryPoint entryPoint;
    SimpleAccountFactory accountFactory;
    PimlicoERC20Paymaster paymaster;
    TestERC20 token;
    TestOracle oracle;

    address beneficiary;
    address paymasterOperator;
    address user;
    SimpleAccount account;

    function setUp() external {
        beneficiary = makeAddr("beneficiary");
        paymasterOperator = makeAddr("paymasterOperator");
        user = makeAddr("user");
        entryPoint = new EntryPoint();
        accountFactory = new SimpleAccountFactory(entryPoint);
        paymaster = new PimlicoERC20Paymaster(
            token,
            entryPoint,
            oracle,
            paymasterOperator
        );
    }

    function testDeploy() external {
        PimlicoERC20Paymaster testArtifact = new PimlicoERC20Paymaster(
            token,
            entryPoint,
            oracle,
            paymasterOperator
        );
        assertEq(address(testArtifact.token()), address(token));
        assertEq(address(testArtifact.entryPoint()), address(entryPoint));
        assertEq(address(testArtifact.oracle()), address(oracle));
        assertEq(address(testArtifact.owner()), paymasterOperator);
    }

    function testOwnershipTransfer() external {
        vm.startPrank(paymasterOperator);
        assertEq(paymaster.owner(), paymasterOperator);
        paymaster.transferOwnership(beneficiary);
        assertEq(paymaster.owner(), beneficiary);
        vm.stopPrank();
    }
}