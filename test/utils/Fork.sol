// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "forge-std/Test.sol";


enum ForkNetwork {
    MAINNET
}

abstract contract Fork is Test {
    modifier onFork(ForkNetwork network, uint256 blockNumber) {
        string memory rpc = _getRPC(network);

        uint fork = vm.createFork(rpc);
        vm.selectFork(fork);
        vm.rollFork(blockNumber);

        _;
    }

    function _getRPC(ForkNetwork network) internal view returns (string memory) {
        if (network == ForkNetwork.MAINNET) {
            return vm.envString("MAINNET_ARCHIVE_RPC_URL");
        }

        return "";
    }
}