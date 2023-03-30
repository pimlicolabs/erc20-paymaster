import { ethers, Signer } from 'ethers'
import { BigNumberish, BigNumber } from 'ethers'
import { PimlicoERC20Paymaster } from '../typechain-types';
import { hexConcat, parseEther, hexZeroPad } from 'ethers/lib/utils'
import  axios from 'axios';

interface SignedPriceData {
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
    constructor(
        readonly provider: ethers.providers.JsonRpcProvider,
        readonly erc20Paymaster : PimlicoERC20Paymaster,
        readonly signer : Signer,
        readonly cmcAPIKey = API_KEY,
        readonly cmcId = 1027, // 1027 represents Ethereum
    ) {
    }
    
    async getSignedPriceData() : Promise<SignedPriceData> {
        const paymasterAddress = this.erc20Paymaster.address
        const chainId = (await this.provider.getNetwork()).chainId
        const price = await this.getPrice();
        const signedAt = Math.floor(Date.now() / 1000)
        const validUntil = signedAt + 60 * 60 * 24 * 30 // todo this should be configurable
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

    async getPrice() : Promise<BigNumberish> {
        const response = await this.queryCMC();
        return BigNumber.from(ethers.utils.parseEther(response.price.toString()));
    }

    async queryCMC() : Promise<CMCQuote>{
        const response = await axios.get("https://pro-api.coinmarketcap.com/v2/cryptocurrency/quotes/latest?CMC_PRO_API_KEY=" + this.cmcAPIKey + "&id="+this.cmcId)
        return response.data.data[this.cmcId].quote.USD;
    }
}

export function encodePaymasterData(signedPriceData : SignedPriceData, maxCost : BigNumberish) : string {
    const { paymasterAddress, chainId, price, signedAt, validUntil, signature } = signedPriceData
    const encodedPrice = hexZeroPad(BigNumber.from(price).toHexString(), 20)
    const encodedSignedAt = hexZeroPad(BigNumber.from(signedAt).toHexString(), 6)
    const encodedValidUntil = hexZeroPad(BigNumber.from(validUntil).toHexString(), 6)
    const encodedMaxCost = hexZeroPad(BigNumber.from(maxCost).toHexString(), 32)
    const encodedSignature = signature

    // priceData = hexConcat([
    //     paymaster.address,
    //     hexZeroPad(ethers.constants.MaxUint256.toHexString(),32),
    //     hexZeroPad(ethers.BigNumber.from("1000000000000").toHexString(), 20),
    //     hexZeroPad("0x00", 6),
    //     hexZeroPad("0xffffffffffff", 6),
    //     sig
    //   ])

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