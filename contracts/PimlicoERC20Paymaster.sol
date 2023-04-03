// SPDX-License-Identifier: copyleft-next-0.3.1
pragma solidity ^0.8.0;

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./IOracle.sol";
import "hardhat/console.sol";

contract PimlicoERC20Paymaster is BasePaymaster {
    uint256 public constant denominator = 1e6;

    uint256 public constant POSTOP_COST = 40000; // TODO i think this is too much since same storage slot will be used on postOp

    IERC20 immutable token;

    IOracle public immutable oracle;

    uint8 immutable decimals;

    uint192 public prevPrice;

    uint32 public pricePremium;

    uint32 public updateThreshold;

    event PricePremiumChanged(uint32 pricePremium, uint32 updateThreshold);

    constructor(IERC20 _token, IEntryPoint _entryPoint, IOracle _oracle) BasePaymaster(_entryPoint) {
        token = _token;
        oracle = _oracle;
        pricePremium = 5e4; // 5%  1e6 = 100%
        updateThreshold = 25e3; // 2.5%  1e6 = 100%
        decimals = _oracle.decimals();
    }

    function setPricePremium(uint32 _pricePremium, uint32 _updateThreshold) external onlyOwner {
        require(_pricePremium <= 15e4, "price premium too high");
        require(_updateThreshold <= _pricePremium, "update threshold too high");
        pricePremium = _pricePremium;
        updateThreshold = _updateThreshold;
        emit PricePremiumChanged(_pricePremium, _updateThreshold);
    }

    function withdrawToken(address to, uint256 amount) external onlyOwner {
        token.transfer(to, amount);
    }

    function updatePrice() external { // this is erc20/eth price ratio
        (, int256 answer, , , ) = oracle.latestRoundData();
        prevPrice = uint192(int192(answer));
    }
    // 
    // prev + premium 
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund) internal override returns (bytes memory context, uint256 validationData) {
        uint256 gasPrev = gasleft();
        // uint256 userProvidedPrice = uint256(bytes32(userOp.paymasterAndData[20:52]));
        if(userOp.paymasterAndData.length == 20) {
            // no price provided, use prevPrice
            uint256 tokenAmount = requiredPreFund  * (denominator + pricePremium) / prevPrice;
            token.transferFrom(userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, userOp.sender);
        } else if(userOp.paymasterAndData.length == 21) {
            // no price provided, and no refund
            uint256 tokenAmount = requiredPreFund  * (denominator + pricePremium) / prevPrice;
            token.transferFrom(userOp.sender, address(this), tokenAmount);
            context = hex"00";
        } else if(userOp.paymasterAndData.length == 52) {
            // price provided
            uint256 minPrice = uint256(bytes32(userOp.paymasterAndData[20:52]));
            require(minPrice <= prevPrice * denominator / (denominator + pricePremium), "price too low"); // since our price oracle uses usdc/eth, we should use prevPrice * denominator / (denominator + pricePremium)
            uint256 tokenAmount = requiredPreFund  * (denominator + pricePremium) / prevPrice;
            token.transferFrom(userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, userOp.sender);
        } else if(userOp.paymasterAndData.length == 53) {
            // price provided, and no refund
            uint256 maxPrice = uint256(bytes32(userOp.paymasterAndData[20:52]));
            require(maxPrice >= prevPrice * (denominator - pricePremium) / denominator, "price too low");
            uint256 tokenAmount = requiredPreFund  * (denominator + pricePremium) / prevPrice;
            token.transferFrom(userOp.sender, address(this), tokenAmount);
            context = hex"00";
        } else {
            revert("invalid paymasterAndData length");
        }
        // no return here since validationData == 0 and we have context saved in memory
        validationData = 0;
        console.log("gas used on verification", gasPrev - gasleft());
    }

    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) internal override {
        uint256 gasPrev = gasleft();
        (, int256 price, , , ) = oracle.latestRoundData();
        // 2.5% price chage
        if(uint256(price) * denominator / prevPrice > denominator + updateThreshold || uint256(price) * denominator / prevPrice < denominator - updateThreshold){
            prevPrice = uint192(int192(price));
        }

        // refund tokens
        if(context.length == 52) {
            uint256 tokenAmount = uint256(bytes32(context[0:32]));
            address sender = address(bytes20(context[32:52]));
            // refund tokens based on actual gas cost
            uint256 actualTokenNeeded = actualGasCost * (denominator + pricePremium) / (prevPrice );
            if(tokenAmount > actualTokenNeeded) {
                token.transfer(sender, tokenAmount - actualTokenNeeded);
            } // else no refund
        }
        console.log("gas used on postOp", gasPrev - gasleft());
    }
}