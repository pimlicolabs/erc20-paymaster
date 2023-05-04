import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import '@typechain/hardhat'
import "@nomicfoundation/hardhat-foundry";
import "./task/deploy";

const config: HardhatUserConfig = {
  solidity: {
    version : "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000000,
      },
      viaIR : true,
    },
  } 
};

export default config;
