// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title TickObserver — Gas-optimized circular buffer for tick observations
/// @notice Packs 4 observations per storage slot for ~5,200 gas per write
/// @dev Each observation uses 56 bits (32-bit timestamp + 24-bit tick),
///      so 4 fit in 224 bits of a 256-bit slot with 32 bits spare.
library TickObserver {
    uint16 constant BUFFER_SIZE = 1024;
    uint8 constant OBS_PER_SLOT = 4;
    uint16 constant NUM_SLOTS = BUFFER_SIZE / uint16(OBS_PER_SLOT); // 256

    uint256 constant TICK_MASK = 0xFFFFFF; // 24 bits
    uint256 constant TIMESTAMP_MASK = 0xFFFFFFFF; // 32 bits
    uint256 constant OBS_BITS = 56;

    error BufferEmpty();
    error IndexOutOfBounds();

    struct ObservationBuffer {
        uint16 head; // Next write position (0..1023)
        uint16 count; // Total observations recorded (saturates at BUFFER_SIZE)
        mapping(uint256 => uint256) slots; // Packed storage slots
    }

    /// @notice Record a new tick observation
    /// @param self The observation buffer
    /// @param tick The pool tick to record (-8388608 to 8388607, fits in int24)
    /// @param timestamp The block timestamp (fits in uint32 until year 2106)
    function record(ObservationBuffer storage self, int24 tick, uint32 timestamp) internal {
        uint16 pos = self.head;
        uint16 slotIndex = pos / uint16(OBS_PER_SLOT);
        uint8 obsIndex = uint8(pos % uint16(OBS_PER_SLOT));

        // Pack: [24-bit tick (as uint24)][32-bit timestamp] = 56 bits
        uint256 packed = (uint256(uint24(tick)) << 32) | uint256(timestamp);

        // Load existing slot, clear the target observation, write new one
        uint256 slot = self.slots[slotIndex];
        uint256 shift = uint256(obsIndex) * OBS_BITS;
        uint256 mask = ~(((1 << OBS_BITS) - 1) << shift);
        slot = (slot & mask) | (packed << shift);
        self.slots[slotIndex] = slot;

        // Advance head (circular)
        self.head = (pos + 1) % BUFFER_SIZE;

        // Track count (saturates at BUFFER_SIZE)
        if (self.count < BUFFER_SIZE) {
            self.count = self.count + 1;
        }
    }

    /// @notice Get a single observation by logical index (0 = oldest available)
    /// @param self The observation buffer
    /// @param index Logical index from oldest (0) to newest (count-1)
    /// @return tick The recorded tick
    /// @return timestamp The recorded timestamp
    function get(ObservationBuffer storage self, uint16 index) internal view returns (int24 tick, uint32 timestamp) {
        uint16 count = self.count;
        if (count == 0) revert BufferEmpty();
        if (index >= count) revert IndexOutOfBounds();

        // Physical position: if buffer has wrapped, oldest is at head; otherwise at 0
        uint16 physicalIndex;
        if (count == BUFFER_SIZE) {
            physicalIndex = (self.head + index) % BUFFER_SIZE;
        } else {
            physicalIndex = index;
        }

        uint16 slotIndex = physicalIndex / uint16(OBS_PER_SLOT);
        uint8 obsIndex = uint8(physicalIndex % uint16(OBS_PER_SLOT));

        uint256 slot = self.slots[slotIndex];
        uint256 shift = uint256(obsIndex) * OBS_BITS;
        uint256 packed = (slot >> shift) & ((1 << OBS_BITS) - 1);

        timestamp = uint32(packed & TIMESTAMP_MASK);
        tick = int24(uint24((packed >> 32) & TICK_MASK));
    }

    /// @notice Get the most recent observation
    /// @param self The observation buffer
    /// @return tick The most recent tick
    /// @return timestamp The most recent timestamp
    function latest(ObservationBuffer storage self) internal view returns (int24 tick, uint32 timestamp) {
        uint16 count = self.count;
        if (count == 0) revert BufferEmpty();
        return get(self, count - 1);
    }

    /// @notice Get a range of observations for vol computation
    /// @param self The observation buffer
    /// @param from Start logical index (inclusive)
    /// @param rangeCount Number of observations to retrieve
    /// @return ticks Array of tick values
    /// @return timestamps Array of timestamps
    function getRange(
        ObservationBuffer storage self,
        uint16 from,
        uint16 rangeCount
    ) internal view returns (int24[] memory ticks, uint32[] memory timestamps) {
        uint16 count = self.count;
        if (from + rangeCount > count) revert IndexOutOfBounds();

        ticks = new int24[](rangeCount);
        timestamps = new uint32[](rangeCount);

        for (uint16 i = 0; i < rangeCount; i++) {
            (ticks[i], timestamps[i]) = get(self, from + i);
        }
    }

    /// @notice Get the number of observations stored
    function length(ObservationBuffer storage self) internal view returns (uint16) {
        return self.count;
    }
}
