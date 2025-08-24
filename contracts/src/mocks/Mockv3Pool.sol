// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockV3Pool {
    address public token0_;
    address public token1_;

    // slot0 fields (only ones we use)
    uint160 public sqrtPriceX96;
    int24 public tick;

    // oracle ring buffer emulation (we’ll just return two cum values)
    int56 public tickCumulativeStart;
    int56 public tickCumulativeEnd;

    constructor(address _token0, address _token1) {
        token0_ = _token0;
        token1_ = _token1;
        sqrtPriceX96 = 0;
        tick = 0;
    }

    // --- Uniswap-like interface ---

    function token0() external view returns (address) {
        return token0_;
    }

    function token1() external view returns (address) {
        return token1_;
    }

    function slot0()
        external
        view
        returns (
            uint160 _sqrtPriceX96,
            int24 _tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        _sqrtPriceX96 = sqrtPriceX96;
        _tick = tick;
        observationIndex = 0;
        observationCardinality = 2;
        observationCardinalityNext = 2;
        feeProtocol = 0;
        unlocked = true;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128)
    {
        require(secondsAgos.length == 2, "need 2 points");
        tickCumulatives = new int56[](2);
        secondsPerLiquidityCumulativeX128 = new uint160[](2);

        // Return the two cumulative ticks we preloaded
        tickCumulatives[0] = tickCumulativeStart; // at t - window
        tickCumulatives[1] = tickCumulativeEnd; // at t
            // secondsPerLiquidity not used in our aggregator; leave zeros
    }

    // --- Helpers for tests ---

    function setSlot0(uint160 _sqrtPriceX96, int24 _tick) external {
        sqrtPriceX96 = _sqrtPriceX96;
        tick = _tick;
    }

    /// @dev Set cumulative ticks to simulate a TWAP over `windowSeconds`.
    /// For average tick T over window w: tickCumEnd - tickCumStart = T * w
    function setTwapCumulatives(int24 avgTick, uint32 windowSeconds) external {
        tickCumulativeStart = 0;
        tickCumulativeEnd = int56(int256(avgTick)) * int56(uint56(windowSeconds));
    }
}
