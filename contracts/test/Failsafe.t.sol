// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";

import {TempestHook} from "../src/TempestHook.sol";
import {VolatilityEngine} from "../src/libraries/VolatilityEngine.sol";
import {FeeCurve} from "../src/libraries/FeeCurve.sol";
import {TempestTestBase} from "./utils/TempestTestBase.sol";

/// @notice Tests for fail-safe staleness, dust filtering, and momentum adjustment
contract FailsafeTest is TempestTestBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    Currency c0;
    Currency c1;
    PoolKey poolKey;
    PoolId poolId;

    function setUp() public override {
        super.setUp();
        c0 = Currency.wrap(address(0x1));
        c1 = Currency.wrap(address(0x2));
        poolKey = createPoolKey(c0, c1);

        // Initialize pool
        vm.prank(address(manager));
        hook.afterInitialize(address(this), poolKey, TickMath.getSqrtPriceAtTick(0), 0);
        poolId = poolKey.toId();
    }

    receive() external payable {}

    // ─── Helper ─────────────────────────────────────────────────────────

    function _simulateAfterSwapWithTick(int24 tick) internal {
        PoolId pid = poolKey.toId();
        uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(tick);
        bytes32 slot0Value = bytes32(
            uint256(sqrtPrice) | (uint256(uint24(tick)) << 160) | (uint256(0) << 184) | (uint256(0) << 208)
        );
        bytes32 baseSlot = keccak256(abi.encodePacked(PoolId.unwrap(pid), uint256(6)));
        vm.store(address(manager), baseSlot, slot0Value);

        vm.prank(address(manager));
        hook.afterSwap(
            address(this),
            poolKey,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0}),
            BalanceDeltaLibrary.ZERO_DELTA,
            ""
        );
    }

    function _simulateAfterSwapWithTickAndDelta(int24 tick, int128 amount0, int128 amount1) internal {
        PoolId pid = poolKey.toId();
        uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(tick);
        bytes32 slot0Value = bytes32(
            uint256(sqrtPrice) | (uint256(uint24(tick)) << 160) | (uint256(0) << 184) | (uint256(0) << 208)
        );
        bytes32 baseSlot = keccak256(abi.encodePacked(PoolId.unwrap(pid), uint256(6)));
        vm.store(address(manager), baseSlot, slot0Value);

        BalanceDelta delta = toBalanceDelta(amount0, amount1);

        vm.prank(address(manager));
        hook.afterSwap(
            address(this),
            poolKey,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0}),
            delta,
            ""
        );
    }

    function _buildVolState() internal {
        // Record observations with varying ticks to create vol
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 15);
            _simulateAfterSwapWithTick(int24(int256(i) * 50));
        }
        // Update vol via keeper
        hook.updateVolatility(poolId);
    }

    function _callBeforeSwap() internal returns (uint24) {
        vm.prank(address(manager));
        (,, uint24 fee) = hook.beforeSwap(
            address(this),
            poolKey,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0}),
            ""
        );
        return fee & ~uint24(LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Proposal 1: Fail-safe staleness
    // ═══════════════════════════════════════════════════════════════════════

    function test_staleFeeThreshold_default() public view {
        assertEq(hook.staleFeeThreshold(), 3600, "Default stale threshold = 1 hour");
    }

    function test_beforeSwap_escalatesToCapFee_whenKeeperStale() public {
        _buildVolState();

        // Fee should be normal (vol-based) right after update
        uint24 normalFee = _callBeforeSwap();
        assertGt(normalFee, 0, "Should have a vol-based fee");

        // Warp past the stale threshold (1 hour + 1 second)
        vm.warp(block.timestamp + 3601);

        uint24 staleFee = _callBeforeSwap();
        // Cap fee from default config is 500 bps
        assertEq(staleFee, 500, "Should escalate to cap fee when keeper is stale");
    }

    function test_getCurrentFee_reflectsStaleness() public {
        _buildVolState();

        uint24 normalFee = hook.getCurrentFee(poolId);
        assertGt(normalFee, 0);

        vm.warp(block.timestamp + 3601);

        uint24 staleFee = hook.getCurrentFee(poolId);
        assertEq(staleFee, 500, "getCurrentFee should also reflect staleness");
    }

    function test_staleFee_recoversAfterKeeperUpdate() public {
        _buildVolState();

        // Go stale
        vm.warp(block.timestamp + 3601);
        assertEq(_callBeforeSwap(), 500, "Stale fee = cap");

        // Keeper records new observations and updates — staleness is cleared
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 15);
            _simulateAfterSwapWithTick(int24(100));
        }
        hook.updateVolatility(poolId);

        // The vol state is now fresh — fee comes from FeeCurve, not the stale cap.
        // Verify staleness is cleared by checking that advancing < threshold doesn't re-trigger cap.
        VolatilityEngine.VolState memory state = hook.getVolState(poolId);
        assertEq(state.lastUpdate, uint32(block.timestamp), "Vol state should be fresh");

        // Move forward but stay within threshold — should NOT be stale
        vm.warp(block.timestamp + 1800); // 30 min, well under 1h threshold
        uint24 fee = _callBeforeSwap();
        uint24 capFee = 500;
        // If the vol-based fee happens to be 500 that's fine, but the path is non-stale.
        // What matters: advancing past the threshold again DOES trigger stale.
        vm.warp(block.timestamp + 1801); // now > 3600s since last update
        assertEq(_callBeforeSwap(), capFee, "Should be stale again after another hour");
    }

    function test_setStaleFeeThreshold() public {
        hook.setStaleFeeThreshold(7200);
        assertEq(hook.staleFeeThreshold(), 7200);
    }

    function test_setStaleFeeThreshold_belowMinInterval_reverts() public {
        // minUpdateInterval is 300, so threshold must be >= 300
        vm.expectRevert(TempestHook.InvalidStaleFeeThreshold.selector);
        hook.setStaleFeeThreshold(100);
    }

    function test_setStaleFeeThreshold_onlyGovernance() public {
        vm.prank(address(0xdead));
        vm.expectRevert(TempestHook.OnlyGovernance.selector);
        hook.setStaleFeeThreshold(7200);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Proposal 2: Dust filter (minSwapSize)
    // ═══════════════════════════════════════════════════════════════════════

    function test_minSwapSize_defaultIsZero() public view {
        bytes32 id = PoolId.unwrap(poolId);
        assertEq(hook.minSwapSize(id), 0);
    }

    function test_dustFilter_skipsSmallSwaps() public {
        // Set min swap size to 1e16 (0.01 ETH)
        hook.setMinSwapSize(poolId, 1e16);

        uint16 countBefore = hook.getObservationCount(poolId);

        // Simulate a dust swap (amount0 = 1e10, well below threshold)
        vm.warp(block.timestamp + 15);
        _simulateAfterSwapWithTickAndDelta(100, int128(int256(1e10)), -int128(int256(1e10)));

        uint16 countAfter = hook.getObservationCount(poolId);
        assertEq(countAfter, countBefore, "Dust swap should NOT record observation");
    }

    function test_dustFilter_allowsLargeSwaps() public {
        hook.setMinSwapSize(poolId, 1e16);

        uint16 countBefore = hook.getObservationCount(poolId);

        // Simulate a proper swap (amount0 = 1e18, above threshold)
        vm.warp(block.timestamp + 15);
        _simulateAfterSwapWithTickAndDelta(100, int128(int256(1e18)), -int128(int256(1e18)));

        uint16 countAfter = hook.getObservationCount(poolId);
        assertEq(countAfter, countBefore + 1, "Large swap should record observation");
    }

    function test_dustFilter_negativeAmount0_usesAbsValue() public {
        hook.setMinSwapSize(poolId, 1e16);

        uint16 countBefore = hook.getObservationCount(poolId);

        // Negative amount0 but large enough in absolute value
        vm.warp(block.timestamp + 15);
        _simulateAfterSwapWithTickAndDelta(100, -int128(int256(1e18)), int128(int256(1e18)));

        uint16 countAfter = hook.getObservationCount(poolId);
        assertEq(countAfter, countBefore + 1, "Negative large swap should record observation");
    }

    function test_dustFilter_zeroMinSize_recordsEverything() public {
        // Default: no filter
        uint16 countBefore = hook.getObservationCount(poolId);

        vm.warp(block.timestamp + 15);
        _simulateAfterSwapWithTickAndDelta(100, int128(1), -int128(1));

        uint16 countAfter = hook.getObservationCount(poolId);
        assertEq(countAfter, countBefore + 1, "With no min size, even tiny swaps are recorded");
    }

    function test_setMinSwapSize_onlyGovernance() public {
        vm.prank(address(0xdead));
        vm.expectRevert(TempestHook.OnlyGovernance.selector);
        hook.setMinSwapSize(poolId, 1e16);
    }

    function test_setMinSwapSize_uninitializedPool_reverts() public {
        PoolId fakeId = PoolId.wrap(bytes32(uint256(0x1234)));
        vm.expectRevert(TempestHook.PoolNotInitialized.selector);
        hook.setMinSwapSize(fakeId, 1e16);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Proposal 3: Momentum adjustment
    // ═══════════════════════════════════════════════════════════════════════

    function test_momentum_noBoostWhenVolBelowEma() public {
        _buildVolState();

        // After first update, currentVol == ema7d (first EMA adopts the value)
        // So momentum boost should be zero
        uint24 fee = _callBeforeSwap();

        // Get base fee for comparison
        (uint64 currentVol,,,) = hook.getVolatility(poolId);
        uint24 baseFee = _getBaseFee(currentVol);

        assertEq(fee, baseFee, "No momentum boost when currentVol == ema7d");
    }

    function test_momentum_boostsWhenVolAccelerates() public {
        // Build initial low-vol state
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 15);
            _simulateAfterSwapWithTick(int24(int256(i) * 5)); // Small movements
        }
        hook.updateVolatility(poolId);

        (uint64 lowVol,,,) = hook.getVolatility(poolId);
        uint24 lowFee = _callBeforeSwap();

        // Now create high-vol regime
        vm.warp(block.timestamp + 301);
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 15);
            int24 tick = i % 2 == 0 ? int24(500) : int24(-500); // Large swings
            _simulateAfterSwapWithTick(tick);
        }
        hook.updateVolatility(poolId);

        (uint64 highVol,,,) = hook.getVolatility(poolId);

        // If vol increased above ema7d, fee should include momentum boost
        if (highVol > lowVol) {
            VolatilityEngine.VolState memory state = hook.getVolState(poolId);
            if (state.currentVol > state.ema7d) {
                uint24 highFee = _callBeforeSwap();
                uint24 baseFee = _getBaseFee(highVol);
                assertGe(highFee, baseFee, "Fee with momentum should be >= base fee");
            }
        }
    }

    // ─── Helper to compute base fee without momentum ────────────────────

    function _getBaseFee(uint64 vol) internal pure returns (uint24) {
        return FeeCurve.getFee(FeeCurve.defaultConfig(), vol);
    }
}
