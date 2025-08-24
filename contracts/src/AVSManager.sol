// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AVSOperatorRegistry.sol";
import "./PriceAggregator.sol";
import "./RewardManager.sol";
import "./interfaces/ISlasherHook.sol";

contract AVSManager {
    struct Round {
        uint32 twapWindow; // seconds for TWAP
        uint256 deviationBps; // max deviation in BPS (10_000 = 100%)
        uint256 rewardPerValid; // flat reward for valid reveal
        bool finalized;
        address[] participants;
        mapping(address => bytes32) commits; // operator => commit hash
        mapping(address => int256) reveals; // operator => prediction (Q64.96)
        mapping(address => bool) isInRound;
    }

    AVSOperatorRegistry public immutable registry;
    PriceAggregator public immutable aggregator;
    RewardManager public immutable rewards;
    ISlasherHook public slasher;

    address public owner;
    mapping(uint256 => Round) private _rounds;

    event Committed(uint256 indexed roundId, address indexed operator, bytes32 commitHash);
    event Revealed(uint256 indexed roundId, address indexed operator, int256 predictionX96);
    event Finalized(uint256 indexed roundId, uint256 refPriceX96);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyOperator() {
        require(registry.isOperator(msg.sender), "not operator");
        _;
    }

    constructor(address _registry, address _aggregator, address _rewards) {
        owner = msg.sender;
        registry = AVSOperatorRegistry(_registry);
        aggregator = PriceAggregator(_aggregator);
        rewards = RewardManager(_rewards);
    }

    function setSlasher(address hook) external onlyOwner {
        slasher = ISlasherHook(hook);
    }

    /// Configure a round (call before commits start)
    function configureRound(uint256 roundId, uint32 twapWindowSeconds, uint256 deviationBps, uint256 rewardPerValid)
        external
        onlyOwner
    {
        Round storage r = _rounds[roundId];
        require(!r.finalized, "finalized");
        require(twapWindowSeconds > 0, "window=0");
        require(deviationBps > 0, "dev=0");
        r.twapWindow = twapWindowSeconds;
        r.deviationBps = deviationBps;
        r.rewardPerValid = rewardPerValid;
    }

    /// -------------------
    /// Commit / Reveal
    /// -------------------
    function commit(uint256 roundId, bytes32 commitHash) external onlyOperator {
        Round storage r = _rounds[roundId];
        require(!r.finalized, "finalized");
        require(r.commits[msg.sender] == bytes32(0), "already committed");
        r.commits[msg.sender] = commitHash;
        if (!r.isInRound[msg.sender]) {
            r.isInRound[msg.sender] = true;
            r.participants.push(msg.sender);
        }
        emit Committed(roundId, msg.sender, commitHash);
    }

    function reveal(uint256 roundId, int256 predictionX96, bytes32 salt) external onlyOperator {
        Round storage r = _rounds[roundId];
        require(!r.finalized, "finalized");
        require(r.commits[msg.sender] != bytes32(0), "no commit");
        require(r.reveals[msg.sender] == int256(0), "revealed");

        bytes32 h = keccak256(abi.encodePacked(predictionX96, salt));
        require(h == r.commits[msg.sender], "hash mismatch");
        r.reveals[msg.sender] = predictionX96;

        emit Revealed(roundId, msg.sender, predictionX96);
    }

    /// -------------------
    /// Finalize & Consequences
    /// -------------------
    function finalize(uint256 roundId) external {
        Round storage r = _rounds[roundId];
        require(!r.finalized, "finalized");
        require(r.twapWindow > 0 && r.deviationBps > 0, "not configured");

        // Reference price from Uniswap TWAP (Q64.96)
        uint256 refX96 = aggregator.twapPriceX96(r.twapWindow);
        emit Finalized(roundId, refX96);

        uint256 n = r.participants.length;
        for (uint256 i = 0; i < n; ++i) {
            address op = r.participants[i];
            int256 pred = r.reveals[op];

            if (pred == int256(0)) {
                // missed reveal
                _slash(op, roundId, 0, abi.encodePacked("NO_REVEAL"));
                continue;
            }

            (bool ok, uint256 devBps) = _withinDeviationBps(uint256(pred), refX96, r.deviationBps);
            if (!ok) {
                // out-of-bounds prediction
                _slash(op, roundId, 0, abi.encode(devBps));
            } else {
                rewards.accrue(op, r.rewardPerValid);
            }
        }

        r.finalized = true;
    }

    function _withinDeviationBps(uint256 px, uint256 refx, uint256 maxBps)
        internal
        pure
        returns (bool ok, uint256 devBps)
    {
        if (px == 0 || refx == 0) return (false, type(uint256).max);
        uint256 diff = px > refx ? px - refx : refx - px;
        devBps = (diff * 10_000) / refx;
        ok = (devBps <= maxBps);
    }

    function _slash(address op, uint256 roundId, uint256 amount, bytes memory evidence) internal {
        if (address(slasher) != address(0)) {
            slasher.reportSlash(op, amount, roundId, evidence);
        }
    }

    /// -------------------
    /// Views
    /// -------------------
    function getParticipants(uint256 roundId) external view returns (address[] memory) {
        return _rounds[roundId].participants;
    }

    function getCommit(uint256 roundId, address op) external view returns (bytes32) {
        return _rounds[roundId].commits[op];
    }

    function getReveal(uint256 roundId, address op) external view returns (int256) {
        return _rounds[roundId].reveals[op];
    }
}
