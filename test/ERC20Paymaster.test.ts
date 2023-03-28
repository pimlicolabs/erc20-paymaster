import { Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import {
  SimpleAccount,
  EntryPoint,
  SimpleAccountFactory,
  SimpleAccountFactory__factory
} from '@account-abstraction/contracts/dist/types'
import {
  TestCounter,
  TestCounter__factory,
  ERC20Paymaster,
  ERC20Paymaster__factory,
  TestERC20__factory,
  TestERC20
} from "../typechain-types";
import {
  AddressZero,
  createAccountOwner,
  fund,
  getBalance,
  getTokenBalance,
  rethrow,
  checkForGeth,
  calcGasUsage,
  deployEntryPoint,
  checkForBannedOps,
  createAddress,
  ONE_ETH,
  createAccount,
  getAccountAddress
} from './testutils'
import { fillAndSign } from './UserOp'
import { hexConcat, parseEther, hexZeroPad } from 'ethers/lib/utils'
import { UserOperation } from './UserOperation'
import { hexValue } from '@ethersproject/bytes'

describe('EntryPoint with paymaster', function () {
  let entryPoint: EntryPoint
  let accountOwner: Wallet
  let priceSigner : Wallet
  const ethersSigner = ethers.provider.getSigner()
  let account: SimpleAccount
  const beneficiaryAddress = '0x'.padEnd(42, '1')
  let factory: SimpleAccountFactory

  function getAccountDeployer (entryPoint: string, accountOwner: string, _salt: number = 0): string {
    return hexConcat([
      factory.address,
      hexValue(factory.interface.encodeFunctionData('createAccount', [accountOwner, _salt])!)
    ])
  }

  before(async function () {
    this.timeout(20000)
    await checkForGeth()

    entryPoint = await deployEntryPoint()
    factory = await new SimpleAccountFactory__factory(ethersSigner).deploy(entryPoint.address)

    accountOwner = createAccountOwner();
    priceSigner = createAccountOwner();
    ({ proxy: account } = await createAccount(ethersSigner, await accountOwner.getAddress(), entryPoint.address, factory))
    await fund(account)
  })

  describe('using TokenPaymaster (account pays in paymaster tokens)', () => {
    let paymaster: ERC20Paymaster
    let token: TestERC20
    before(async () => {
      token = await new TestERC20__factory(ethersSigner).deploy()
      paymaster = await new ERC20Paymaster__factory(ethersSigner).deploy(token.address, entryPoint.address, priceSigner.address)
      // await token.transfer(account.address, await token.balanceOf(await ethersSigner.getAddress()));
      // await token.sudoApprove(account.address, paymaster.address, ethers.constants.MaxUint256);
      await entryPoint.depositTo(paymaster.address, { value: parseEther('1') })
      await paymaster.addStake(1, { value: parseEther('2') })
    })

    describe('#handleOps', () => {
      let calldata: string
      let priceData: string
      before(async () => {
        calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
        const sig = await priceSigner._signTypedData({
          name: 'ERC20Paymaster',
          version: '0.0.1',
          chainId: 31337,
          verifyingContract: paymaster.address,
        },{
          PaymasterPrice: [
            { name: 'price', type: 'uint160' },
            { name: 'signedAt', type: 'uint48'},
            { name: 'validUntil', type: 'uint48' },
          ]
        }, {
          price: "1000000000000",
          signedAt: 0,
          validUntil: "0xffffffffffff"
        })

        priceData = hexConcat([
          paymaster.address,
          hexZeroPad(ethers.constants.MaxUint256.toHexString(),32),
          hexZeroPad(ethers.BigNumber.from("1000000000000").toHexString(), 20),
          hexZeroPad("0x00", 6),
          hexZeroPad("0xffffffffffff", 6),
          sig
        ])
      })
      it('paymaster should reject if account doesn\'t have tokens', async () => {
        const op = await fillAndSign({
          sender: account.address,
          paymasterAndData: priceData,
          callData: calldata
        }, accountOwner, entryPoint)
        await expect(entryPoint.callStatic.handleOps([op], beneficiaryAddress, {
          gasLimit: 1e7
        })).to.revertedWith('FailedOp') // TODO : weird => cannot get AA32
        await expect(entryPoint.handleOps([op], beneficiaryAddress, {
          gasLimit: 1e7
        })).to.revertedWith('') // TODO : weird
      })
      it('paymaster be able to sponsor tx', async () => {
        await token.transfer(account.address, await token.balanceOf(await ethersSigner.getAddress()));
        await token.sudoApprove(account.address, paymaster.address, ethers.constants.MaxUint256);

        const op = await fillAndSign({
          sender: account.address,
          paymasterAndData: priceData,
          callData: calldata
        }, accountOwner, entryPoint)
        await entryPoint.callStatic.handleOps([op], beneficiaryAddress, {
          gasLimit: 1e7
        })
        await entryPoint.handleOps([op], beneficiaryAddress, {
          gasLimit: 1e7
        })
      })
    })
  })
})
