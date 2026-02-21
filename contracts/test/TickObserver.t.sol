// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TickObserver} from "../src/libraries/TickObserver.sol";

/// @dev Wrapper contract to test library with storage
contract TickObserverHarness {
    using TickObserver for TickObserver.ObservationBuffer;

    TickObserver.ObservationBuffer public buffer;

    function record(int24 tick, uint32 timestamp) external {
        buffer.record(tick, timestamp);
    }

    function get(uint16 index) external view returns (int24 tick, uint32 timestamp) {
        return buffer.get(index);
    }

    function latest() external view returns (int24 tick, uint32 timestamp) {
        return buffer.latest();
    }

    function getRange(uint16 from, uint16 rangeCount)
        external
        view
        returns (int24[] memory ticks, uint32[] memory timestamps)
    {
        return buffer.getRange(from, rangeCount);
    }

    function length() external view returns (uint16) {
        return buffer.length();
    }

    function head() external view returns (uint16) {
        return buffer.head;
    }

    function count() external view returns (uint16) {
        return buffer.count;
    }
}

contract TickObserverTest is Test {
    TickObserverHarness harness;

    function setUp() public {
        harness = new TickObserverHarness();
    }

    function test_emptyBuffer_reverts() public {
        vm.expectRevert(TickObserver.BufferEmpty.selector);
        harness.get(0);

        vm.expectRevert(TickObserver.BufferEmpty.selector);
        harness.latest();
    }

    function test_recordSingle() public {
        harness.record(100, 1000);

        assertEq(harness.length(), 1);
        (int24 tick, uint32 ts) = harness.get(0);
        assertEq(tick, 100);
        assertEq(ts, 1000);
    }

    function test_recordMultiple() public {
        harness.record(100, 1000);
        harness.record(200, 2000);
        harness.record(-300, 3000);

        assertEq(harness.length(), 3);

        (int24 tick0, uint32 ts0) = harness.get(0);
        assertEq(tick0, 100);
        assertEq(ts0, 1000);

        (int24 tick1, uint32 ts1) = harness.get(1);
        assertEq(tick1, 200);
        assertEq(ts1, 2000);

        (int24 tick2, uint32 ts2) = harness.get(2);
        assertEq(tick2, -300);
        assertEq(ts2, 3000);
    }

    function test_negativeTick() public {
        harness.record(-8388608, 1000); // min int24
        (int24 tick, uint32 ts) = harness.get(0);
        assertEq(tick, -8388608);
        assertEq(ts, 1000);
    }

    function test_positiveTick() public {
        harness.record(8388607, 1000); // max int24
        (int24 tick, uint32 ts) = harness.get(0);
        assertEq(tick, 8388607);
        assertEq(ts, 1000);
    }

    function test_latest() public {
        harness.record(100, 1000);
        harness.record(200, 2000);
        harness.record(300, 3000);

        (int24 tick, uint32 ts) = harness.latest();
        assertEq(tick, 300);
        assertEq(ts, 3000);
    }

    function test_getRange() public {
        harness.record(100, 1000);
        harness.record(200, 2000);
        harness.record(300, 3000);
        harness.record(400, 4000);

        (int24[] memory ticks, uint32[] memory timestamps) = harness.getRange(1, 2);
        assertEq(ticks.length, 2);
        assertEq(ticks[0], 200);
        assertEq(ticks[1], 300);
        assertEq(timestamps[0], 2000);
        assertEq(timestamps[1], 3000);
    }

    function test_getRange_outOfBounds_reverts() public {
        harness.record(100, 1000);
        harness.record(200, 2000);

        vm.expectRevert(TickObserver.IndexOutOfBounds.selector);
        harness.getRange(0, 3);
    }

    function test_packing_fourObsPerSlot() public {
        // Record exactly 4 observations — should use 1 slot
        harness.record(10, 100);
        harness.record(20, 200);
        harness.record(30, 300);
        harness.record(40, 400);

        assertEq(harness.length(), 4);

        (int24 t0,) = harness.get(0);
        (int24 t1,) = harness.get(1);
        (int24 t2,) = harness.get(2);
        (int24 t3,) = harness.get(3);

        assertEq(t0, 10);
        assertEq(t1, 20);
        assertEq(t2, 30);
        assertEq(t3, 40);
    }

    function test_bufferWrapAround() public {
        // Fill entire buffer (1024 entries) then add one more
        for (uint16 i = 0; i < 1024; i++) {
            harness.record(int24(int16(i)), uint32(i * 15));
        }
        assertEq(harness.length(), 1024);

        // Add one more — overwrites oldest
        harness.record(9999, 1024 * 15);
        assertEq(harness.length(), 1024); // Still 1024

        // The oldest should now be index 1 from original (index 0 was overwritten)
        (int24 oldest, uint32 oldestTs) = harness.get(0);
        assertEq(oldest, 1); // Was i=1
        assertEq(oldestTs, 15);

        // The newest should be our 9999
        (int24 newest, uint32 newestTs) = harness.latest();
        assertEq(newest, 9999);
        assertEq(newestTs, 1024 * 15);
    }

    function test_indexOutOfBounds_reverts() public {
        harness.record(100, 1000);

        vm.expectRevert(TickObserver.IndexOutOfBounds.selector);
        harness.get(1);
    }

    function test_gasRecord() public {
        // First record (cold slot write)
        uint256 gasStart = gasleft();
        harness.record(100, 1000);
        uint256 gasUsed = gasStart - gasleft();
        // First write includes cold SSTORE overhead, should still be reasonable
        assertLt(gasUsed, 100_000);

        // Second through fourth records (same slot, warm)
        gasStart = gasleft();
        harness.record(200, 2000);
        gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 50_000);
    }

    function test_fuzz_recordAndRetrieve(int24 tick, uint32 timestamp) public {
        harness.record(tick, timestamp);
        (int24 retrieved, uint32 retrievedTs) = harness.get(0);
        assertEq(retrieved, tick);
        assertEq(retrievedTs, timestamp);
    }
}
