// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "src/ERC20Paymaster.sol";
import "src/test/TestERC20.sol";
import "src/test/TestOracle.sol";
import "src/test/TestCounter.sol";
import "@account-abstraction/contracts/core/EntryPoint.sol";
import "@account-abstraction/contracts/core/EntryPointSimulations.sol";
import "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "@account-abstraction/contracts/samples/SimpleAccountFactory.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {SymTest} from "halmos-cheatcodes/SymTest.sol";

using ECDSA for bytes32;

import "./BytesLib.sol";

contract ERC20PaymasterSymbolicTest is SymTest, Test {
    EntryPoint entryPoint;
    EntryPointSimulations entryPointSimulations;
    SimpleAccountFactory accountFactory;
    ERC20Paymaster paymaster;
    TestERC20 token;
    TestOracle tokenOracle;
    TestOracle nativeAssetOracle;
    TestCounter counter;

    address payable beneficiary;
    address paymasterOperator;
    address user;
    uint256 userKey;
    address guarantor;
    uint256 guarantorKey;
    SimpleAccount account;

    function setUp() external {
        beneficiary = payable(address(0x976EA74026E726554dB657fA54763abd0C3a0aa9));
        paymasterOperator = address(0x14dC79964da2C08b23698B3D3cc7Ca32193d9955);
        (user, userKey) = (
            address(0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f),
            uint256(bytes32(0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97))
        );
        (guarantor, guarantorKey) = (
            address(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720),
            uint256(bytes32(0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6))
        );

        entryPoint = new EntryPoint();
        entryPointSimulations = new EntryPointSimulations();
        token = new TestERC20(18);
        tokenOracle = new TestOracle();
        tokenOracle.setPrice(1_00000000);
        nativeAssetOracle = new TestOracle();
        nativeAssetOracle.setPrice(2000_00000000);
        accountFactory = new SimpleAccountFactory(entryPoint);
        paymaster =
            new ERC20Paymaster(token, entryPoint, tokenOracle, nativeAssetOracle, paymasterOperator, 120e4, 100e4);
        account = accountFactory.createAccount(user, 0);
        counter = new TestCounter();
        vm.deal(paymasterOperator, 1000e18);
        vm.startPrank(paymasterOperator);
        entryPoint.depositTo{value: 100e18}(address(paymaster));
        paymaster.addStake{value: 100e18}(1);
        vm.stopPrank();
        vm.warp(1680509051);
    }

    function check_updateMarkup_markupNotHigherThanLimit() public {
        uint32 initialPriceMarkup = uint32(svm.createUint(32, "initialPriceMarkup"));
        uint32 priceMarkup = uint32(svm.createUint(32, "priceMarkup"));
        uint32 priceMarkupLimit = uint32(svm.createUint(32, "priceMarkupLimit"));

        ERC20Paymaster testPaymaster = new ERC20Paymaster(
            token, entryPoint, tokenOracle, nativeAssetOracle, paymasterOperator, priceMarkupLimit, initialPriceMarkup
        );

        assert(testPaymaster.priceMarkup() >= 1e6);
        assert(testPaymaster.priceMarkupLimit() >= 1e6);
        assert(testPaymaster.priceMarkup() == initialPriceMarkup);
        assert(testPaymaster.priceMarkupLimit() == priceMarkupLimit);
        assert(testPaymaster.priceMarkup() <= testPaymaster.priceMarkupLimit());

        vm.prank(paymasterOperator);
        (bool success,) =
            address(testPaymaster).call(abi.encodeWithSelector(ERC20Paymaster.updateMarkup.selector, priceMarkup));
        if (!success) {
            if (priceMarkup >= testPaymaster.PRICE_DENOMINATOR()) {
                assert(priceMarkup > priceMarkupLimit);
            }
        } else {
            assert(priceMarkup <= priceMarkupLimit);
        }
    }

    function check_postOp_neverUnderpaid() public {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        PackedUserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        // op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(100000), uint128(100000));
        // op.signature = signUserOp(op, userKey);
        // submitUserOp(op);
    }

    function fillUserOp(SimpleAccount _sender, uint256 _key, address _to, uint256 _value, bytes memory _data)
        public
        view
        returns (PackedUserOperation memory op)
    {
        op.sender = address(_sender);
        op.nonce = entryPoint.getNonce(address(_sender), 0);
        op.callData = abi.encodeWithSelector(SimpleAccount.execute.selector, _to, _value, _data);
        op.accountGasLimits = bytes32(abi.encodePacked(bytes16(uint128(80000)), bytes16(uint128(50000))));
        op.preVerificationGas = 50000;
        op.gasFees = bytes32(abi.encodePacked(bytes16(uint128(100)), bytes16(uint128(1000000000))));
        op.signature = signUserOp(op, _key);
        return op;
    }

    function signUserOp(PackedUserOperation memory op, uint256 _key) public view returns (bytes memory signature) {
        bytes32 hash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, MessageHashUtils.toEthSignedMessageHash(hash));
        signature = abi.encodePacked(r, s, v);
    }

    function submitUserOp(PackedUserOperation memory op) public {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }
}
