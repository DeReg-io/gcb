// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
contract LogicProxy {
    /// @dev ERC1967 implementation slot: `keccak256("eip1967.proxy.implementation") - 1`
    /// Layout (data after implementation address considered "auxiliary"):
    /// [  0-159] address implementation
    /// [    160] "bit"   assetLayerActive
    /// [    161] "bit"   app paused
    bytes32 internal constant _CORE_DATA_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint256 internal constant _LAYER_ACTIVE_FLAG = 0x010000000000000000000000000000000000000000;
    uint256 internal constant _APP_ACTIVE_FLAG = 0x020000000000000000000000000000000000000000;
    // Flags that cannot be touched by implementation
    uint256 internal constant _ROOT_FLAGS_MASK = 0x020000000000000000000000000000000000000000;
    uint256 internal constant _AUX_ONLY_MASK = 0xffffffffffffffffffffffff0000000000000000000000000000000000000000;

    address internal immutable assetLayer;

    error Paused();
    error RootFlagChanged();

    event AppPaused();
    event AppUnpaused();

    constructor(address _startImplementation) {
        assetLayer = msg.sender;
        assembly {
            sstore(_CORE_DATA_SLOT, or(_startImplementation, _APP_ACTIVE_FLAG))
        }
    }

    /// @dev Reroutes call to implementation if caller not `assetLayer`
    modifier onlyLayerCallable() {
        if (msg.sender != assetLayer) {
            _delegateToImpl();
        } else {
            _;
        }
    }

    receive() external payable {
        _delegateToImpl();
    }

    fallback() external payable {
        _delegateToImpl();
    }

    /// @dev Sets implementation if caller is `assetLayer`, forwards to
    /// implementation otherwise incase it has its own `upgradeTo` method.
    function upgradeTo(address _newImpl) external payable onlyLayerCallable {
        assembly {
            let currentImplData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, or(and(currentImplData, _AUX_ONLY_MASK), _newImpl))
        }
    }

    function disableAssetLayer() external payable onlyLayerCallable {
        assembly {
            let currentImplData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, and(currentImplData, not(_LAYER_ACTIVE_FLAG)))
        }
    }

    function paused() external view returns (bool) {
        assembly {
            mstore(0x00, iszero(and(sload(_CORE_DATA_SLOT), _APP_ACTIVE_FLAG)))
            return(0x00, 0x20)
        }
    }

    function pauseApp() external payable onlyLayerCallable {
        assembly {
            let prevCoreData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, and(prevCoreData, not(_APP_ACTIVE_FLAG)))
        }
        emit AppPaused();
    }

    function unpauseApp() external payable onlyLayerCallable {
        assembly {
            let prevCoreData := sload(_CORE_DATA_SLOT)
            sstore(_CORE_DATA_SLOT, or(prevCoreData, _APP_ACTIVE_FLAG))
        }
        emit AppUnpaused();
    }

    /// @dev Forwards calldata, asset layer address and auxiliary data to the implementation sending any ETH to the `assetLayer`.
    function _delegateToImpl() internal {
        // Store immutable locally since immutables not supported in assembly.
        address assetLayer_ = assetLayer;
        assembly {
            let coreData := sload(_CORE_DATA_SLOT)

            if iszero(and(coreData, _APP_ACTIVE_FLAG)) {
                // `revert Paused()`
                mstore(0x00, 0x9e87fac8)
                revert(0x1c, 0x04)
            }

            // Send ETH to layer for safe keeping if active and callvalue passed.
            if iszero(or(iszero(callvalue()), and(_APP_ACTIVE_FLAG, coreData))) {
                pop(call(gas(), assetLayer_, callvalue(), 0, 0, 0, 0))
            }
            // Copy calldata to memory.
            calldatacopy(0x00, 0x00, calldatasize())
            // Append asset layer and auxiliary data as an immutable arg.
            mstore(calldatasize(), or(and(coreData, _AUX_ONLY_MASK), assetLayer_))
            let success := delegatecall(gas(), coreData, 0x00, add(calldatasize(), 0x20), 0x00, 0x00)

            // Ensure that implementation didn't change root flags.
            if iszero(eq(and(sload(_CORE_DATA_SLOT), _ROOT_FLAGS_MASK), and(coreData, _ROOT_FLAGS_MASK))) {
                mstore(0x00, 0x0feb2b1a)
                revert(0x1c, 0x04)
            }

            // Relay return data to caller.
            returndatacopy(0x00, 0x00, returndatasize())
            if iszero(success) {
                revert(0x00, returndatasize())
            }
            return(0x00, returndatasize())
        }
    }
}
