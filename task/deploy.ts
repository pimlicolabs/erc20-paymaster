import { task } from "hardhat/config"
import {
    EntryPoint__factory,
    SimpleAccount__factory,
    SimpleAccountFactory__factory
} from "@account-abstraction/contracts/dist/types"
import {
  NATIVE_ASSET,
    ORACLE_ADDRESS,
    TOKEN_ADDRESS,
    calculateERC20PaymasterAddress,
    deployERC20Paymaster,
    getERC20Paymaster
} from "../sdk"
import { fillUserOp, signUserOp } from "../test/hardhat/UserOp"
import { IERC20__factory } from "../sdk/typechain"
import { utils, Wallet, BigNumber, providers } from "ethers"

const ENTRYPOINT_0_6 = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"

task("deploy-paymaster", "deploy erc20 paymaster")
    .addParam("token", "token ticker")
    .addOptionalParam("entrypoint", "entrypoint address")
    .addOptionalParam("tokenOracle", "token oracle address")
    .addOptionalParam("nativeOracle", "native asset oracle address")
    .addOptionalParam("owner", "owner address")
    .setAction(async (taskArgs, hre) => {
        const { ethers } = hre
        const { token, entrypoint, tokenOracle, nativeOracle, owner } = taskArgs
        await deployERC20Paymaster(ethers.provider, token, {
            entrypoint: entrypoint,
            tokenOracle: tokenOracle,
            nativeAssetOracle: nativeOracle,
            owner: owner ?? (await ethers.getSigners())[0].address,
            deployer: (await ethers.getSigners())[0]
        })
    })

task("paymaster-address", "calculate erc20 paymaster address")
  .addParam("token", "token ticker")
  .addOptionalParam("entrypoint", "entrypoint address")
  .addOptionalParam("tokenOracle", "token oracle address")
  .addOptionalParam("nativeOracle", "native asset oracle address")
  .addOptionalParam("owner", "owner address")
  .setAction(async (taskArgs, hre) => {
      const { ethers } = hre
      const { token, entrypoint, tokenOracle, nativeOracle, owner } = taskArgs
      console.log("paymaster address: ", calculateERC20PaymasterAddress({
        entrypoint: entrypoint ?? ENTRYPOINT_0_6,
        tokenAddress: TOKEN_ADDRESS[(await ethers.provider.getNetwork()).chainId][token],
        tokenOracle: tokenOracle ?? ORACLE_ADDRESS[(await ethers.provider.getNetwork()).chainId][token],
        nativeAssetOracle: nativeOracle ?? ORACLE_ADDRESS[(await ethers.provider.getNetwork()).chainId][NATIVE_ASSET[(await ethers.provider.getNetwork()).chainId]],
        owner: owner ?? (await ethers.getSigners())[0].address
      }))
  })

task("fund-paymaster", "fund erc20 paymaster")
    .addParam("token", "token ticker")
    .addParam("owner", "owner address")
    .setAction(async (taskArgs, hre) => {
        const { ethers } = hre
        const { token, owner } = taskArgs
        const paymasterAddress = calculateERC20PaymasterAddress({
            entrypoint: ENTRYPOINT_0_6,
            nativeAssetOracle: ORACLE_ADDRESS[(await ethers.provider.getNetwork()).chainId]["ETH"],
            tokenAddress: TOKEN_ADDRESS[(await ethers.provider.getNetwork()).chainId][token],
            tokenOracle: ORACLE_ADDRESS[(await ethers.provider.getNetwork()).chainId][token],
            owner: owner
        })
        console.log("paymaster address: ", paymasterAddress)
        console.log("paymaster deployed: ", (await ethers.provider.getCode(paymasterAddress)).length > 2)
        const erc20Paymaster = await ethers.getContractAt("PimlicoERC20Paymaster", paymasterAddress)
        const tx = await erc20Paymaster.deposit({ value: ethers.utils.parseEther("1") })
        await tx.wait()
        console.log("deposit of paymaster: ", await erc20Paymaster.getDeposit())
    })

task("userop-test", "test userOps")
    .addParam("token", "token ticker")
    .addParam("owner", "owner address")
    .setAction(async (taskArgs, hre) => {
        const { ethers } = hre
        const { token, owner } = taskArgs
        const erc20Paymaster = await getERC20Paymaster(ethers.provider, token, {
            owner: owner,
            deployer: (await ethers.getSigners())[0]
        })

        const tokenAddr = TOKEN_ADDRESS[(await ethers.provider.getNetwork()).chainId][token]
        const signer = (await ethers.getSigners())[0]
        await erc20Paymaster.contract.connect(signer).updatePrice()
        const accOwner = createAccountOwner(ethers.provider)
        const factory = await new SimpleAccountFactory__factory(signer).deploy(ENTRYPOINT_0_6)
        await factory.createAccount(await accOwner.getAddress(), 0)
        const account = SimpleAccount__factory.connect(await factory.getAddress(await accOwner.getAddress(), 0), signer)
        const erc20 = IERC20__factory.connect(tokenAddr, signer)
        await signer.sendTransaction({
            to: await accOwner.getAddress(),
            value: ethers.utils.parseEther("1")
        })
        await signer.sendTransaction({
            to: account.address,
            value: ethers.utils.parseEther("1")
        })

        await account
            .connect(accOwner)
            .execute(
                tokenAddr,
                0,
                erc20.interface.encodeFunctionData("approve", [
                    erc20Paymaster.contract.address,
                    ethers.constants.MaxUint256
                ])
            )

        console.log("approved")
        const DAI_ETHEREUM_WHALE = "0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8"
        await ethers.provider.send("hardhat_impersonateAccount", [DAI_ETHEREUM_WHALE])
        const whale = await ethers.provider.getSigner(DAI_ETHEREUM_WHALE)
        await erc20.connect(whale).transfer(account.address, ethers.utils.parseEther("1000"))
        console.log("transferred")
        const entrypoint = EntryPoint__factory.connect(ENTRYPOINT_0_6, signer)
        let op = await fillUserOp(
            {
                sender: account.address,
                callData: account.interface.encodeFunctionData("execute", [
                    tokenAddr,
                    0,
                    erc20.interface.encodeFunctionData("transfer", [
                        await signer.getAddress(),
                        ethers.utils.parseEther("1")
                    ])
                ]),
                maxFeePerGas: "100000000000"
            },
            entrypoint
        )

        const paymasterAndData = await erc20Paymaster.generatePaymasterAndData(op)
        console.log("paymasterAndData: ", paymasterAndData)
        op.paymasterAndData = paymasterAndData
        op = signUserOp(op, accOwner, entrypoint.address, (await ethers.provider.getNetwork()).chainId)
        await entrypoint.handleOps([op], await signer.getAddress())
    })

// create non-random account, so gas calculations are deterministic
function createAccountOwner(provider: providers.Provider): Wallet {
    const privateKey = utils.keccak256(Buffer.from(utils.arrayify(BigNumber.from(0))))
    return new Wallet(privateKey, provider)
}
