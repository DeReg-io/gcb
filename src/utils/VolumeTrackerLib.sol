// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant MAX_TICKS = 256;
uint256 constant CHANGE_SCALE = 1000;
uint256 constant MIN_EPOCH_LENGTH = 3;
uint24 constant MAX_CHANGE = 0x7fffff;

enum LimiterType {
    Increase,
    Decrease
}

struct Tick {
    bool initialized;
    uint184 pastFlow;
}

struct VTracker {
    uint8 windowTicks;
    uint16 epochLengthMinutes;
    /// @dev Packed (limiter type  1 bit) ++ (max change  23 bits)
    uint24 limiterParams;
    uint24 lastUpdatedEpoch;
    uint184 flow;
    Tick[MAX_TICKS] ticks;
}

/// @author philogy <https://github.com/philogy>
library VolumeTrackerLib {
    error WindowTicksZero();
    error TrackerAlreadyInitialized();
    error EpochsTooShort(uint16 epochLength);
    error TooLargeMaxChange(uint24 maxChange);
    error InvalidLimitedType(LimiterType ltype);

    function init(
        VTracker storage tracker,
        uint8 windowTicks,
        uint16 epochLengthMinutes,
        uint24 maxChange,
        LimiterType ltype
    ) internal {
        if (tracker.windowTicks != 0) revert TrackerAlreadyInitialized();
        if (windowTicks == 0) revert WindowTicksZero();
        if (epochLengthMinutes < MIN_EPOCH_LENGTH) revert EpochsTooShort(epochLengthMinutes);
        uint24 lastUpdatedEpoch = getCurrentEpoch(epochLengthMinutes);
        tracker.windowTicks = windowTicks;
        tracker.epochLengthMinutes = epochLengthMinutes;
        tracker.limiterParams = packLimiterParams(maxChange, ltype);
        tracker.lastUpdatedEpoch = lastUpdatedEpoch;

        // Initialize ticks.
        for (uint256 i; i < windowTicks;) {
            // Ensure tick storage slots are non-zero to minimize user gas overhead.
            tracker.ticks[i].initialized = true;
            // forgefmt: disable-next-item
            unchecked { ++i; }
        }
    }

    function initialized(VTracker storage tracker) internal view returns (bool) {
        return tracker.windowTicks != 0;
    }

    function updateLimited(VTracker storage tracker, uint184 newFlow, uint256 total) internal returns (bool) {
        uint8 windowTicks = tracker.windowTicks;
        uint16 epochLengthMinutes = tracker.epochLengthMinutes;
        uint24 limiterParams = tracker.limiterParams;
        uint24 lastUpdatedEpoch = tracker.lastUpdatedEpoch;
        uint184 flow = tracker.flow;

        uint24 currentEpoch = getCurrentEpoch(epochLengthMinutes);

        // Update past epochs if moved epoch.
        if (currentEpoch > lastUpdatedEpoch) {
            // Cap resets to one full round of the ticks. Prevents uncapped gas use.
            uint24 resetEndEpoch =
                (currentEpoch - lastUpdatedEpoch >= windowTicks ? lastUpdatedEpoch + windowTicks : currentEpoch) + 1;

            for (uint256 epoch = lastUpdatedEpoch + 1; epoch < resetEndEpoch;) {
                flow -= tracker.ticks[epoch % windowTicks].pastFlow;
                tracker.ticks[epoch % windowTicks].pastFlow = 0;
                // forgefmt: disable-next-item
                unchecked { ++epoch; }
            }
        }

        flow += newFlow;
        tracker.ticks[currentEpoch % windowTicks].pastFlow += newFlow;

        (uint24 maxChange, LimiterType ltype) = unpackLimiterParams(limiterParams);

        tracker.lastUpdatedEpoch = currentEpoch;
        tracker.flow = flow;

        if (ltype == LimiterType.Increase) {
            return total * CHANGE_SCALE <= (total - flow) * maxChange;
        } else if (ltype == LimiterType.Decrease) {
            return total * CHANGE_SCALE >= (total + flow) * maxChange;
        } else {
            revert InvalidLimitedType(ltype);
        }
    }

    function getFlow(VTracker storage tracker) internal view returns (uint256) {
        uint8 windowTicks = tracker.windowTicks;
        uint16 epochLengthMinutes = tracker.epochLengthMinutes;
        uint24 lastUpdatedEpoch = tracker.lastUpdatedEpoch;
        uint184 flow = tracker.flow;

        uint24 currentEpoch = getCurrentEpoch(epochLengthMinutes);

        // Update past epochs if moved epoch.
        if (currentEpoch > lastUpdatedEpoch) {
            // Cap resets to one full round of the ticks. Prevents uncapped gas use.
            uint24 resetEndEpoch =
                (currentEpoch - lastUpdatedEpoch >= windowTicks ? lastUpdatedEpoch + windowTicks : currentEpoch) + 1;

            for (uint256 epoch = lastUpdatedEpoch + 1; epoch < resetEndEpoch;) {
                flow -= tracker.ticks[epoch % windowTicks].pastFlow;
                // forgefmt: disable-next-item
                unchecked { ++epoch; }
            }
        }

        return flow;
    }

    function getCurrentEpoch(uint16 epochLengthMinutes) internal view returns (uint24) {
        return uint24(block.timestamp / (epochLengthMinutes * 1 minutes));
    }

    function packLimiterParams(uint24 maxChange, LimiterType ltype) internal pure returns (uint24) {
        if (maxChange > MAX_CHANGE) revert TooLargeMaxChange(maxChange);
        return ((ltype == LimiterType.Increase ? 0 : 1) << 23) | maxChange;
    }

    function unpackLimiterParams(uint24 limiterParams) internal pure returns (uint24 maxChange, LimiterType ltype) {
        maxChange = limiterParams & MAX_CHANGE;
        ltype = ((limiterParams >> 23) == 0) ? LimiterType.Increase : LimiterType.Decrease;
    }
}
