// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";

import {TempestHook} from "../src/TempestHook.sol";
import {VolatilityEngine} from "../src/libraries/VolatilityEngine.sol";
import {FeeCurve} from "../src/libraries/FeeCurve.sol";
import {TickObserver} from "../src/libraries/TickObserver.sol";
import {TempestTestBase} from "./utils/TempestTestBase.sol";

/// @notice Integration tests for the full Tempest hook lifecycle
contract IntegrationTest is TempestTestBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function _simulateAfterInitialize(PoolKey memory key, int24 tick) internal {
        vm.prank(address(manager));
        hook.afterInitialize(address(this), key, TickMath.getSqrtPriceAtTick(tick), tick);
    }

    function _zeroDelta() internal pure returns (BalanceDelta) {
        return BalanceDeltaLibrary.ZERO_DELTA;
    }

    /// @dev Simulate afterSwap by directly recording ticks through the hook
    ///      We prank as the PoolManager and mock getSlot0 to return varying ticks
    function _simulateAfterSwapWithTick(PoolKey memory key, int24 tick) internal {
        // Mock the extsload that StateLibrary.getSlot0 uses
        // StateLibrary.getSlot0 calls manager.extsload(keccak256(poolId, POOLS_SLOT))
        // We can mock this via vm.mockCall on the manager's extsload
        PoolId poolId = key.toId();

        // Pack the Slot0 data the way StateLibrary expects
        uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(tick);
        // Slot0 packing: sqrtPriceX96 || tick || protocolFee || lpFee
        // = 160 bits + 24 bits + 24 bits + 24 bits = 232 bits, packed right-aligned
        bytes32 slot0Value = bytes32(
            uint256(sqrtPrice) | (uint256(uint24(tick)) << 160) | (uint256(0) << 184) | (uint256(0) << 208)
        );

        // The key is: StateLibrary.getSlot0 uses extsload, which reads from a mapping
        // pools[poolId].slot0 in transient-like storage.
        // Rather than figure out the exact storage slot, let's use a simpler approach:
        // Store slot0 data directly in the PoolManager's storage.

        // POOLS_SLOT in PoolManager = 6 (from Pool.State mapping)
        // The pool state slot is at keccak256(abi.encode(poolId, 6))
        // Slot0 is the first field of Pool.State, so it's at that base slot
        bytes32 baseSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), uint256(6)));
        vm.store(address(manager), baseSlot, slot0Value);

        vm.prank(address(manager));
        hook.afterSwap(
            address(this),
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0}),
            _zeroDelta(),
            ""
        );
    }

    // Allow receiving ETH (for keeper reward payout when this contract calls updateVolatility)
    receive() external payable {}

    // ─── Pool Registration ─────────────────────────────────────────────

    function test_afterInitialize_registersPool() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);

        _simulateAfterInitialize(key, 0);

        PoolId poolId = key.toId();
        assertTrue(hook.isPoolInitialized(poolId));
        assertEq(hook.getObservationCount(poolId), 1);
    }

    function test_afterInitialize_cannotReinitialize() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);

        _simulateAfterInitialize(key, 0);

        vm.expectRevert(TempestHook.PoolAlreadyInitialized.selector);
        vm.prank(address(manager));
        hook.afterInitialize(address(this), key, TickMath.getSqrtPriceAtTick(0), 0);
    }

    function test_afterInitialize_nonDynamicFee_reverts() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.expectRevert(TempestHook.PoolMustUseDynamicFee.selector);
        vm.prank(address(manager));
        hook.afterInitialize(address(this), key, TickMath.getSqrtPriceAtTick(0), 0);
    }

    // ─── beforeSwap ────────────────────────────────────────────────────

    function test_beforeSwap_returnsDefaultFee_beforeVolUpdate() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 0);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0});

        vm.prank(address(manager));
        (bytes4 sel,, uint24 fee) = hook.beforeSwap(address(this), key, params, "");

        assertEq(sel, IHooks.beforeSwap.selector);
        assertTrue(fee & LPFeeLibrary.OVERRIDE_FEE_FLAG != 0, "Override flag should be set");
        uint24 actualFee = fee & ~uint24(LPFeeLibrary.OVERRIDE_FEE_FLAG);
        assertEq(actualFee, 30, "Default fee should be 30 bps");
    }

    function test_getCurrentFee_beforeVolUpdate_returnsDefault() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 0);

        uint24 fee = hook.getCurrentFee(key.toId());
        assertEq(fee, 30, "Default fee before vol update");
    }

    // ─── updateVolatility ──────────────────────────────────────────────

    function test_updateVolatility_insufficientObservations() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 0);

        vm.expectRevert(TempestHook.InsufficientObservations.selector);
        hook.updateVolatility(key.toId());
    }

    function test_updateVolatility_tooFrequent() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 0);

        // Record enough observations with varying ticks
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 15);
            _simulateAfterSwapWithTick(key, int24(int256(i) * 10));
        }

        // First update should work (this contract has receive() so can accept reward)
        hook.updateVolatility(key.toId());

        // Second update immediately should fail
        vm.expectRevert(TempestHook.UpdateTooFrequent.selector);
        hook.updateVolatility(key.toId());

        // After waiting minUpdateInterval, should work again
        vm.warp(block.timestamp + 301);
        _simulateAfterSwapWithTick(key, 200);
        hook.updateVolatility(key.toId());
    }

    // ─── Full Lifecycle ────────────────────────────────────────────────

    function test_fullLifecycle_volUpdateChangesFee() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);

        _simulateAfterInitialize(key, 0);
        PoolId poolId = key.toId();

        // Simulate swaps with varying ticks to create vol
        int24[20] memory tickSequence = [
            int24(50), int24(-30), int24(100), int24(-50), int24(80),
            int24(-20), int24(120), int24(-60), int24(90), int24(-40),
            int24(110), int24(-70), int24(60), int24(-10), int24(130),
            int24(-80), int24(70), int24(-30), int24(100), int24(-50)
        ];

        for (uint256 i = 0; i < 20; i++) {
            vm.warp(block.timestamp + 15);
            _simulateAfterSwapWithTick(key, tickSequence[i]);
        }

        assertEq(hook.getObservationCount(poolId), 21);

        // Keeper updates
        address keeper = makeAddr("keeper");
        vm.deal(keeper, 0);

        vm.prank(keeper);
        hook.updateVolatility(poolId);

        (uint64 currentVol,,,) = hook.getVolatility(poolId);
        assertGt(currentVol, 0, "Vol should be computed");

        assertEq(keeper.balance, 0.001 ether, "Keeper should receive reward");

        uint24 fee = hook.getCurrentFee(poolId);
        assertGt(fee, 0, "Fee should be > 0 after vol update");
    }

    function test_getRecommendedRange() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 1000);

        PoolId poolId = key.toId();

        (int24 lower, int24 upper) = hook.getRecommendedRange(poolId, 1000);
        assertEq(lower, 800, "Lower tick for VeryLow regime");
        assertEq(upper, 1200, "Upper tick for VeryLow regime");
    }

    // ─── Fee Config Management ─────────────────────────────────────────

    function test_setFeeConfig() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 0);

        FeeCurve.FeeConfig memory newConfig = FeeCurve.FeeConfig({
            vol0: 0,
            fee0: 10,
            vol1: 1000,
            fee1: 20,
            vol2: 2000,
            fee2: 50,
            vol3: 4000,
            fee3: 100,
            vol4: 6000,
            fee4: 200,
            vol5: 10000,
            fee5: 1000
        });

        hook.setFeeConfig(key.toId(), newConfig);
    }

    function test_setFeeConfig_invalidConfig_reverts() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 0);

        FeeCurve.FeeConfig memory badConfig = FeeCurve.FeeConfig({
            vol0: 5000,
            fee0: 10,
            vol1: 1000,
            fee1: 20,
            vol2: 2000,
            fee2: 50,
            vol3: 4000,
            fee3: 100,
            vol4: 6000,
            fee4: 200,
            vol5: 10000,
            fee5: 1000
        });

        vm.expectRevert(TempestHook.InvalidFeeConfig.selector);
        hook.setFeeConfig(key.toId(), badConfig);
    }

    function test_setFeeConfig_onlyGovernance() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);
        _simulateAfterInitialize(key, 0);

        vm.prank(address(0xdead));
        vm.expectRevert(TempestHook.OnlyGovernance.selector);
        hook.setFeeConfig(key.toId(), FeeCurve.defaultConfig());
    }

    // ─── Access Control ────────────────────────────────────────────────

    function test_onlyPoolManager_beforeSwap() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);

        vm.expectRevert(TempestHook.OnlyPoolManager.selector);
        hook.beforeSwap(
            address(this),
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0}),
            ""
        );
    }

    function test_onlyPoolManager_afterSwap() public {
        Currency c0 = Currency.wrap(address(0x1));
        Currency c1 = Currency.wrap(address(0x2));
        PoolKey memory key = createPoolKey(c0, c1);

        vm.expectRevert(TempestHook.OnlyPoolManager.selector);
        hook.afterSwap(
            address(this),
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0}),
            _zeroDelta(),
            ""
        );
    }
}
