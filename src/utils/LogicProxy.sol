// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @author philogy <https://github.com/philogy>
contract LogicProxy {
    /**
     * @dev ERC1967 implementation slot: `keccak256("eip1967.proxy.implementation") - 1`
     * Layout (data after implementation address considered "auxiliary"):
     * [  0-159] address implementation
     * [    160] "bit"   redirecting ETH (0 = disabled, 1 = enabled )
     * [    161] "bit"   app paused      (0 = paused,   1 = unpaused)
     */
    bytes32 internal constant _CORE_DATA_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint256 internal constant _ETH_REDIRECT_DISABLED_FLAG = 0x010000000000000000000000000000000000000000;
    uint256 internal constant _NOT_PAUSED_FLAG = 0x020000000000000000000000000000000000000000;
    // Core data that cannot be touched by implementation (implementation, redirect enabled/disabled).
    uint256 internal constant _INTEGRAL_DATA_MASK = 0x01ffffffffffffffffffffffffffffffffffffffff;
    uint256 internal constant _IMPL_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;
    uint256 internal constant _AUX_ONLY_MASK = 0xffffffffffffffffffffffff0000000000000000000000000000000000000000;

    address internal immutable BREAKER;

    error CallWhilePaused();
    error BreakerDisabled();
    error RootFlagsChanged();

    event Paused();
    event Unpaused();
    event EthRelayDisabled();
    event Upgraded(address indexed newImplementation);

    constructor(address startImplementation, address breaker) {
        BREAKER = breaker;
        assembly {
            sstore(_CORE_DATA_SLOT, or(startImplementation, _NOT_PAUSED_FLAG))
        }
    }

    /**
     * @dev Reroutes call to implementation if caller not `BREAKER`. Allows use of same selector for
     * other functions
     */
    modifier onlyBreaker() {
        if (msg.sender != BREAKER) {
            _delegateToImpl();
        } else {
            _;
        }
    }

    /**
     * @dev Allows `onlyBreaker` methods to accept and forward ETH to implementation while still
     * reverting if breaker calls with ETH.
     */
    modifier actuallyNonPayable() {
        assembly {
            if callvalue() { revert(0, 0) }
        }
        _;
    }

    receive() external payable {
        _delegateToImpl();
    }

    fallback() external payable {
        _delegateToImpl();
    }

    /**
     * @dev Allows `BREAKER` to upg
     */
    function upgradeTo(address implementation) external payable onlyBreaker actuallyNonPayable {
        assembly {
            let coreData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, or(and(coreData, _AUX_ONLY_MASK), implementation))
        }
        emit Upgraded(implementation);
    }

    function disableEthRelay() external payable onlyBreaker actuallyNonPayable {
        assembly {
            let currentImplData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, or(currentImplData, _ETH_REDIRECT_DISABLED_FLAG))
        }
        emit EthRelayDisabled();
    }

    function getProxyInfo()
        external
        view
        returns (bool paused, bool breakerEnabled, address implementation, address breaker)
    {
        breaker = BREAKER;
        assembly {
            let coreData := sload(_CORE_DATA_SLOT)
            paused := iszero(and(coreData, _NOT_PAUSED_FLAG))
            breakerEnabled := iszero(and(coreData, _ETH_REDIRECT_DISABLED_FLAG))
            implementation := coreData
        }
    }

    function pause() external payable onlyBreaker actuallyNonPayable {
        assembly {
            let prevCoreData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, and(prevCoreData, not(_NOT_PAUSED_FLAG)))
        }
        emit Paused();
    }

    function unpause() external payable onlyBreaker actuallyNonPayable {
        assembly {
            let prevCoreData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, or(prevCoreData, _NOT_PAUSED_FLAG))
        }
        emit Unpaused();
    }

    /// @dev Forwards calldata, asset layer address and auxiliary data to the implementation sending
    //any ETH to the `BREAKER`.
    function _delegateToImpl() internal {
        // Store immutable locally since immutables not supported in assembly.
        address breaker = BREAKER;
        assembly {
            let coreData := sload(_CORE_DATA_SLOT)

            if iszero(and(coreData, _NOT_PAUSED_FLAG)) {
                // `revert CallWhilePaused()`
                mstore(0x00, 0xa44edd3f)
                revert(0x1c, 0x04)
            }

            // Send ETH to breaker for safe keeping if active and callvalue passed.
            if iszero(or(iszero(callvalue()), and(coreData, _ETH_REDIRECT_DISABLED_FLAG))) {
                pop(call(gas(), breaker, callvalue(), 0, 0, 0, 0))
            }
            // Copy calldata to memory.
            calldatacopy(0x00, 0x00, calldatasize())
            // Append asset layer and auxiliary data as an immutable arg.
            mstore(calldatasize(), or(and(coreData, _AUX_ONLY_MASK), breaker))

            // Implementation can't unpause because it won't be called in the first place if paused.
            let success := delegatecall(gas(), coreData, 0x00, add(calldatasize(), 0x20), 0x00, 0x00)

            // Ensure that implementation didn't change integral core data.
            if iszero(eq(and(sload(_CORE_DATA_SLOT), _INTEGRAL_DATA_MASK), and(coreData, _INTEGRAL_DATA_MASK))) {
                // `revert RootFlagsChanged()`
                mstore(0x00, 0xe9df817e)
                revert(0x1c, 0x04)
            }

            // Relay return data to caller.
            returndatacopy(0x00, 0x00, returndatasize())
            if iszero(success) { revert(0x00, returndatasize()) }
            return(0x00, returndatasize())
        }
    }
}
