// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {ICircuitBreaker} from "./interfaces/ICircuitBreaker.sol";
import {CrispyERC1155} from "./CrispyERC1155.sol";

contract CircuitBreaker is ICircuitBreaker, CrispyERC1155 {}
