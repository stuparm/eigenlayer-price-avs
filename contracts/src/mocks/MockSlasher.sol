// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISlasherHook} from "../interfaces/ISlasherHook.sol";

contract MockSlasher is ISlasherHook {
    event Reported(address operator, uint256 amount, uint256 roundId, bytes evidence);

    address public lastOp;
    uint256 public lastAmt;
    uint256 public lastRound;
    bytes public lastEvidence;
    uint256 public reports;

    function reportSlash(
        address operator,
        uint256 amount,
        uint256 roundId,
        bytes calldata evidence
    ) external {
        lastOp = operator;
        lastAmt = amount;
        lastRound = roundId;
        lastEvidence = evidence;
        reports += 1;
        emit Reported(operator, amount, roundId, evidence);
    }
}
