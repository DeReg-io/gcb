// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @author philogy <https://github.com/philogy>
contract Example {
    using SafeTransferLib for address;

    mapping(address => uint256) public balance;

    address public immutable token;

    constructor(address token_) {
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
