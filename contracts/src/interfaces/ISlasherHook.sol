// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal hook to call EigenLayer's slasher.
/// In production, this contract verifies AVS evidence (roundId, deviation, etc.)
/// and forwards to EigenLayer middleware slashing entrypoints.
interface ISlasherHook {
    function reportSlash(address operator, uint256 amount, uint256 roundId, bytes calldata evidence) external;
}