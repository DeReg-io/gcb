// SPDX-License-Identifier: GPL-3.0-Only
pragma solidity 0.8.15;

import {IERC1155} from "@openzeppelin/token/ERC1155/IERC1155.sol";

interface ICircuitBreaker is IERC1155 {
    enum GCBState {
        Running, // Circuit breaker is active and processing withdrawals
        FrozenResolved, // Contract paused, but pending withdrawals marked and differentiated
        LockedDown // Contract paused, pending withdrawals not settled
    }

    enum ReentrancyLock {
        Uninitialized,
        Unlocked,
        Locked
    }

    enum TriggerAuth {
        Factory,
        OnlyOwner,
        Other
    }

    function state() external view returns (GCBState);

    function queueETHTransfer(address payable recipient, uint256 amount) external returns (uint256);

    function queueERC20Transfer(
        address token,
        address recipient,
        uint256 amount
    ) external returns (uint256);

    function queuePayableCall(
        address payable recipient,
        uint256 amount,
        bytes calldata data
    ) external returns (uint256);

    function queueCall(
        address payable recipient,
        uint256 amount,
        bytes calldata data
    ) external returns (uint256);
}
