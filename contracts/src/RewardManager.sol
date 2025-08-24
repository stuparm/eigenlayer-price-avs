// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

contract RewardManager {
    using SafeTransferLib for address;

    IERC20 public immutable REWARD_TOKEN;
    address public owner;
    address public avs; // authorized caller

    mapping(address => uint256) public accrued;

    event Funded(uint256 amount);
    event Accrued(address indexed operator, uint256 amount);
    event Claimed(address indexed operator, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address token) {
        require(token != address(0), "token=0");
        REWARD_TOKEN = IERC20(token);
        owner = msg.sender;
    }

    modifier onlyAVS() {
        require(msg.sender == avs, "not avs");
        _;
    }

    function setAVS(address _avs) external onlyOwner {
        require(_avs != address(0), "zero");
        avs = _avs;
    }

    function fund(uint256 amount) external {
        address(address(REWARD_TOKEN)).safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(amount);
    }

    function accrue(address operator, uint256 amount) external onlyAVS {
        accrued[operator] += amount;
        emit Accrued(operator, amount);
    }

    function claim() external {
        uint256 a = accrued[msg.sender];
        require(a > 0, "nothing to claim");
        accrued[msg.sender] = 0;
        address(address(REWARD_TOKEN)).safeTransfer(msg.sender, a);
        emit Claimed(msg.sender, a);
    }
}
