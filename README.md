# Pimlico ERC20 Paymaster
## Overview
Pimlico ERC20 Paymaster is a smart contract designed for the pimlico.io to handle ERC20 token payments for transaction fees. It supports refunding excess tokens if the actual gas cost is lower than the initially provided amount. The contract also allows updating price configuration and withdrawing tokens by the contract owner. It uses an Oracle to fetch the latest token prices.

## Features
- ERC20 token payments for transaction fees
- Refunding excess tokens based on actual gas cost
- Updating price configuration
- Withdrawing tokens by contract owner
- Fetching latest token prices using an Oracle

## Contract
The PimlicoERC20Paymaster contract inherits from BasePaymaster and adheres to the UserOperation interface.

### Functions
- constructor: Initializes the PimlicoERC20Paymaster contract with the given parameters.
- updateConfig: Updates the price markup and price update threshold configurations.
- withdrawToken: Allows the contract owner to withdraw a specified amount of tokens from the contract.
- updatePrice: Updates the token price by fetching the latest price from the Oracle.
- _validatePaymasterUserOp: Validates a paymaster user operation and calculates the required token amount for the transaction.
- _postOp: Performs post-operation tasks, such as updating the token price and refunding excess tokens (if applicable).
### Events
- ConfigUpdated: Emitted when the price markup and price update threshold configurations are updated.

## Usage
Deploy the PimlicoERC20Paymaster contract, providing the required parameters such as the ERC20 token, EntryPoint contract, and Oracle contract addresses.
Update the price markup and price update threshold configurations if needed, using the updateConfig function.
If necessary, the contract owner can withdraw tokens using the withdrawToken function.
To update the token price, call the updatePrice function.
For more information, please refer to the comments within the contract source code.

## Development setup

this repository uses both hardhat and foundry for development, and assumes you have already installed hardhat/foundry

### hardhat

hardhat is used for gas metering and developing sdk.

1. install dependencies
```shell
npm install
```
2. run test
```
npx hardhat test
```
this will show results for the gas metering on different modes based on 1) refund 2) token payment limit 3) price update

*note* : first transaction is expensive because nonce increases 0 -> 1

### foundry

foundry is used for unit tests

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
