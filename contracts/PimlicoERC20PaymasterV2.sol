// SPDX-License-Identifier: copyleft-next-0.3.1
pragma solidity ^0.8.0;

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./IOracle.sol";

contract PimlicoERC20PaymasterV2 is BasePaymaster {
    IERC20 immutable token;

    uint256 public constant denominator = 1e18;

    uint256 public constant POSTOP_COST = 40000; // TODO i think this is too much since same storage slot will be used on postOp

    uint256 public prevPrice;

    IOracle public oracle;

    constructor(IERC20 _token, IEntryPoint _entryPoint, IOracle _oracle) BasePaymaster(_entryPoint) {
        token = _token;
        oracle = _oracle;
    }

    function withdrawToken(address to, uint256 amount) external onlyOwner {
        token.transfer(to, amount);
    }

    function updatePrice() external {
        prevPrice = uint256(oracle.latestAnswer());
    }

    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund) internal override returns (bytes memory context, uint256 validationData) {
        uint256 userProvidedPrice = uint256(bytes32(userOp.paymasterAndData[20:52]));
        uint256 minPrice = min(userProvidedPrice, prevPrice);
        uint256 gasPrice = UserOperationLib.gasPrice(userOp);
        uint256 cost = (requiredPreFund + POSTOP_COST * gasPrice) * minPrice / denominator;
        token.transferFrom(userOp.sender, address(this), cost);
        return (abi.encode(userOp.sender, cost, gasPrice, minPrice), _packValidationData(false, 0, 0));
    }

    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        (address sender, uint256 paid, uint256 gasPrice, uint256 minPrice) = abi.decode(context, (address, uint256, uint256, uint256));
        uint256 currentPrice = uint256(oracle.latestAnswer());
        if(minPrice > currentPrice) {
            // we need to get more token from sender
            uint256 leftover = (actualGasCost + POSTOP_COST * gasPrice) * currentPrice / denominator - paid;
            token.transferFrom(
                sender,
                address(this),
                leftover
            );
        }
        prevPrice = currentPrice;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}