"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ERC20Paymaster = exports.Blockchains = exports.ERC20 = void 0;
const ethers_1 = require("ethers");
const typechain_types_1 = require("../typechain-types");
var ERC20;
(function (ERC20) {
    ERC20[ERC20["DAI"] = 0] = "DAI";
    ERC20[ERC20["USDC"] = 1] = "USDC";
    ERC20[ERC20["USDT"] = 2] = "USDT";
})(ERC20 = exports.ERC20 || (exports.ERC20 = {}));
var Blockchains;
(function (Blockchains) {
    Blockchains["ETHEREUM"] = "ETHEREUM";
    Blockchains["POLYGON"] = "POLYGON";
    Blockchains["BSC"] = "BSC";
})(Blockchains = exports.Blockchains || (exports.Blockchains = {}));
class ERC20Paymaster {
    constructor(signer, paymasterAddress) {
        this.paymasterContract = new typechain_types_1.PimlicoERC20Paymaster__factory(signer).attach(paymasterAddress);
    }
    async calculateTokenAmount(userOp) {
        const priceMarkup = await this.paymasterContract.priceMarkup();
        const cachedPrice = await this.paymasterContract.previousPrice();
        const requiredPreFund = ethers_1.BigNumber.from(userOp.preVerificationGas)
            .add(ethers_1.BigNumber.from(userOp.verificationGasLimit).mul(3))
            .add(ethers_1.BigNumber.from(userOp.callGasLimit))
            .mul(ethers_1.BigNumber.from(userOp.maxFeePerGas));
        const tokenAmount = requiredPreFund
            .add(ethers_1.BigNumber.from(userOp.maxFeePerGas).mul(40000)) // 40000 is the REFUND_POSTOP_COST constant
            .mul(priceMarkup)
            .mul(cachedPrice)
            .div(ethers_1.BigNumber.from(10).pow(18))
            .div(1e6); // 1e6 is the priceDenominator constant
        return tokenAmount;
    }
    async generatePaymasterAndData(userOp) {
        const tokenAmount = await this.calculateTokenAmount(userOp);
        const paymasterAndData = ethers_1.utils.concat([
            this.paymasterContract.address,
            ethers_1.utils.defaultAbiCoder.encode(["uint256", "address"], [tokenAmount, userOp.sender]),
        ]);
        return paymasterAndData;
    }
}
exports.ERC20Paymaster = ERC20Paymaster;
