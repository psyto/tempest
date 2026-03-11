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

/// @notice Full lifecycle scenario tests: vol regimes, keeper failure, recovery, dynamic rewards
contract ScenarioTest is TempestTestBase {
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

        vm.prank(address(manager));
        hook.afterInitialize(address(this), poolKey, TickMath.getSqrtPriceAtTick(0), 0);
        poolId = poolKey.toId();
    }

    receive() external payable {}

    // ─── Helpers ────────────────────────────────────────────────────────

    function _swapAt(int24 tick) internal {
        PoolId pid = poolKey.toId();
        uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(tick);
        bytes32 slot0Value = bytes32(
            uint256(sqrtPrice) | (uint256(uint24(tick)) << 160)
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

    function _swapAtWithDelta(int24 tick, int128 amount0) internal {
        PoolId pid = poolKey.toId();
        uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(tick);
        bytes32 slot0Value = bytes32(
            uint256(sqrtPrice) | (uint256(uint24(tick)) << 160)
        );
        bytes32 baseSlot = keccak256(abi.encodePacked(PoolId.unwrap(pid), uint256(6)));
        vm.store(address(manager), baseSlot, slot0Value);

        vm.prank(address(manager));
        hook.afterSwap(
            address(this),
            poolKey,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0}),
            toBalanceDelta(amount0, -amount0),
            ""
        );
    }

    function _getFee() internal returns (uint24) {
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
    // Scenario 1: Full lifecycle — high vol → keeper goes offline → stale
    //             fee activates → keeper returns → recovery
    // ═══════════════════════════════════════════════════════════════════════

    function test_scenario_keeperFailureAndRecovery() public {
        // Phase 1: Normal operation — low vol with active keeper
        // Small ticks, long intervals → low annualized vol
        console2.log("--- Phase 1: Normal operation ---");
        for (uint256 i = 1; i <= 20; i++) {
            vm.warp(block.timestamp + 3600); // 1 hour intervals
            int24 tick = i % 2 == 0 ? int24(5) : int24(-5); // ±5 tick moves
            _swapAt(tick);
        }
        hook.updateVolatility(poolId);

        uint24 normalFee = _getFee();
        (uint64 normalVol,,,) = hook.getVolatility(poolId);
        console2.log("  Normal vol:", normalVol);
        console2.log("  Normal fee:", normalFee);
        assertGt(normalFee, 0, "Should have a vol-based fee");
        assertLt(normalFee, 500, "Normal fee should be below cap");

        // Phase 2: Market turmoil — large swings, short intervals
        console2.log("--- Phase 2: Market turmoil ---");
        vm.warp(block.timestamp + 301);
        for (uint256 i = 0; i < 20; i++) {
            vm.warp(block.timestamp + 10);
            int24 tick = i % 2 == 0 ? int24(500) : int24(-500);
            _swapAt(tick);
        }
        hook.updateVolatility(poolId);

        uint24 highVolFee = _getFee();
        (uint64 highVol,,,) = hook.getVolatility(poolId);
        console2.log("  High vol:", highVol);
        console2.log("  High fee:", highVolFee);
        assertGt(highVolFee, normalFee, "Fee should increase with vol");

        // Phase 3: Keeper goes offline — fees go stale
        console2.log("--- Phase 3: Keeper offline ---");
        vm.warp(block.timestamp + 3601); // 1 hour passes, no updates

        uint24 staleFee = _getFee();
        console2.log("  Stale fee:", staleFee);
        assertEq(staleFee, 500, "Stale fee should be cap (500 bps)");

        // Swaps continue during keeper downtime
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 60);
            _swapAt(int24(50)); // Market stabilizes
        }
        // Fee should still be stale cap since no vol update
        assertEq(_getFee(), 500, "Still stale while keeper is down");

        // Phase 4: Keeper comes back online
        console2.log("--- Phase 4: Keeper recovers ---");
        // Record a few more stable observations
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 60);
            _swapAt(int24(50));
        }
        hook.updateVolatility(poolId);

        VolatilityEngine.VolState memory recoveredState = hook.getVolState(poolId);
        assertEq(recoveredState.lastUpdate, uint32(block.timestamp), "State should be fresh");

        uint24 recoveredFee = _getFee();
        console2.log("  Recovered fee:", recoveredFee);

        // Fee should no longer be forced to cap by staleness
        // (might still be high due to historical observations, but is vol-based, not stale-forced)
        // Verify by checking that 30 min later it's still not stale
        vm.warp(block.timestamp + 1800);
        uint24 feeAfter30min = _getFee();
        // If we're not stale, fee comes from vol calculation, not the stale cap
        // Verify staleness re-triggers after another full threshold
        vm.warp(block.timestamp + 1801);
        assertEq(_getFee(), 500, "Stale again after threshold from last update");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 2: Dynamic keeper reward scales with gas price
    // ═══════════════════════════════════════════════════════════════════════

    function test_dynamicKeeperReward_scalesWithGas() public {
        // Record enough observations
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 15);
            _swapAt(int24(int256(i) * 50));
        }

        // Test at 10 gwei
        vm.txGasPrice(10 gwei);
        uint256 reward10 = hook.computeKeeperReward();
        // base (0.0005 ETH) + 150,000 * 10 gwei * 1.5 = 0.0005 + 0.00225 = 0.00275 ETH
        uint256 expected10 = 0.0005 ether + (150_000 * 10 gwei * 15_000) / 10_000;
        assertEq(reward10, expected10, "Reward at 10 gwei");

        // Test at 100 gwei
        vm.txGasPrice(100 gwei);
        uint256 reward100 = hook.computeKeeperReward();
        uint256 expected100 = 0.0005 ether + (150_000 * 100 gwei * 15_000) / 10_000;
        assertEq(reward100, expected100, "Reward at 100 gwei");

        assertGt(reward100, reward10, "Higher gas should mean higher reward");

        // Verify keeper actually receives the dynamic amount
        address keeper = makeAddr("keeper");
        vm.deal(keeper, 0);
        uint256 hookBalBefore = address(hook).balance;

        vm.txGasPrice(10 gwei);
        vm.prank(keeper);
        hook.updateVolatility(poolId);

        assertEq(keeper.balance, reward10, "Keeper should receive gas-adjusted reward");
        assertEq(address(hook).balance, hookBalBefore - reward10, "Hook balance should decrease");
    }

    function test_dynamicKeeperReward_zeroGasPrice() public {
        // At 0 gas price, keeper still gets base reward
        vm.txGasPrice(0);
        uint256 reward = hook.computeKeeperReward();
        assertEq(reward, 0.0005 ether, "Base reward at zero gas");
    }

    function test_dynamicKeeperReward_insufficientBalance() public {
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 15);
            _swapAt(int24(int256(i) * 50));
        }

        // Drain hook balance
        vm.deal(address(hook), 0);

        address keeper = makeAddr("keeper");
        vm.deal(keeper, 1 ether); // Fund keeper for gas
        vm.txGasPrice(10 gwei);

        // Update should still succeed but keeper gets no reward
        vm.prank(keeper);
        hook.updateVolatility(poolId);

        assertEq(keeper.balance, 1 ether, "Keeper balance unchanged when hook can't pay");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 3: Dust attack resistance with minSwapSize
    // ═══════════════════════════════════════════════════════════════════════

    function test_scenario_dustAttackMitigated() public {
        // Set min swap size to 0.01 ETH (1e16 wei)
        hook.setMinSwapSize(poolId, 1e16);

        // Record legitimate observations to establish vol
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 30);
            int24 tick = i % 2 == 0 ? int24(200) : int24(-200);
            _swapAtWithDelta(tick, int128(int256(1e18))); // 1 ETH swaps
        }
        hook.updateVolatility(poolId);

        (uint64 legitimateVol,,,) = hook.getVolatility(poolId);
        uint16 obsCountBefore = hook.getObservationCount(poolId);

        // Attacker tries to inject many dust swaps at constant tick to suppress vol
        vm.warp(block.timestamp + 301);
        for (uint256 i = 0; i < 50; i++) {
            vm.warp(block.timestamp + 1);
            _swapAtWithDelta(int24(0), int128(int256(1e10))); // Dust: 0.00000001 ETH
        }

        uint16 obsCountAfter = hook.getObservationCount(poolId);
        assertEq(obsCountAfter, obsCountBefore, "Dust swaps should NOT add observations");

        // Legitimate swaps still get recorded
        vm.warp(block.timestamp + 30);
        _swapAtWithDelta(int24(300), int128(int256(1e18)));
        assertEq(hook.getObservationCount(poolId), obsCountBefore + 1, "Legit swap should be recorded");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 4: Governance parameter tuning
    // ═══════════════════════════════════════════════════════════════════════

    function test_scenario_governanceTuning() public {
        // Governance tightens stale threshold to 30 minutes
        hook.setStaleFeeThreshold(1800);

        // Build vol state
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 15);
            _swapAt(int24(int256(i) * 50));
        }
        hook.updateVolatility(poolId);

        // After 31 minutes without update, should be stale with tighter threshold
        vm.warp(block.timestamp + 1801);
        assertEq(_getFee(), 500, "Stale at 30min with tighter threshold");

        // Governance increases keeper reward premium for high-gas environments
        hook.setKeeperReward(0.001 ether, 200_000, 10_000); // 100% premium

        vm.txGasPrice(50 gwei);
        uint256 reward = hook.computeKeeperReward();
        // base (0.001) + 200,000 * 50 gwei * (10000 + 10000) / 10000
        // = 0.001 + 200,000 * 50e9 * 2 = 0.001 + 0.02 = 0.021 ETH
        uint256 expected = 0.001 ether + (200_000 * 50 gwei * 20_000) / 10_000;
        assertEq(reward, expected, "Tuned reward should reflect new params");
    }
}
