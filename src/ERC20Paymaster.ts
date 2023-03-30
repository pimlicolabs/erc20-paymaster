import { ethers, Signer } from 'ethers'
import { BigNumberish, BigNumber } from 'ethers'
import { PimlicoERC20Paymaster } from '../typechain-types';
import { hexConcat, parseEther, hexZeroPad } from 'ethers/lib/utils'
import  axios from 'axios';

export interface SignedPriceData {
    paymasterAddress : string,
    chainId : number,
    price: BigNumberish,
    signedAt : BigNumberish,
    validUntil : BigNumberish,
    signature : string,
}

const API_KEY : string = "1babe94f-3bc2-4b12-8f59-2f1db41f6bb5" // this is for test, don't freak out

interface CMCQuote {
    price: number,
    volume_24h: number,
    volume_change_24h: number,
    percent_change_1h: number,
    percent_change_24h: number,
    percent_change_7d: number,
    percent_change_30d: number,
    percent_change_60d: number,
    percent_change_90d: number,
    market_cap: number,
    market_cap_dominance: number,
    fully_diluted_market_cap: number,
    tvl: number | null,
    last_updated: string,
}

export class ERC20Paymaster {

    sigValidPeriod : number;

    constructor(
        readonly provider: ethers.providers.JsonRpcProvider,
        readonly erc20Paymaster : PimlicoERC20Paymaster,
        readonly signer : Signer,
        readonly owner = signer,
        readonly cmcAPIKey = API_KEY,
        readonly cmcId = 1027, // 1027 represents Ethereum
        sigValidPeriod? : number
    ) {
        this.sigValidPeriod = sigValidPeriod || 5 * 60; // 5 minutes default
    }
    
    async getSignedPriceData() : Promise<SignedPriceData> {
        const paymasterAddress = this.erc20Paymaster.address
        const chainId = (await this.provider.getNetwork()).chainId
        const price = await this.getPrice();
        const signedAt = Math.floor(Date.now() / 1000)
        const validUntil = signedAt + this.sigValidPeriod
        const signature = await this.signer._signTypedData({
            name: 'PimlicoERC20Paymaster',
            version: '0.0.1',
            chainId: await this.provider.getNetwork().then(network => network.chainId),
            verifyingContract: this.erc20Paymaster.address,
          },{
            PaymasterPrice: [
              { name: 'price', type: 'uint160' },
              { name: 'signedAt', type: 'uint48'},
              { name: 'validUntil', type: 'uint48' },
            ]
          }, {
            price: price,
            signedAt: signedAt,
            validUntil: validUntil
          })
        return { paymasterAddress, chainId, price, signedAt, validUntil, signature }
    }

    async setEmergencyPrice(price : BigNumberish) : Promise<ethers.ContractTransaction> {
        return this.erc20Paymaster.connect(this.owner).setEmergencyPrice(price)
    }

    async stopEmergencyPrice() : Promise<ethers.ContractTransaction> {
        return this.erc20Paymaster.connect(this.owner).setEmergencyPrice(0)
    }

    async getPrice() : Promise<BigNumberish> {
        const response = await this.queryCMC();
        return BigNumber.from(ethers.utils.parseEther(response.price.toString()));
    }

    async getVolatility() : Promise<BigNumberish> {
        const response = await this.queryCMC();
        return response.percent_change_24h;
    }

    async queryCMC() : Promise<CMCQuote>{
        const response = await axios.get(
            "https://pro-api.coinmarketcap.com/v2/cryptocurrency/quotes/latest?id="+this.cmcId,{
                headers: {
                    'X-CMC_PRO_API_KEY': this.cmcAPIKey,
                }
            })
        return response.data.data[this.cmcId].quote.USD;
    }
}

export function encodePaymasterData(signedPriceData : SignedPriceData, maxCost : BigNumberish) : string {
    const { paymasterAddress, price, signedAt, validUntil, signature } = signedPriceData
    const encodedPrice = hexZeroPad(BigNumber.from(price).toHexString(), 20)
    const encodedSignedAt = hexZeroPad(BigNumber.from(signedAt).toHexString(), 6)
    const encodedValidUntil = hexZeroPad(BigNumber.from(validUntil).toHexString(), 6)
    const encodedMaxCost = hexZeroPad(BigNumber.from(maxCost).toHexString(), 32)
    const encodedSignature = signature

    const encodedData = hexConcat([
        paymasterAddress,
        encodedMaxCost,
        encodedPrice,
        encodedSignedAt,
        encodedValidUntil,
        encodedSignature
    ])
    return encodedData
}