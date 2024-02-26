// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "src/PimlicoERC20Paymaster.sol";
import "src/test/TestERC20.sol";
import "src/test/TestOracle.sol";
import "src/test/TestCounter.sol";
import "@account-abstraction/contracts/core/EntryPoint.sol";
import "@account-abstraction/contracts/core/EntryPointSimulations.sol";
import "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "@account-abstraction/contracts/samples/SimpleAccountFactory.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

using ECDSA for bytes32;

import "./BytesLib.sol";

contract PimlicoERC20Paymaster18Test is Test {
    EntryPoint entryPoint;
    EntryPointSimulations entryPointSimulations;
    SimpleAccountFactory accountFactory;
    PimlicoERC20Paymaster paymaster;
    TestERC20 token;
    TestOracle tokenOracle;
    TestOracle nativeAssetOracle;
    TestCounter counter;

    address payable beneficiary;
    address paymasterOperator;
    address user;
    uint256 userKey;
    SimpleAccount account;

    function setUp() external {
        beneficiary = payable(makeAddr("beneficiary"));
        paymasterOperator = makeAddr("paymasterOperator");
        (user, userKey) = makeAddrAndKey("user");
        entryPoint = new EntryPoint();
        entryPointSimulations = new EntryPointSimulations();
        token = new TestERC20(18);
        tokenOracle = new TestOracle();
        tokenOracle.setPrice(100000000);
        nativeAssetOracle = new TestOracle();
        nativeAssetOracle.setPrice(189933000000);
        accountFactory = new SimpleAccountFactory(entryPoint);
        paymaster = new PimlicoERC20Paymaster(token, entryPoint, tokenOracle, nativeAssetOracle, paymasterOperator);
        account = accountFactory.createAccount(user, 0);
        counter = new TestCounter();
        vm.deal(paymasterOperator, 1000e18);
        vm.startPrank(paymasterOperator);
        entryPoint.depositTo{value: 100e18}(address(paymaster));
        paymaster.addStake{value: 100e18}(1);
        vm.stopPrank();
        vm.warp(1680509051);
    }

    function testDeploy() external {
        PimlicoERC20Paymaster testArtifact =
            new PimlicoERC20Paymaster(token, entryPoint, tokenOracle, nativeAssetOracle, paymasterOperator);
        assertEq(address(testArtifact.token()), address(token));
        assertEq(address(testArtifact.entryPoint()), address(entryPoint));
        assertEq(address(testArtifact.tokenOracle()), address(tokenOracle));
        assertEq(address(testArtifact.owner()), paymasterOperator);
    }

    function testOwnershipTransfer() external {
        vm.startPrank(paymasterOperator);
        assertEq(paymaster.owner(), paymasterOperator);
        paymaster.transferOwnership(beneficiary);
        assertEq(paymaster.owner(), beneficiary);
        vm.stopPrank();
    }

    function testUpdateConfigSuccess(uint32 _priceMarkup) external {
        _priceMarkup = uint32(bound(_priceMarkup, 1e6, 12e5)); // 100% - 120%
        vm.startPrank(paymasterOperator);
        paymaster.updateConfig(_priceMarkup);
        assertEq(paymaster.priceMarkup(), _priceMarkup);
        vm.stopPrank();
    }

    function testUpdateConfigFailMarkupTooLow(uint32 _priceMarkup) external {
        _priceMarkup = uint32(bound(_priceMarkup, 0, 1e6 - 1)); // 100% - 120%
        vm.startPrank(paymasterOperator);
        vm.expectRevert("PP-ERC20 : price markeup too low");
        paymaster.updateConfig(_priceMarkup);
        vm.stopPrank();
    }

    function testUpdateConfigFailMarkupTooHigh(uint32 _priceMarkup) external {
        _priceMarkup = uint32(bound(_priceMarkup, 12e5 + 1, type(uint32).max)); // 100% - 120%
        vm.startPrank(paymasterOperator);
        vm.expectRevert("PP-ERC20 : price markup too high");
        paymaster.updateConfig(_priceMarkup);
        vm.stopPrank();
    }

    function testWithdrawToken(uint256 _amount) external {
        vm.assume(_amount < token.totalSupply());
        token.sudoMint(address(paymaster), _amount);
        vm.startPrank(paymasterOperator);
        paymaster.withdrawToken(beneficiary, _amount);
        assertEq(token.balanceOf(address(paymaster)), 0);
        assertEq(token.balanceOf(beneficiary), _amount);
        vm.stopPrank();
    }

    function testWithdrawTokenFailNotOwner(uint256 _amount) external {
        vm.assume(_amount < token.totalSupply());
        token.sudoMint(address(paymaster), _amount);
        vm.startPrank(beneficiary);
        vm.expectRevert("Ownable: caller is not the owner");
        paymaster.withdrawToken(beneficiary, _amount);
        vm.stopPrank();
    }

    function testGetPrice(int192 _price) external {
        vm.assume(_price > 1e8);
        vm.assume(uint192(_price) < type(uint120).max);
        nativeAssetOracle.setPrice(_price);
        assertEq(uint256(paymaster.getPrice()), uint256(uint192(_price)) * 1e10);
    }

    // sanity check for everything works without paymaster
    function testCall() external {
        vm.deal(address(account), 1e18);
        (PackedUserOperation memory op,) =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        op.signature = signUserOp(op, userKey);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }

    function testERC20PaymasterRefund() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        (PackedUserOperation memory op,) =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(100000), uint128(100000));
        op.signature = signUserOp(op, userKey);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }

    function testERC20PaymasterRefundAndGuaredTokenFailTokenTooHigh() external {
        uint256 limit = 9 * 1897398591996964148 * tx.gasprice / 10000000000;
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        (PackedUserOperation memory op,) =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(100000), uint128(50000), limit);
        op.signature = signUserOp(op, userKey);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector, uint256(0), "AA33 reverted: PP-ERC20 : token amount too high"
            )
        );
        entryPoint.handleOps(ops, beneficiary);
    }

    function testERC20PaymasterFailWeirdCalldataLength() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        (PackedUserOperation memory op,) =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        op.paymasterAndData =
            abi.encodePacked(address(paymaster), bytes16(uint128(50000)), bytes16(uint128(50000)), hex"1234");
        op.signature = signUserOp(op, userKey);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        emit log_bytes32(bytes32(IEntryPoint.FailedOpWithRevert.selector));
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector, uint256(0), "AA33 reverted", "PP-ERC20 : invalid data length"
            )
        );
        entryPoint.handleOps(ops, beneficiary);
    }

    function testERC20PaymasterPostOpFailed() external {
        uint256 limit = 11 * 1897398591996964148 * tx.gasprice / 10000000000;
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        (PackedUserOperation memory op,) = fillUserOp(
            account,
            userKey,
            address(token),
            0,
            abi.encodeWithSelector(
                TestERC20.sudoTransfer.selector, paymaster, beneficiary, 1897398591996964148 * tx.gasprice / 10000000000
            )
        );
        op.paymasterAndData =
            abi.encodePacked(address(paymaster), bytes16(uint128(100000)), bytes16(uint128(50000)), limit);
        op.signature = signUserOp(op, userKey);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }

    function fillUserOp(SimpleAccount _sender, uint256 _key, address _to, uint256 _value, bytes memory _data)
        public
        view
        returns (PackedUserOperation memory op, uint256 prefund)
    {
        op.sender = address(_sender);
        op.nonce = entryPoint.getNonce(address(_sender), 0);
        op.callData = abi.encodeWithSelector(SimpleAccount.execute.selector, _to, _value, _data);
        op.accountGasLimits = bytes32(abi.encodePacked(bytes16(uint128(80000)), bytes16(uint128(50000))));
        op.preVerificationGas = 50000;
        op.gasFees = bytes32(abi.encodePacked(bytes16(uint128(100)), bytes16(uint128(1000000000))));
        op.signature = signUserOp(op, _key);
        return (op, 0);
        // (op, prefund) = simulateVerificationGas(entryPoint, op);

        // op.accountGasLimits =
        //     bytes32(abi.encodePacked(bytes16(uint128(80000)), bytes16(uint128(simulateCallGas(entryPoint, op)))));
        //op.signature = signUserOp(op, _name);
    }

    function signUserOp(PackedUserOperation memory op, uint256 _key) public view returns (bytes memory signature) {
        bytes32 hash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, MessageHashUtils.toEthSignedMessageHash(hash));
        signature = abi.encodePacked(r, s, v);
    }

    function simulateVerificationGas(EntryPoint _entrypoint, PackedUserOperation memory op)
        public
        returns (PackedUserOperation memory, uint256 preFund)
    {
        bool success;
        bytes memory ret;

        try _entrypoint.delegateAndRevert(
            address(entryPointSimulations),
            abi.encodeWithSelector(EntryPointSimulations.simulateValidation.selector, op)
        ) {
            revert("Should have failed");
            //bool _success, bytes memory _ret
        } catch (bytes memory reason) {
            (success, ret) = abi.decode(reason, (bool, bytes));
        }

        require(!success, "failed");
        bytes memory data = BytesLib.slice(ret, 4, ret.length - 4);
        (IEntryPoint.ReturnInfo memory retInfo,,,) = abi.decode(
            data, (IEntryPoint.ReturnInfo, IStakeManager.StakeInfo, IStakeManager.StakeInfo, IStakeManager.StakeInfo)
        );
        op.preVerificationGas = retInfo.preOpGas;
        op.accountGasLimits = bytes32(
            abi.encodePacked(bytes16(uint128(retInfo.preOpGas)), bytes16(bytes32(uint256(op.accountGasLimits)) << 128))
        );
        op.gasFees = bytes32(
            abi.encodePacked(bytes16(uint128(1)), bytes16(uint128(retInfo.prefund * 11 / (retInfo.preOpGas * 10))))
        );
        return (op, retInfo.prefund);
    }

    function simulateCallGas(EntryPoint _entrypoint, PackedUserOperation memory op) internal returns (uint256) {
        try this.calcGas(_entrypoint, op.sender, op.callData) {
            revert("Should have failed");
        } catch Error(string memory reason) {
            uint256 gas = abi.decode(bytes(reason), (uint256));
            return gas * 11 / 10;
        } catch {
            revert("Should have failed");
        }
    }

    // not used internally
    function calcGas(EntryPoint _entrypoint, address _to, bytes memory _data) external {
        vm.startPrank(address(_entrypoint));
        uint256 g = gasleft();
        (bool success,) = _to.call(_data);
        require(success);
        g = g - gasleft();
        bytes memory r = abi.encode(g);
        vm.stopPrank();
        require(false, string(r));
    }
}
