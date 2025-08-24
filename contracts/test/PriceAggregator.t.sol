// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PriceAggregator.sol";
import "../src/mocks/MockV3Pool.sol";
import "../src/mocks/MockERC20.sol";

contract PriceAggregatorTest is Test {
    MockERC20 t0;
    MockERC20 t1;
    MockV3Pool pool;
    PriceAggregator agg;

    function setUp() public {
        t0 = new MockERC20("T0", "T0");
        t1 = new MockERC20("T1", "T1");
        pool = new MockV3Pool(address(t0), address(t1));
        agg = new PriceAggregator(address(pool));

        // Set some spot values (sqrtPriceX96 squared >>96 = Q64.96 price)
        // e.g., sqrtPriceX96 = 2^96 => priceX96 = (2^96)^2 >>96 = 2^96 (not human, but fine for test)
        pool.setSlot0(uint160(1 << 96), 0);
    }

    function test_spotPriceX96() public view {
        uint256 px = agg.spotPriceX96();
        // With sqrtPriceX96 = 2^96, px = (2^96 * 2^96) >> 96 = 2^96
        assertEq(px, uint256(1) << 96, "spot px mismatch");
    }

    function test_twapTickAndPriceX96() public {
        // Configure TWAP: avgTick = 100; window = 600s
        int24 avgTick = 100;
        uint32 window = 600;
        pool.setTwapCumulatives(avgTick, window);

        int24 gotTick = agg.twapTick(window);
        assertEq(gotTick, avgTick, "avg tick mismatch");

        // If your PriceAggregator computes twapPriceX96 via your copied function,
        // just assert it returns non-zero.
        uint256 pxX96 = agg.twapPriceX96(window);
        assertGt(pxX96, 0, "twap price should be > 0");
    }
}
