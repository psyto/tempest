// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VolatilityEngine} from "../src/libraries/VolatilityEngine.sol";

/// @dev Harness to expose library functions as external calls (needed for vm.expectRevert)
contract VolEngineHarness {
    function computeRealizedVol(int24[] memory ticks, uint32[] memory timestamps, uint16 count)
        external
        pure
        returns (uint64)
    {
        return VolatilityEngine.computeRealizedVol(ticks, timestamps, count);
    }
}

contract VolatilityEngineTest is Test {
    VolEngineHarness harness;

    function setUp() public {
        harness = new VolEngineHarness();
    }

    // ─── computeRealizedVol ────────────────────────────────────────────

    function test_computeRealizedVol_insufficientSamples() public {
        int24[] memory ticks = new int24[](1);
        uint32[] memory timestamps = new uint32[](1);
        ticks[0] = 100;
        timestamps[0] = 1000;

        vm.expectRevert(VolatilityEngine.InsufficientSamples.selector);
        harness.computeRealizedVol(ticks, timestamps, 1);
    }

    function test_computeRealizedVol_zeroMovement() public {
        // Same tick at different times = zero vol
        int24[] memory ticks = new int24[](5);
        uint32[] memory timestamps = new uint32[](5);
        for (uint16 i = 0; i < 5; i++) {
            ticks[i] = 1000;
            timestamps[i] = uint32(i * 15);
        }

        uint64 vol = VolatilityEngine.computeRealizedVol(ticks, timestamps, 5);
        assertEq(vol, 0, "Zero movement should produce zero vol");
    }

    function test_computeRealizedVol_constantMovement() public {
        // Constant tick movement: ticks go 0, 10, 20, 30, 40
        // Each delta = 10 ticks, each interval = 15 seconds
        int24[] memory ticks = new int24[](5);
        uint32[] memory timestamps = new uint32[](5);
        for (uint16 i = 0; i < 5; i++) {
            ticks[i] = int24(int16(i)) * 10;
            timestamps[i] = uint32(i * 15);
        }

        uint64 vol = VolatilityEngine.computeRealizedVol(ticks, timestamps, 5);

        // delta = 10 bps, dt = 15s
        // per-second variance = 10^2 / 15 = 100/15 ≈ 6.667
        // annualized variance = 6.667 * 31557600 ≈ 210,384,000
        // annualized vol = sqrt(210,384,000) ≈ 14,504 bps
        // This represents very high vol because we have constant directional movement
        assertGt(vol, 0, "Should have positive vol");
        assertGt(vol, 10000, "Constant movement over short intervals should be high vol");
    }

    function test_computeRealizedVol_lowVol() public {
        // Very small tick movements with long intervals
        // Simulates a quiet market
        int24[] memory ticks = new int24[](10);
        uint32[] memory timestamps = new uint32[](10);
        for (uint16 i = 0; i < 10; i++) {
            ticks[i] = int24(int16(i % 2 == 0 ? int16(0) : int16(1))); // oscillate 0,1
            timestamps[i] = uint32(i * 3600); // 1 hour intervals
        }

        uint64 vol = VolatilityEngine.computeRealizedVol(ticks, timestamps, 10);

        // Small movements over long intervals = low vol
        assertLt(vol, 2000, "Tiny movements should produce low vol");
    }

    function test_computeRealizedVol_highVol() public {
        // Large tick swings at short intervals
        int24[] memory ticks = new int24[](6);
        uint32[] memory timestamps = new uint32[](6);
        ticks[0] = 0;
        timestamps[0] = 0;
        ticks[1] = 500; // +500
        timestamps[1] = 15;
        ticks[2] = -300; // -800
        timestamps[2] = 30;
        ticks[3] = 400; // +700
        timestamps[3] = 45;
        ticks[4] = -200; // -600
        timestamps[4] = 60;
        ticks[5] = 300; // +500
        timestamps[5] = 75;

        uint64 vol = VolatilityEngine.computeRealizedVol(ticks, timestamps, 6);
        assertGt(vol, 7500, "Large swings should produce extreme vol");
    }

    function test_computeRealizedVol_skipZeroTimeIntervals() public {
        // Two observations at the same timestamp
        int24[] memory ticks = new int24[](3);
        uint32[] memory timestamps = new uint32[](3);
        ticks[0] = 100;
        timestamps[0] = 1000;
        ticks[1] = 200;
        timestamps[1] = 1000; // Same timestamp
        ticks[2] = 300;
        timestamps[2] = 2000;

        uint64 vol = VolatilityEngine.computeRealizedVol(ticks, timestamps, 3);
        // Should not revert, just skip the zero-dt pair
        assertGt(vol, 0);
    }

    // ─── classifyRegime ────────────────────────────────────────────────

    function test_classifyRegime_veryLow() public pure {
        assertEq(uint256(VolatilityEngine.classifyRegime(0)), uint256(VolatilityEngine.Regime.VeryLow));
        assertEq(uint256(VolatilityEngine.classifyRegime(1000)), uint256(VolatilityEngine.Regime.VeryLow));
        assertEq(uint256(VolatilityEngine.classifyRegime(2000)), uint256(VolatilityEngine.Regime.VeryLow));
    }

    function test_classifyRegime_low() public pure {
        assertEq(uint256(VolatilityEngine.classifyRegime(2001)), uint256(VolatilityEngine.Regime.Low));
        assertEq(uint256(VolatilityEngine.classifyRegime(3500)), uint256(VolatilityEngine.Regime.Low));
    }

    function test_classifyRegime_normal() public pure {
        assertEq(uint256(VolatilityEngine.classifyRegime(3501)), uint256(VolatilityEngine.Regime.Normal));
        assertEq(uint256(VolatilityEngine.classifyRegime(5000)), uint256(VolatilityEngine.Regime.Normal));
    }

    function test_classifyRegime_high() public pure {
        assertEq(uint256(VolatilityEngine.classifyRegime(5001)), uint256(VolatilityEngine.Regime.High));
        assertEq(uint256(VolatilityEngine.classifyRegime(7500)), uint256(VolatilityEngine.Regime.High));
    }

    function test_classifyRegime_extreme() public pure {
        assertEq(uint256(VolatilityEngine.classifyRegime(7501)), uint256(VolatilityEngine.Regime.Extreme));
        assertEq(uint256(VolatilityEngine.classifyRegime(20000)), uint256(VolatilityEngine.Regime.Extreme));
    }

    // ─── updateEMA ─────────────────────────────────────────────────────

    function test_updateEMA_firstValue() public pure {
        // When currentEma is 0, should return the new value
        uint64 result = VolatilityEngine.updateEMA(0, 5000, 3600, 7 days);
        assertEq(result, 5000);
    }

    function test_updateEMA_noElapsed() public pure {
        uint64 result = VolatilityEngine.updateEMA(3000, 5000, 0, 7 days);
        assertEq(result, 3000, "No time elapsed should keep old value");
    }

    function test_updateEMA_convergence() public pure {
        // Repeated updates with same value should converge toward it
        uint64 ema = 1000;
        for (uint256 i = 0; i < 30; i++) {
            ema = VolatilityEngine.updateEMA(ema, 5000, 1 days, 7 days);
        }
        // After 30 daily updates at 5000 with 7-day half-life, should be very close
        assertGt(ema, 4800, "EMA should converge toward target");
        assertLt(ema, 5100, "EMA should be near target");
    }

    function test_updateEMA_longElapsed_clampsWeight() public pure {
        // Very long elapsed time should clamp weight to 1000 (full weight)
        uint64 result = VolatilityEngine.updateEMA(1000, 5000, 365 days, 7 days);
        assertEq(result, 5000, "Long elapsed should fully weight new value");
    }

    // ─── isElevated / isDepressed ──────────────────────────────────────

    function test_isElevated() public pure {
        VolatilityEngine.VolState memory state;
        state.currentVol = 6000;
        state.ema30d = 3000;
        assertTrue(VolatilityEngine.isElevated(state), "6000 > 1.5 * 3000");

        state.currentVol = 4000;
        assertFalse(VolatilityEngine.isElevated(state), "4000 < 1.5 * 3000");
    }

    function test_isDepressed() public pure {
        VolatilityEngine.VolState memory state;
        state.currentVol = 1000;
        state.ema30d = 4000;
        assertTrue(VolatilityEngine.isDepressed(state), "1000 < 0.5 * 4000");

        state.currentVol = 3000;
        assertFalse(VolatilityEngine.isDepressed(state), "3000 > 0.5 * 4000");
    }

    // ─── updateVolState ────────────────────────────────────────────────

    function test_updateVolState_initialUpdate() public pure {
        VolatilityEngine.VolState memory state;

        int24[] memory ticks = new int24[](5);
        uint32[] memory timestamps = new uint32[](5);
        for (uint16 i = 0; i < 5; i++) {
            ticks[i] = int24(int16(i)) * 5;
            timestamps[i] = uint32(i * 60);
        }

        state = VolatilityEngine.updateVolState(state, ticks, timestamps, 5, 300);

        assertGt(state.currentVol, 0, "Should compute vol");
        assertEq(state.lastUpdate, 300);
        assertEq(state.sampleCount, 5);
        // First update: ema equals current vol
        assertEq(state.ema7d, state.currentVol);
        assertEq(state.ema30d, state.currentVol);
    }

    // ─── sqrt ──────────────────────────────────────────────────────────

    function test_sqrt() public pure {
        assertEq(VolatilityEngine.sqrt(0), 0);
        assertEq(VolatilityEngine.sqrt(1), 1);
        assertEq(VolatilityEngine.sqrt(4), 2);
        assertEq(VolatilityEngine.sqrt(9), 3);
        assertEq(VolatilityEngine.sqrt(100), 10);
        assertEq(VolatilityEngine.sqrt(10000), 100);
        // Large number
        assertEq(VolatilityEngine.sqrt(1e18), 1e9);
    }

    function test_sqrt_fuzz(uint128 x) public pure {
        uint256 root = VolatilityEngine.sqrt(uint256(x));
        // root^2 <= x < (root+1)^2
        assertLe(root * root, uint256(x));
        if (root < type(uint128).max) {
            assertGt((root + 1) * (root + 1), uint256(x));
        }
    }
}
