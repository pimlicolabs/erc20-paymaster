# Pimlico ERC20 Paymaster
## Overview
PimlicoERC20Paymaster is an ERC-4337 Paymaster contract by Pimlico which is able to sponsor gas fees in exchange for ERC20 tokens. The contract refunds excess tokens if the actual gas cost is lower than the initially provided amount. It also allows updating price configuration and withdrawing tokens by the contract owner. The contract uses an Oracle to fetch the latest token prices.

## Features
- ERC20 token payments for transaction fees
- Refunding excess tokens based on actual gas cost
- Updating price configuration
- Withdrawing tokens by contract owner
- Fetching latest token prices using an Oracle

## Contract
The PimlicoERC20Paymaster contract inherits from BasePaymaster.

### Functions
- constructor: Initializes the PimlicoERC20Paymaster contract with the given parameters.
- updateConfig: Updates the price markup and price update threshold configurations.
- withdrawToken: Allows the contract owner to withdraw a specified amount of tokens from the contract.
- updatePrice: Updates the token price by fetching the latest price from the Oracle.
- _validatePaymasterUserOp: Validates a paymaster user operation and calculates the required token amount for the transaction.
- _postOp: Performs post-operation tasks, such as updating the token price and refunding excess tokens.
### Events
- ConfigUpdated: Emitted when the price markup and price update threshold configurations are updated.

## Usage
Deploy the PimlicoERC20Paymaster contract, providing the required parameters such as the ERC20 token, EntryPoint contract, and Oracle contract addresses.
Update the price markup and price update threshold configurations if needed, using the updateConfig function.
If necessary, the contract owner can withdraw tokens using the withdrawToken function.
To update the token price, call the updatePrice function.
For more information, please refer to the comments within the contract source code.

## Development setup

This repository uses both hardhat and foundry for development, and assumes you have already installed hardhat/foundry

### hardhat

Hardhat is used for gas metering and developing sdk.

1. install dependencies
```shell
npm install
```
2. run test
```
Npx hardhat test
```
This will show results for the gas metering on different modes based on 1) refund 2) token payment limit 3) price update

*note* : first transaction is expensive because nonce increases 0 -> 1

### foundry

Foundry is used for unit tests

1. install dependencies
```shell
forge install
```

2. run tests
```shell
forge test
```

3. run coverage
```shell
forge coverage
```


## License
This project is licensed under the GNU General Public License v3.0.
