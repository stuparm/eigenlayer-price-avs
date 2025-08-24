// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AVSOperatorRegistry.sol";
import "../src/PriceAggregator.sol";
import "../src/RewardManager.sol";
import "../src/AVSManager.sol";
import "../src/mocks/MockV3Pool.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockSlasher.sol";

contract AVSFlowTest is Test {
    address owner = address(0xA11CE);
    address op1 = address(0xB0B1);
    address op2 = address(0xB0B2);

    MockERC20 rewardToken;
    RewardManager rewards;
    AVSOperatorRegistry registry;
    MockV3Pool pool;
    PriceAggregator aggregator;
    AVSManager avs;
    MockERC20 t0;
    MockERC20 t1;
    MockSlasher slasher;

    function setUp() public {
        vm.startPrank(owner);

        // Reward token & manager
        rewardToken = new MockERC20("RWD", "RWD");
        rewards = new RewardManager(address(rewardToken));
        // Fund reward manager
        rewardToken.mint(owner, 1_000 ether);
        rewardToken.approve(address(rewards), type(uint256).max);
        rewards.fund(500 ether);

        // Pool & aggregator
        t0 = new MockERC20("T0", "T0");
        t1 = new MockERC20("T1", "T1");
        pool = new MockV3Pool(address(t0), address(t1));
        aggregator = new PriceAggregator(address(pool));

        // Initial spot (arbitrary but non-zero)
        pool.setSlot0(uint160(1 << 96), 0);

        // Registry & AVS
        registry = new AVSOperatorRegistry();
        avs = new AVSManager(address(registry), address(aggregator), address(rewards));

        // Slasher
        slasher = new MockSlasher();
        avs.setSlasher(address(slasher));

        // Set avs as allowed caller
        rewards.setAVS(address(avs));

        // Register two operators
        registry.register(op1);
        registry.register(op2);

        vm.stopPrank();
    }

    function _commit(address op, uint256 roundId, int256 predictionX96, bytes32 salt) internal {
        // commit = keccak(predictionX96, salt)
        bytes32 h = keccak256(abi.encodePacked(predictionX96, salt));
        vm.prank(op);
        avs.commit(roundId, h);
    }

    function _reveal(address op, uint256 roundId, int256 predictionX96, bytes32 salt) internal {
        vm.prank(op);
        avs.reveal(roundId, predictionX96, salt);
    }

    function test_commitRevealReward_validWithinBounds() public {
        uint256 roundId = 1;
        uint32 window = 600;
        uint256 deviationBps = 500; // 5%
        uint256 rewardPerValid = 10 ether;

        vm.prank(owner);
        avs.configureRound(roundId, window, deviationBps, rewardPerValid);

        // Configure TWAP reference in pool: avgTick = 0 -> twapPriceX96 equals spot (~2^96)
        pool.setTwapCumulatives(0, window);
        uint256 refX96 = aggregator.twapPriceX96(window);
        assertGt(refX96, 0, "ref must be > 0");

        // Operator 1 prediction: within 5%
        int256 pred1 = int256(refX96 * 10100 / 10000); // +1%
        bytes32 salt1 = bytes32(uint256(0x1111));
        _commit(op1, roundId, pred1, salt1);
        _reveal(op1, roundId, pred1, salt1);

        // Operator 2 prediction: also within 5%
        int256 pred2 = int256(refX96 * 9800 / 10000); // -2%
        bytes32 salt2 = bytes32(uint256(0x2222));
        _commit(op2, roundId, pred2, salt2);
        _reveal(op2, roundId, pred2, salt2);

        // Finalize: both should be rewarded, no slashes
        vm.prank(op1); // anyone can call finalize
        avs.finalize(roundId);

        // Both accrued
        assertEq(rewards.accrued(op1), rewardPerValid, "op1 reward");
        assertEq(rewards.accrued(op2), rewardPerValid, "op2 reward");
        // No slash reports
        assertEq(slasher.reports(), 0, "no slashes expected");
    }

    function test_noReveal_isSlashed() public {
        uint256 roundId = 2;
        uint32 window = 300;
        uint256 deviationBps = 300; // 3%
        uint256 rewardPerValid = 5 ether;

        vm.prank(owner);
        avs.configureRound(roundId, window, deviationBps, rewardPerValid);

        // TWAP reference setup
        pool.setTwapCumulatives(0, window);

        // op1 commits & reveals (valid)
        uint256 refX96 = aggregator.twapPriceX96(window);
        int256 pred1 = int256(refX96);
        bytes32 salt1 = bytes32(uint256(0xAAAA));
        _commit(op1, roundId, pred1, salt1);
        _reveal(op1, roundId, pred1, salt1);

        // op2 commits but DOES NOT reveal
        int256 pred2 = int256(refX96);
        bytes32 salt2 = bytes32(uint256(0xBBBB));
        _commit(op2, roundId, pred2, salt2);
        // no reveal for op2

        vm.prank(op1);
        avs.finalize(roundId);

        // op1 rewarded
        assertEq(rewards.accrued(op1), rewardPerValid, "op1 reward");
        // slasher should have 1 report (for op2)
        assertEq(slasher.reports(), 1, "one slash");
        assertEq(slasher.lastOp(), op2, "slashed op2");
    }

    function test_outOfBounds_isSlashed() public {
        uint256 roundId = 3;
        uint32 window = 600;
        uint256 deviationBps = 200; // 2% bound
        uint256 rewardPerValid = 7 ether;

        vm.prank(owner);
        avs.configureRound(roundId, window, deviationBps, rewardPerValid);

        pool.setTwapCumulatives(0, window);
        uint256 refX96 = aggregator.twapPriceX96(window);

        // op1: valid within 2%
        int256 pred1 = int256(refX96 * 10150 / 10000); // +1.5%
        bytes32 salt1 = bytes32(uint256(0xAAAA1111));
        _commit(op1, roundId, pred1, salt1);
        _reveal(op1, roundId, pred1, salt1);

        // op2: out of bounds (e.g., +3%)
        int256 pred2 = int256(refX96 * 10300 / 10000);
        bytes32 salt2 = bytes32(uint256(0xBBBB2222));
        _commit(op2, roundId, pred2, salt2);
        _reveal(op2, roundId, pred2, salt2);

        vm.prank(op2);
        avs.finalize(roundId);

        // op1 accrued, op2 slashed
        assertEq(rewards.accrued(op1), rewardPerValid, "op1 reward ok");
        assertEq(rewards.accrued(op2), 0, "op2 no reward");
        assertEq(slasher.reports(), 1, "one slash");
        assertEq(slasher.lastOp(), op2, "slashed op2");
    }

    function test_claimRewards() public {
        // Reuse happy-path test to accrue, then claim
        test_commitRevealReward_validWithinBounds();
        uint256 amount = rewards.accrued(op1);
        assertGt(amount, 0, "need accrued");

        // Fund already loaded; op1 claims
        vm.prank(op1);
        rewards.claim();

        assertEq(rewards.accrued(op1), 0, "reset accrued");
        // balance increased on op1
        assertEq(rewardToken.balanceOf(op1), amount, "op1 received tokens");
    }

    function test_onlyRegisteredCanCommitReveal() public {
        uint256 roundId = 4;
        vm.prank(owner);
        avs.configureRound(roundId, 300, 500, 1 ether);

        address notOp = address(0xDEAD);
        bytes32 salt = bytes32(uint256(123));
        int256 pred = 1; // anything

        vm.expectRevert("not operator");
        vm.prank(notOp);
        avs.commit(roundId, keccak256(abi.encodePacked(pred, salt)));

        vm.expectRevert("not operator");
        vm.prank(notOp);
        avs.reveal(roundId, pred, salt);
    }
}
