// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {Util} from "./Util.sol";

/// @notice Helper that exposes spot and TWAP prices for a single V3 pool.
/// Prices are returned in Q64.96 fixed-point as token1 per token0.
contract PriceAggregator {
    IUniswapV3Pool public immutable pool;

    constructor(address _pool) {
        require(_pool != address(0), "pool=0");
        pool = IUniswapV3Pool(_pool);
    }

    /// -----------------------------------------------------------------------
    /// Spot price
    /// -----------------------------------------------------------------------

    /// @notice Returns spot sqrtPriceX96 directly from slot0.
    function spotSqrtPriceX96() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = pool.slot0();
    }

    /// @notice Returns spot price (token1 per token0) in Q64.96.
    function spotPriceX96() external view returns (uint256) {
        uint160 sp = spotSqrtPriceX96();
        // priceX192 = sp^2, then shift >> 96 to get Q64.96
        return (uint256(sp) * uint256(sp)) >> 96;
    }

    /// -----------------------------------------------------------------------
    /// TWAP price
    /// -----------------------------------------------------------------------

    /// @notice Average tick over a lookback window.
    function twapTick(uint32 windowSeconds) public view returns (int24 avgTick) {
        require(windowSeconds > 0, "window<=0");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = windowSeconds;
        secondsAgos[1] = 0;

        (int56[] memory tickCums,) = pool.observe(secondsAgos);

        int56 tickDelta = tickCums[1] - tickCums[0];
        int56 avg = tickDelta / int56(uint56(windowSeconds));

        // clamp to int24 range
        if (avg > type(int24).max) avg = int56(int24(type(int24).max));
        if (avg < type(int24).min) avg = int56(int24(type(int24).min));

        avgTick = int24(avg);
    }

    /// @notice Returns the TWAP price (token1 per token0) in Q64.96 over `windowSeconds`.
    function twapPriceX96(uint32 windowSeconds) external view returns (uint256) {
        int24 avgTick = twapTick(windowSeconds);
        uint160 sqrtAt = Util.getSqrtRatioAtTick(avgTick);
        return (uint256(sqrtAt) * uint256(sqrtAt)) >> 96;
    }
}
