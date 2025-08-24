// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract AVSOperatorRegistry {
    address public owner;
    mapping(address => bool) public isOperator;

    event OperatorRegistered(address indexed op);
    event OperatorUnregistered(address indexed op);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function register(address op) external onlyOwner {
        isOperator[op] = true;
        emit OperatorRegistered(op);
    }

    function unregister(address op) external onlyOwner {
        isOperator[op] = false;
        emit OperatorUnregistered(op);
    }
}
