// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20PaymasterV06 as ERC20Paymaster} from "src/ERC20PaymasterV06.sol";
import "src/base/BaseERC20Paymaster.sol";
import {ERC20PaymasterFactory} from "src/factory/ERC20PaymasterFactory.sol";
import {PaymasterVersion} from "src/factory/PaymasterFactory.sol";
import "./utils/TestERC20.sol";
import "./utils/TestOracle.sol";
import "./utils/TestCounter.sol";
import "./utils/BytesLib.sol";

import {EntryPoint} from "src/account-abstraction/v06/core/EntryPoint.sol";
import {SimpleAccountFactory, SimpleAccount} from "src/account-abstraction/v06/samples/SimpleAccountFactory.sol";
import {UserOperationLib, UserOperation} from "@account-abstraction-v6/contracts/interfaces/UserOperation.sol";
import {ECDSA} from "@openzeppelin-v4.8.0/contracts/utils/cryptography/ECDSA.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";


using ECDSA for bytes32;

contract ERC20Paymaster18Test is Test {
    EntryPoint entryPoint;
    ERC20PaymasterFactory paymasterFactory;
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
        beneficiary = payable(makeAddr("beneficiary"));
        paymasterOperator = makeAddr("paymasterOperator");
        (user, userKey) = makeAddrAndKey("user");
        (guarantor, guarantorKey) = makeAddrAndKey("guarantor");
        entryPoint = new EntryPoint();
        token = new TestERC20(18);
        tokenOracle = new TestOracle();
        tokenOracle.setPrice(1_00000000);
        nativeAssetOracle = new TestOracle();
        nativeAssetOracle.setPrice(2000_00000000);
        accountFactory = new SimpleAccountFactory(entryPoint);

        paymasterFactory = new ERC20PaymasterFactory(paymasterOperator);

        vm.startPrank(paymasterOperator);
        address _paymaster = paymasterFactory.deployPaymaster(
            "0x00",
            PaymasterVersion.V06,
            token,
            address(entryPoint),
            tokenOracle,
            nativeAssetOracle,
            2 * 24 * 60 * 60,
            paymasterOperator,
            120e4,
            100e4,
            30000,
            50000
        );
        vm.stopPrank();
        paymaster = ERC20Paymaster(_paymaster);

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
        assertEq(address(paymaster.token()), address(token));
        assertEq(address(paymaster.entryPoint()), address(entryPoint));
        assertEq(address(paymaster.tokenOracle()), address(tokenOracle));
        assertEq(address(paymaster.owner()), paymasterOperator);
    }

    function testOwnershipTransfer() external {
        vm.startPrank(paymasterOperator);
        assertEq(paymaster.owner(), paymasterOperator);
        paymaster.transferOwnership(beneficiary);
        assertEq(paymaster.owner(), beneficiary);
        vm.stopPrank();
    }

    function testUpdateMarkupSuccess(uint32 _priceMarkup) external {
        _priceMarkup = uint32(bound(_priceMarkup, 1e6, 12e5)); // 100% - 120%
        vm.startPrank(paymasterOperator);
        paymaster.updateMarkup(_priceMarkup);
        assertEq(paymaster.priceMarkup(), _priceMarkup);
        vm.stopPrank();
    }

    function testUpdateMarkupFailMarkupTooLow(uint32 _priceMarkup) external {
        _priceMarkup = uint32(bound(_priceMarkup, 0, 1e6 - 1)); // 100% - 120%
        vm.startPrank(paymasterOperator);
        vm.expectRevert(BaseERC20Paymaster.PriceMarkupTooLow.selector);
        paymaster.updateMarkup(_priceMarkup);
        vm.stopPrank();
    }

    function testUpdateMarkupFailMarkupTooHigh(uint32 _priceMarkup) external {
        _priceMarkup = uint32(bound(_priceMarkup, 12e5 + 1, type(uint32).max)); // 100% - 120%
        vm.startPrank(paymasterOperator);
        vm.expectRevert(BaseERC20Paymaster.PriceMarkupTooHigh.selector);
        paymaster.updateMarkup(_priceMarkup);
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
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", beneficiary));
        paymaster.withdrawToken(beneficiary, _amount);
        vm.stopPrank();
    }

    function testGetPrice(int192 _price) external {
        vm.assume(_price > 1e8);
        vm.assume(uint192(_price) < type(uint120).max);
        nativeAssetOracle.setPrice(_price);
        assertEq(uint256(paymaster.getPrice()), uint256(uint192(_price)) * 1e10);
    }

    function testGetPriceFailZeroPrice() external {
        nativeAssetOracle.setPrice(0);
        vm.expectRevert(BaseERC20Paymaster.OraclePriceNotPositive.selector);
        paymaster.getPrice();
    }

    function testGetPriceFailStalePrice() external {
        nativeAssetOracle.setUpdatedAtDelay(3 * 24 * 60 * 60);
        vm.expectRevert(BaseERC20Paymaster.OraclePriceStale.selector);
        paymaster.getPrice();
    }

    // sanity check for everything works without paymaster
    function testCall() external {
        vm.deal(address(account), 1e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        op.signature = signUserOp(op, userKey);
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }

    function getRequiredPrefund(UserOperation memory op) internal pure returns (uint256 requiredPrefund) {
        uint256 mul = op.paymasterAndData.length > 0 ? 3 : 1;

        uint256 verificationGasLimit = op.verificationGasLimit;
        uint256 callGasLimit = op.callGasLimit;
        uint256 preVerificationGas = op.preVerificationGas;
        uint256 maxFeePerGas = uint256(uint128(uint256(op.maxFeePerGas)));

        uint256 requiredGas =
            verificationGasLimit + callGasLimit + preVerificationGas;
        requiredPrefund = requiredGas * maxFeePerGas * mul;
    }

    function testERC20PaymasterMode0Success() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        op.paymasterAndData = abi.encodePacked(address(paymaster));
        op.signature = signUserOp(op, userKey);
        submitUserOp(op);
    }

    function testERC20PaymasterMode1Success() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 maxFeePerGas = uint256(uint128(uint256(op.maxFeePerGas)));
        uint256 limit = (getRequiredPrefund(op) + (paymaster.refundPostOpCost() * maxFeePerGas))
            * paymaster.priceMarkup() * paymaster.getPrice() / (1e18 * paymaster.PRICE_DENOMINATOR());
        
        op.paymasterAndData = abi.encodePacked(address(paymaster), hex"01", limit);
        op.signature = signUserOp(op, userKey);
        submitUserOp(op);
    }

    function testERC20PaymasterMode1FailedPaymasterDataLengthInvalid() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 maxFeePerGas = uint256(uint128(uint256(op.maxFeePerGas)));
        uint256 limit = (getRequiredPrefund(op) + (paymaster.refundPostOpCost() * maxFeePerGas))
            * paymaster.priceMarkup() * paymaster.getPrice() / (1e18 * paymaster.PRICE_DENOMINATOR());

        op.paymasterAndData =
            abi.encodePacked(address(paymaster), hex"01", limit, hex"69");
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function testERC20PaymasterMode1FailedTokenLimitExceeded() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 maxFeePerGas = uint256(uint128(uint256(op.maxFeePerGas)));
        uint256 limit = ((getRequiredPrefund(op) + (paymaster.refundPostOpCost() * maxFeePerGas))
            * paymaster.priceMarkup() * paymaster.getPrice() / (1e18 * paymaster.PRICE_DENOMINATOR())) / 4;

        op.paymasterAndData = abi.encodePacked(address(paymaster), hex"01", limit);
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function testERC20PaymasterMode1FailedTokenLimitZero() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 limit = 0;

        op.paymasterAndData = abi.encodePacked(address(paymaster), hex"01", limit);
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function testERC20PaymasterMode2Success() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster));

        uint48 validUntil = 0;
        uint48 validAfter = 0;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guarantorKey, paymaster.getHash(op, validUntil, validAfter, type(uint256).max));
        bytes memory guarantorSig = abi.encodePacked(r, s, v);

        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            hex"02",
            guarantor,
            validUntil,
            validAfter,
            guarantorSig
        );
        op.signature = signUserOp(op, userKey);
        submitUserOp(op);

        assertEq(token.balanceOf(guarantor), 1000e18);
        assertLt(token.balanceOf(address(account)), 1000e18);
    }

    function testERC20PaymasterMode2FailedInvalidSignature() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster));

        uint48 validUntil = 0;
        uint48 validAfter = 0;

        (, bytes32 r, bytes32 s) = vm.sign(guarantorKey, paymaster.getHash(op, validUntil, validAfter, 0));
        bytes memory guarantorSig = abi.encodePacked(r, s, uint8(69)); // invalid sig

        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            hex"02",
            guarantor,
            validUntil,
            validAfter,
            guarantorSig
        );
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(IEntryPoint.FailedOp.selector,
            uint256(0),
            "AA34 signature error"
        ));
        submitUserOp(op);
    }

    function testERC20PaymasterMode2FailedInvalidPaymasterDataLength() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster), hex"02", hex"69");
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function testERC20PaymasterMode2SuccessGuarantorPays() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));

        op.paymasterAndData = abi.encodePacked(address(paymaster));

        uint48 validUntil = 0;
        uint48 validAfter = 0;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guarantorKey, paymaster.getHash(op, validUntil, validAfter, type(uint256).max));
        bytes memory guarantorSig = abi.encodePacked(r, s, v);

        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            hex"02",
            guarantor,
            validUntil,
            validAfter,
            guarantorSig
        );
        op.signature = signUserOp(op, userKey);
        submitUserOp(op);

        assertLt(token.balanceOf(guarantor), 1000e18);
        assertEq(token.balanceOf(address(account)), 1000e18);
    }

    function testERC20PaymasterMode3Success() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 maxFeePerGas = uint256(uint128(uint256(op.maxFeePerGas)));
        uint256 limit = (getRequiredPrefund(op) + (paymaster.refundPostOpCostWithGuarantor() * maxFeePerGas))
            * paymaster.priceMarkup() * paymaster.getPrice() / (1e18 * paymaster.PRICE_DENOMINATOR());

        uint48 validUntil = 0;
        uint48 validAfter = 0;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guarantorKey, paymaster.getHash(op, validUntil, validAfter, limit));
        bytes memory guarantorSig = abi.encodePacked(r, s, v);

        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            hex"03",
            limit,
            guarantor,
            validUntil,
            validAfter,
            guarantorSig
        );
        op.signature = signUserOp(op, userKey);
        submitUserOp(op);
    }

    function testERC20PaymasterMode3FailedPaymasterDataLengthInvalid() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster), hex"03", hex"69");
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function testERC20PaymasterMode3FailedTokenLimitExceeded() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 maxFeePerGas = uint256(uint128(uint256(op.maxFeePerGas)));
        uint256 limit = ((getRequiredPrefund(op) + (paymaster.refundPostOpCost() * maxFeePerGas))
            * paymaster.priceMarkup() * paymaster.getPrice() / (1e18 * paymaster.PRICE_DENOMINATOR())) / 4;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guarantorKey, paymaster.getHash(op, 0, 0, limit));
        bytes memory guarantorSig = abi.encodePacked(r, s, v);

        op.paymasterAndData = abi.encodePacked(
            address(paymaster), hex"03", limit, guarantor, guarantorSig
        );
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function testERC20PaymasterMode3FailedTokenLimitZero() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 limit = 0;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(guarantorKey, paymaster.getHash(op, 0, 0, limit));
        bytes memory guarantorSig = abi.encodePacked(r, s, v);

        op.paymasterAndData = abi.encodePacked(
            address(paymaster), hex"03", limit, guarantor, guarantorSig
        );
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function testERC20PaymasterMode3FailedInvalidSignature() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1000e6); // 1000 usdc;
        token.sudoMint(address(guarantor), 1000e18); // 1000 usdc;
        token.sudoApprove(address(guarantor), address(paymaster), 1000e18);
        UserOperation memory op = fillUserOp(
            account, userKey, address(token), 0, abi.encodeWithSelector(ERC20.approve.selector, paymaster, 1000e18)
        );

        op.paymasterAndData = abi.encodePacked(address(paymaster));
        uint256 maxFeePerGas = uint256(uint128(uint256(op.maxFeePerGas)));
        uint256 limit = (getRequiredPrefund(op) + (paymaster.refundPostOpCostWithGuarantor() * maxFeePerGas))
            * paymaster.priceMarkup() * paymaster.getPrice() / (1e18 * paymaster.PRICE_DENOMINATOR());

        uint48 validUntil = uint48(0);
        uint48 validAfter = uint48(0);

        (, bytes32 r, bytes32 s) = vm.sign(guarantorKey, paymaster.getHash(op, validUntil, validAfter, limit));
        bytes memory guarantorSig = abi.encodePacked(r, s, uint8(69));

        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            hex"03",
            limit,
            guarantor,
            validUntil,
            validAfter,
            guarantorSig
        );
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(IEntryPoint.FailedOp.selector,
            uint256(0),
            "AA34 signature error"
        ));
        submitUserOp(op);
    }

    function testERC20PaymasterFailInvalidMode() external {
        vm.deal(address(account), 1e18);
        token.sudoMint(address(account), 1000e18); // 1000 usdc;
        token.sudoMint(address(paymaster), 1); // 1000 usdc;
        token.sudoApprove(address(account), address(paymaster), 1000e18);
        UserOperation memory op =
            fillUserOp(account, userKey, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector));
        op.paymasterAndData =
            abi.encodePacked(address(paymaster), hex"04");
        op.signature = signUserOp(op, userKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA33 reverted (or OOG)"
            )
        );
        submitUserOp(op);
    }

    function fillUserOp(SimpleAccount _sender, uint256 _key, address _to, uint256 _value, bytes memory _data)
        public
        view
        returns (UserOperation memory op)
    {
        op.sender = address(_sender);
        op.nonce = entryPoint.getNonce(address(_sender), 0);
        op.callData = abi.encodeWithSelector(SimpleAccount.execute.selector, _to, _value, _data);
        op.callGasLimit = 50000;
        op.verificationGasLimit = 80000;
        op.preVerificationGas = 50000;
        op.maxFeePerGas = 1000000000;
        op.maxPriorityFeePerGas = 100;
        op.signature = signUserOp(op, _key);
        return op;
    }

    function signUserOp(UserOperation memory op, uint256 _key) public view returns (bytes memory signature) {
        bytes32 hash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, hash.toEthSignedMessageHash());
        signature = abi.encodePacked(r, s, v);
    }

    function submitUserOp(UserOperation memory op) public {
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }
}