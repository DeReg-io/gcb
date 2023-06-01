// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {CircuitConsumer} from "gcb/CircuitConsumer.sol";
import {CircuitTransferLib} from "gcb/utils/CircuitTransferLib.sol";

/// @author philogy <https://github.com/philogy>
contract Example is CircuitConsumer {
    using CircuitTransferLib for address;

    mapping(address => uint256) public balance;

    address public immutable token;

    constructor(address circuitBreaker, address token_) CircuitConsumer(circuitBreaker) {
        token = token_;
    }

    function deposit(uint256 amount) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        balance[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        balance[msg.sender] -= amount;
        token.safeTransfer(msg.sender, amount);
    }
}
