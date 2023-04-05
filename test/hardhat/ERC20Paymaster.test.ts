import { Wallet, BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import {
  SimpleAccount,
  EntryPoint,
  SimpleAccountFactory,
  SimpleAccountFactory__factory
} from '@account-abstraction/contracts/dist/types'
import {
  PimlicoERC20Paymaster,
  PimlicoERC20Paymaster__factory,
  TestERC20__factory,
  TestERC20,
  TestOracle,
  TestOracle__factory
} from "../../typechain-types";
import {
  createAccountOwner,
  fund,
  checkForGeth,
  deployEntryPoint,
  createAccount,
} from './testutils'
import { fillAndSign } from './UserOp'
import { hexConcat, parseEther, hexZeroPad } from 'ethers/lib/utils'

describe('EntryPoint with paymaster', function () {
  let entryPoint: EntryPoint
  let accountOwner: Wallet
  let oracle : TestOracle
  let account: SimpleAccount
  let factory: SimpleAccountFactory
  const ethersSigner = ethers.provider.getSigner()
  const beneficiaryAddress = '0x'.padEnd(42, '1')

  before(async function () {
    entryPoint = await deployEntryPoint()
    factory = await new SimpleAccountFactory__factory(ethersSigner).deploy(entryPoint.address)

    accountOwner = createAccountOwner();
    const { proxy } = await createAccount(ethersSigner, await accountOwner.getAddress(), entryPoint.address, factory)
    account = proxy;
    await fund(account)
  })

  describe('using TokenPaymaster (account pays in paymaster tokens)', () => {
    let paymaster: PimlicoERC20Paymaster
    let token: TestERC20
    before(async () => {
      await checkForGeth();
      token = await new TestERC20__factory(ethersSigner).deploy()
      oracle = await new TestOracle__factory(ethersSigner).deploy()
      paymaster = await new PimlicoERC20Paymaster__factory(ethersSigner).deploy(token.address, entryPoint.address, oracle.address, await ethersSigner.getAddress())
      await token.transfer(paymaster.address, 100);
      await paymaster.updatePrice();
      await entryPoint.depositTo(paymaster.address, { value: parseEther('1000') })
      await paymaster.addStake(1, { value: parseEther('2') })
    })

    describe('gas cost comparison, #note, first call is always more expensive', () => {
      describe('no price change',() => {
        describe('#handleOps - refund, no price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            priceData = hexConcat([paymaster.address]);
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })

        describe('#handleOps - no refund, no price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            priceData = hexConcat([paymaster.address, "0x00"]);
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })

        describe('#handleOps - refund, max price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            const price = await paymaster.previousPrice();
            priceData = hexConcat([paymaster.address, hexZeroPad(price.mul(95).div(100).toHexString(), 32)]);
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })

        describe('#handleOps - no refund, max price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            const price = await paymaster.previousPrice();
            priceData = hexConcat([paymaster.address, hexZeroPad(ethers.constants.WeiPerEther.mul(10).toHexString(), 32), "0x00"]);
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })
      });
      describe('with price change',() => {
        describe('#handleOps - refund, no price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            priceData = hexConcat([paymaster.address]);
            let priceOld = await paymaster.previousPrice();
            await oracle.setPrice(priceOld.mul(103).div(100));
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })

        describe('#handleOps - no refund, no price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            priceData = hexConcat([paymaster.address, "0x00"]);
            let priceOld = await paymaster.previousPrice();
            await oracle.setPrice(priceOld.mul(103).div(100));
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })

        describe('#handleOps - refund, max price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            const price = await paymaster.previousPrice();
            priceData = hexConcat([paymaster.address, hexZeroPad(price.mul(95).div(100).toHexString(), 32)]);
            let priceOld = await paymaster.previousPrice();
            await oracle.setPrice(priceOld.mul(103).div(100));
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })

        describe('#handleOps - no refund, max price', () => {
          let calldata: string
          let priceData: string
          before(async () => {
            calldata = await account.populateTransaction.execute(accountOwner.address, 0, "0x").then(tx => tx.data!)
            let priceOld = await paymaster.previousPrice();
            await oracle.setPrice(priceOld.mul(103).div(100));
            const price = await paymaster.previousPrice();
            priceData = hexConcat([paymaster.address, hexZeroPad(price.mul(95).div(100).toHexString(), 32), "0x00"]);
            await token.sudoTransfer(account.address, await ethersSigner.getAddress());
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
            const tx = await entryPoint.handleOps([op], beneficiaryAddress, {
              gasLimit: 1e7
            }).then(async tx => await tx.wait())
            console.log("gas used", tx.gasUsed?.toString())
          })
        })
      });
    })
  })
})
