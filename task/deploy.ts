import { task } from "hardhat/config";
import { ORACLE_ADDRESS, TOKEN_ADDRESS, calculateERC20PaymasterAddress, deployERC20Paymaster } from "../sdk";

const ENTRYPOINT_0_6 = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789";

task("deploy-paymaster", "deploy erc20 paymaster")
  .addParam("token", "token ticker")
  .addOptionalParam("entrypoint", "entrypoint address")
  .addOptionalParam("tokenOracle", "token oracle address")
  .addOptionalParam("nativeOracle", "native asset oracle address")
  .addOptionalParam("owner", "owner address")
  .setAction(async (taskArgs, hre) => {
    const { ethers } = hre;
    const { token, entrypoint, tokenOracle, nativeOracle, owner } = taskArgs;
    const erc20Paymaster = await deployERC20Paymaster(
      ethers.provider,
      token,
      {
        entrypoint: entrypoint,
        tokenOracle: tokenOracle,
        nativeAssetOracle: nativeOracle,
        owner: owner??(await ethers.getSigners())[0].address,
        deployer: (await ethers.getSigners())[0],
      }
    );
  });

task("fund-paymaster", "fund erc20 paymaster")
  .addParam("token", "token ticker")
  .addParam("owner", "owner address")
  .setAction(async (taskArgs, hre) => {
    const { ethers } = hre;
    const { token, owner } = taskArgs;
    const paymasterAddress = calculateERC20PaymasterAddress({
      entrypoint: ENTRYPOINT_0_6,
      nativeAssetOracle : ORACLE_ADDRESS[(await ethers.provider.getNetwork()).chainId]["ETH"],
      tokenAddress : TOKEN_ADDRESS[(await ethers.provider.getNetwork()).chainId][token],
      tokenOracle : ORACLE_ADDRESS[(await ethers.provider.getNetwork()).chainId][token],
      owner : owner,
    });
    console.log("paymaster address: ", paymasterAddress);
    console.log("paymaster deployed: ", (await ethers.provider.getCode(paymasterAddress)).length > 2);
    const erc20Paymaster = await ethers.getContractAt("PimlicoERC20Paymaster", paymasterAddress);
    const tx = await erc20Paymaster.deposit({ value: ethers.utils.parseEther("1") });
    await tx.wait();
    console.log("deposit of paymaster: ", await erc20Paymaster.getDeposit());
  });
