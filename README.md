# `ERC20Paymaster` contract

## Overview

This repository contains an ERC-4337 paymaster implementation allowing users to pay for gas fees with ERC-20 tokens, leveraging an oracle to fetch latest prices. The contract takes the max fee during the paymaster validation step, and refunds excess tokens if the actual gas cost is lower than the initially provided amount. It also allows updating price configuration and withdrawing tokens by the contract owner.

## Features
- ✅ Users paying with ERC-20 tokens for transaction fees
- ✅ Using guarantors to front gas fees to allow for token approvals during execution
- ✅ Compatible with EntryPoint v0.7
- ✅ Refunding excess tokens based on the actual user operation cost
- ✅ Using oracles to fetch latest gas prices
- ✅ Withdrawing accrued tokens by the contract owner

The ERC-20 paymaster supports:
- ✅ Standard ERC-20 tokens
- ✅ Up-rebasing tokens (e.g. stETH, AAVE balances)
- ❌ Down-rebasing tokens
- ❌ Fee-on-transfer tokens

## Usage

This paymaster has four modes. It allows the user to be simply made to pay themselves, but also allows the selection of a guarnator who can front the ERC-20 token fees during validation, allowing the user to approve tokens to the paymaster or fetch / claim tokens if they do not already have any. For each mode, it is possible to set a ERC-20 token spend limit to protect against sudden price fluctuations or oracle manipulation.  

Mode 0:
- The user (sender) pays for gas fees with the ERC-20 token.
- `paymasterData` is empty

Mode 1:
- The user (sender) pays for gas fees with the ERC-20 token, 
- There is a limit to the amount of ERC-20 tokens that can be taken from the user for the user opertion.
- `paymasterData`: "0x01" + token spend limit (32 bytes)

Mode 2:
- A guarantor fronts the ERC-20 token gas fees during validation, and expects the user to be able to pay the actual cost during the postOp phase and get refunded. Otherwise the guarantor is liable.
- `paymasterData`: "0x02" + guarantor address (20 bytes) + validUntil (6 bytes) + validAfter (6 bytes) + guarantor signature (dynamic bytes)

Mode 3:
- A guarantor fronts the ERC-20 token gas fees during validation, and expects the user to be able to pay the actual cost during the postOp phase and get refunded. Otherwise the guarantor is liable.
- There is a limit to the amount of ERC-20 tokens that can be taken from the user/guarantor for the user opertion.
- `paymasterData`: "0x03" + token spend limit (32 bytes) + guarantor address (20 bytes) + validUntil (6 bytes) + validAfter (6 bytes) + guarantor signature (dynamic bytes)

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

To install Halmos, run `pip install halmos` or follow [their detailed installation guide](https://github.com/a16z/halmos?tab=readme-ov-file#installation).

Halmos is used for symbolic tests.

1. install dependencies
```shell
forge install
```

2. run tests
```shell
halmos
```

## Security

The audits of the ERC-20 Paymaster can be found in the audits folder:
- [OpenZeppelin audit 2024 March](./audits/2024-03-openzeppelin.pdf)

## License
This project is licensed under the MIT license.