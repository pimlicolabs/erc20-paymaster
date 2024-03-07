# `ERC20Paymaster` contract

## Overview

This repository contains an ERC-4337 paymaster implementation allowing users to pay for gas fees with ERC-20 tokens, leveraging an oracle to fetch latest prices. The contract takes the max fee during the paymaster validation step, and refunds excess tokens if the actual gas cost is lower than the initially provided amount. It also allows updating price configuration and withdrawing tokens by the contract owner.

## Features
- ERC-20 token payments for transaction fees
- Refunding excess tokens based on actual gas cost
- Updating price configuration
- Withdrawing tokens by contract owner
- Fetching latest token prices using an Oracle

## Contract
The ERC20Paymaster contract inherits from BasePaymaster.

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

## Development

This repository uses Foundry and Halmos for development.

### Foundry

Run `foundryup` to make sure you have the latest foundry version.

Foundry is used for unit tests.

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
forge coverage --ir-minimum 
```

### Halmos

To install Halmos, run `pip install halmos` or follow [their more detailed installation guide](https://github.com/a16z/halmos?tab=readme-ov-file#installation).

Halmos is used for symbolic tests.

1. install dependencies
```shell
forge install
```

2. run tests
```shell
halmos
```

## License
This project is licensed under the MIT license.
