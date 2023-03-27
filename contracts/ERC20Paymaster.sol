// SPDX-License-Identifier: copyleft-next-0.3.1
pragma solidity ^0.8.0;

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract ERC20Paymaster is BasePaymaster {
    IERC20 immutable token;

    uint256 public constant denominator = 1e18;

    uint256 public constant POSTOP_COST = 40000; // TODO i think this is too much

    uint256 public priceOfEth;

    uint48 public lastUpdatedAt;

    uint48 public safeRange;

    constructor(IERC20 _token, IEntryPoint _entryPoint) BasePaymaster(_entryPoint) {
        token = _token;
        safeRange = 10 minutes;
    }

    /// @notice set the safe range for the price of ETH
    function setSafeRange(uint48 _safeRange) external onlyOwner {
        safeRange = _safeRange;
    }

    function setPriceOfEth(uint256 _price) external onlyOwner {
        priceOfEth = _price;
        lastUpdatedAt = uint48(block.timestamp);
    }

    function withdrawToken(address to, uint256 amount) external onlyOwner {
        token.transfer(to, amount);
    }

    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund) internal override returns (bytes memory context, uint256 validationData) {
        uint256 ethPrice = priceOfEth;
        uint48 validUntil = lastUpdatedAt + safeRange;
        uint256 gasPrice = UserOperationLib.gasPrice(userOp);
        uint256 cost = (requiredPreFund + POSTOP_COST * gasPrice) * ethPrice / denominator;
        uint256 maxPayment = uint256(bytes32(userOp.paymasterAndData[20:52]));
        require(maxPayment >= cost, "maxPayment too low");
        token.transferFrom(userOp.sender, address(this), cost);
        return (abi.encode(userOp.sender, cost, gasPrice, ethPrice), _packValidationData(false, validUntil, uint48(0)));
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