// SPDX-License-Identifier: copyleft-next-0.3.1
pragma solidity ^0.8.0;

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "hardhat/console.sol";

contract ERC20Paymaster is BasePaymaster, EIP712 {
    IERC20 immutable token;

    uint256 public constant denominator = 1e18;

    uint256 public constant POSTOP_COST = 40000; // TODO i think this is too much since same storage slot will be used on postOp

    address public priceSigner;

    uint48 public emergencyPriceUntil;
    uint48 public emergencyPriceAt;
    uint160 public emergencyPriceValue;

    constructor(IERC20 _token, IEntryPoint _entryPoint, address _priceSigner) BasePaymaster(_entryPoint) EIP712("ERC20Paymaster", "0.0.1") {
        token = _token;
        priceSigner = _priceSigner;
    }

    function setPriceSigner(address _newPriceSigner) external onlyOwner {
        priceSigner = _newPriceSigner;
    }

    function withdrawToken(address to, uint256 amount) external onlyOwner {
        token.transfer(to, amount);
    }

    function emergencyPrice(uint48 _duration, uint160 price) external onlyOwner {
        emergencyPriceUntil = uint48(block.timestamp) + _duration;
        emergencyPriceAt = uint48(block.timestamp);
        emergencyPriceValue = price;
    }

    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund) internal override returns (bytes memory context, uint256 validationData) {
        uint256 maxPayment = uint256(bytes32(userOp.paymasterAndData[20:52]));
        (bool signed, uint48 validUntil, uint48 signedAt, uint256 signedPrice) = _getPrice(userOp.paymasterAndData);
        uint256 gasPrice = UserOperationLib.gasPrice(userOp);
        uint256 cost = (requiredPreFund + POSTOP_COST * gasPrice) * signedPrice / denominator;
        require(maxPayment >= cost, "maxPayment too low");
        token.transferFrom(userOp.sender, address(this), cost);
        return (abi.encode(userOp.sender, cost, gasPrice, signedPrice), _packValidationData(!signed, validUntil, signedAt));
    }

    function _getPrice(bytes calldata paymasterAndData) internal view returns (bool, uint48, uint48, uint256) {
        uint160 signedPrice = uint160(bytes20(paymasterAndData[52:72]));
        uint48 signedAt = uint48(bytes6(paymasterAndData[72:78]));
        uint48 validUntil = uint48(bytes6(paymasterAndData[78:84]));
        if(emergencyPriceUntil > signedAt) return (true, emergencyPriceUntil, emergencyPriceAt, emergencyPriceValue);
        bytes calldata signature = paymasterAndData[84:];
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            keccak256("PaymasterPrice(uint160 price,uint48 signedAt,uint48 validUntil)"),
                signedPrice,
                signedAt,
                validUntil
        )));
        address signer = ECDSA.recover(digest, signature);
        return (signer == priceSigner, validUntil, signedAt, signedPrice);
    }

    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        if(mode == PostOpMode.postOpReverted) return; // no refund
        (address sender, uint256 paid, uint256 gasPrice, uint256 ethPrice) = abi.decode(context, (address, uint256, uint256, uint256));
        uint256 balance = token.balanceOf(address(this));
        uint256 actualTokenUsed = (actualGasCost + POSTOP_COST * gasPrice) * ethPrice / denominator;
        uint256 refundAmount = paid > actualTokenUsed ? paid - actualTokenUsed : 0;
        token.transfer(
            sender,
            refundAmount > balance ? balance : refundAmount // refund only what we have
        );
    }
}