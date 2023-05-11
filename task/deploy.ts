import { task } from "hardhat/config";
import {
  EntryPoint__factory,
  SimpleAccount__factory,
  SimpleAccountFactory__factory,
} from "@account-abstraction/contracts/dist/types";
import { ERC20, ORACLE_ADDRESS, TOKEN_ADDRESS, calculateERC20PaymasterAddress, deployERC20Paymaster, getERC20Paymaster } from "../sdk";
import { fillUserOp, signUserOp } from "../test/hardhat/UserOp";
import { IERC20__factory, TestERC20__factory, TestOracle__factory } from "../typechain-types";
import { utils, Wallet, BigNumber, providers  } from "ethers";
import { HttpNetworkUserConfig } from "hardhat/types";
import { JsonRpcProvider } from "@ethersproject/providers";

const ENTRYPOINT_0_6 = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789";

task("mint-test-token","mint test token")
  .addParam("token", "token address")
  .addParam("amount", "amount to mint")
  .addParam("to", "address to mint to")
  .setAction(async (taskArgs, hre) => {
    const { ethers } = hre;
    const { token, amount, to } = taskArgs;
    const signer = (await ethers.getSigners())[0];
    const erc20 = new TestERC20__factory(signer).attach(token);
    await erc20.sudoMint(to, ethers.utils.parseEther(amount));
    console.log("minted " + amount + " to " + to);
  });

task("deploy-paymaster", "deploy erc20 paymaster")
  .addParam("token", "token ticker")
  .addOptionalParam("entrypoint", "entrypoint address")
  .addOptionalParam("tokenOracle", "token oracle address")
  .addOptionalParam("nativeOracle", "native asset oracle address")
  .addOptionalParam("owner", "owner address")
  .setAction(async (taskArgs, hre) => {
    const { ethers } = hre;
    const { token, entrypoint, tokenOracle, nativeOracle, owner } = taskArgs;
    const paymaster = await deployERC20Paymaster(
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
    console.log("contract deployed at : " + paymaster.paymasterContract.address);
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
    const tx = await erc20Paymaster.deposit({ value: ethers.utils.parseEther("0.1") });
    await tx.wait();
    console.log("deposit of paymaster: ", await erc20Paymaster.getDeposit());
  });

task("userop-test", "test userOps")
  .addParam("token", "token ticker")
  .addParam("owner", "owner address")
  .setAction(async (taskArgs, hre) => {
    const { ethers } = hre;
    const { token, owner } = taskArgs;  
    const erc20Paymaster = await getERC20Paymaster(
      ethers.provider,
      token,
      {
        owner: owner,
        deployer: (await ethers.getSigners())[0],
      }
    );

    const tokenAddr = TOKEN_ADDRESS[(await ethers.provider.getNetwork()).chainId][token];
    const signer = (await ethers.getSigners())[0];
    await erc20Paymaster.paymasterContract.connect(signer).updatePrice();
    const accOwner = createAccountOwner(ethers.provider);
    const factory = SimpleAccountFactory__factory.connect("0x628D5eCD6913d1E0375b1F1411ee6E402F717991", signer);
    const account = SimpleAccount__factory.connect(await factory.getAddress(await accOwner.getAddress(), 0), signer);
    const erc20 = IERC20__factory.connect(tokenAddr, signer);
    // await signer.sendTransaction({
    //   to: account.address,
    //   value: ethers.utils.parseEther("0.1")
    // });
    // await signer.sendTransaction({
    //   to: accOwner.address,
    //   value: ethers.utils.parseEther("0.1")
    // })

    // await account.connect(accOwner).execute(
    //   tokenAddr,
    //   0,
    //   erc20.interface.encodeFunctionData("approve",
    //     [
    //       erc20Paymaster.paymasterContract.address,
    //       ethers.constants.MaxUint256
    //     ]
    //   )
    // );

    // console.log("approved");
    // await erc20.connect(signer).transfer(account.address, ethers.utils.parseEther("1000"));
    // console.log("transferred");
    const entrypoint = EntryPoint__factory.connect(ENTRYPOINT_0_6, signer);
    let op = await fillUserOp({
      sender: account.address,
      preVerificationGas: 50304,
      callData: account.interface.encodeFunctionData(
        "execute",
        [
          tokenAddr,
          0,
          erc20.interface.encodeFunctionData("transfer", [await signer.getAddress(), ethers.utils.parseEther("1")])
        ]
      ),
      maxFeePerGas : "100000000000"
    }, entrypoint)

    const paymasterAndData = await erc20Paymaster.generatePaymasterAndData(op);
    console.log("paymasterAndData: ", paymasterAndData);
    op.paymasterAndData = paymasterAndData;
    op = signUserOp(op, accOwner, entrypoint.address, (await ethers.provider.getNetwork()).chainId);
    const bundlerRPC = new JsonRpcProvider("https://api.pimlico.io/v1/goerli/rpc?<API_KEY>");

    const structedOp = {
      sender: op.sender,
      callData: op.callData,
      maxFeePerGas: BigNumber.from(op.maxFeePerGas).toHexString(),
      maxPriorityFeePerGas: BigNumber.from(op.maxPriorityFeePerGas).toHexString(),
      paymasterAndData: op.paymasterAndData,
      signature: op.signature,
      nonce : BigNumber.from(op.nonce).toHexString(),
      initCode: op.initCode,
      preVerificationGas : BigNumber.from(op.preVerificationGas).toHexString(),
      verificationGasLimit : BigNumber.from(op.verificationGasLimit).toHexString(),
      callGasLimit : BigNumber.from(op.callGasLimit).toHexString(),
    }
    await bundlerRPC.send("eth_sendUserOperation", [structedOp, entrypoint.address]);
    // await entrypoint.handleOps([
    //   op
    // ], await signer.getAddress())
  })

// create non-random account, so gas calculations are deterministic
function createAccountOwner(provider: providers.Provider): Wallet {
  const privateKey = utils.keccak256(Buffer.from(utils.arrayify(BigNumber.from(0))))
  return new Wallet(privateKey, provider)
}
