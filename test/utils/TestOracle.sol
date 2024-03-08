pragma solidity ^0.8.0;

import "../../src/interfaces/IOracle.sol";

contract TestOracle is IOracle {
    int256 public price;
    uint80 public roundId;
    uint256 public updatedAtDelay;

    constructor() {
        price = 100000000;
        roundId = 73786976294838215802;
        updatedAtDelay = 0;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }

    function setUpdatedAtDelay(uint256 _updatedAtDelay) external {
        updatedAtDelay = _updatedAtDelay;
    }

    function setRoundId(uint80 _roundId) external {
        roundId = _roundId;
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 _roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (roundId, price, 1680509051, block.timestamp - updatedAtDelay, 73786976294838215802);
    }
}
