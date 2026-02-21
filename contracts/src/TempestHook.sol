// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/types/BeforeSwapDelta.sol";

import {TickObserver} from "./libraries/TickObserver.sol";
import {VolatilityEngine} from "./libraries/VolatilityEngine.sol";
import {FeeCurve} from "./libraries/FeeCurve.sol";

/// @title TempestHook — Volatility-responsive dynamic fee hook for Uniswap v4
/// @notice Dynamically adjusts swap fees based on real-time realized volatility
///         computed from pool swap data. Records tick observations on every swap,
///         and a keeper periodically computes vol to determine the fee regime.
contract TempestHook is IHooks {
    using TickObserver for TickObserver.ObservationBuffer;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;

    // ─── Errors ────────────────────────────────────────────────────────────

    error OnlyPoolManager();
    error OnlyGovernance();
    error PoolNotInitialized();
    error PoolAlreadyInitialized();
    error PoolMustUseDynamicFee();
    error UpdateTooFrequent();
    error InsufficientObservations();
    error InvalidFeeConfig();
    error TransferFailed();

    // ─── Events ────────────────────────────────────────────────────────────

    event PoolRegistered(PoolId indexed poolId, int24 initialTick);
    event TickRecorded(PoolId indexed poolId, int24 tick, uint32 timestamp);
    event VolatilityUpdated(
        PoolId indexed poolId,
        uint64 currentVol,
        VolatilityEngine.Regime regime,
        uint24 newFee,
        uint16 sampleCount
    );
    event FeeConfigUpdated(PoolId indexed poolId);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);
    event KeeperRewardUpdated(uint256 newReward);
    event MinUpdateIntervalUpdated(uint32 newInterval);

    // ─── State ─────────────────────────────────────────────────────────────

    struct PoolState {
        TickObserver.ObservationBuffer observations;
        VolatilityEngine.VolState volState;
        FeeCurve.FeeConfig feeConfig;
        bool initialized;
    }

    IPoolManager public immutable manager;
    address public governance;
    uint256 public keeperReward; // Wei reward for calling updateVolatility
    uint32 public minUpdateInterval; // Min seconds between vol updates

    mapping(bytes32 => PoolState) internal _pools;

    // ─── Constructor ───────────────────────────────────────────────────────

    constructor(IPoolManager _manager, address _governance) {
        manager = _manager;
        governance = _governance;
        keeperReward = 0.001 ether;
        minUpdateInterval = 300; // 5 minutes

        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );
    }

    // ─── Modifiers ─────────────────────────────────────────────────────────

    modifier onlyPoolManager() {
        if (msg.sender != address(manager)) revert OnlyPoolManager();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    // ─── Hook Callbacks ────────────────────────────────────────────────────

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) external override onlyPoolManager returns (bytes4) {
        // Pool MUST have been created with DYNAMIC_FEE_FLAG
        if (!key.fee.isDynamicFee()) revert PoolMustUseDynamicFee();

        bytes32 id = PoolId.unwrap(key.toId());
        PoolState storage pool = _pools[id];
        if (pool.initialized) revert PoolAlreadyInitialized();

        pool.initialized = true;
        pool.feeConfig = FeeCurve.defaultConfig();
        pool.observations.record(tick, uint32(block.timestamp));

        emit PoolRegistered(key.toId(), tick);
        return IHooks.afterInitialize.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        bytes32 id = PoolId.unwrap(key.toId());
        PoolState storage pool = _pools[id];

        uint24 fee;
        if (pool.initialized && pool.volState.lastUpdate > 0) {
            fee = FeeCurve.getFee(pool.feeConfig, pool.volState.currentVol);
        } else {
            // Default fee before first vol update
            fee = 30; // 0.30%
        }

        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        bytes32 id = PoolId.unwrap(key.toId());
        PoolState storage pool = _pools[id];

        if (pool.initialized) {
            // Read current tick from pool state
            (, int24 tick,,) = manager.getSlot0(key.toId());
            pool.observations.record(tick, uint32(block.timestamp));
            emit TickRecorded(key.toId(), tick, uint32(block.timestamp));
        }

        return (IHooks.afterSwap.selector, 0);
    }

    // ─── Keeper Functions ──────────────────────────────────────────────────

    /// @notice Update volatility computation for a pool. Callable by anyone (keeper).
    /// @param poolId The pool ID to update
    function updateVolatility(PoolId poolId) external {
        bytes32 id = PoolId.unwrap(poolId);
        PoolState storage pool = _pools[id];
        if (!pool.initialized) revert PoolNotInitialized();

        uint32 now_ = uint32(block.timestamp);
        if (pool.volState.lastUpdate > 0 && now_ - pool.volState.lastUpdate < minUpdateInterval) {
            revert UpdateTooFrequent();
        }

        uint16 count = pool.observations.length();
        if (count < 2) revert InsufficientObservations();

        // Use up to 256 most recent observations for vol computation
        uint16 sampleCount = count > 256 ? 256 : count;
        uint16 from = count - sampleCount;

        (int24[] memory ticks, uint32[] memory timestamps) = pool.observations.getRange(from, sampleCount);

        VolatilityEngine.VolState memory newState =
            VolatilityEngine.updateVolState(pool.volState, ticks, timestamps, sampleCount, now_);

        // Write updated state
        pool.volState.currentVol = newState.currentVol;
        pool.volState.ema7d = newState.ema7d;
        pool.volState.ema30d = newState.ema30d;
        pool.volState.lastUpdate = newState.lastUpdate;
        pool.volState.regime = newState.regime;
        pool.volState.sampleCount = newState.sampleCount;

        uint24 newFee = FeeCurve.getFee(pool.feeConfig, newState.currentVol);

        emit VolatilityUpdated(poolId, newState.currentVol, newState.regime, newFee, sampleCount);

        // Pay keeper reward
        if (keeperReward > 0 && address(this).balance >= keeperReward) {
            (bool ok,) = msg.sender.call{value: keeperReward}("");
            if (!ok) revert TransferFailed();
        }
    }

    // ─── View Functions (for SDK) ──────────────────────────────────────────

    /// @notice Get current volatility data for a pool
    function getVolatility(PoolId poolId)
        external
        view
        returns (uint64 currentVol, VolatilityEngine.Regime regime, uint64 ema7d, uint64 ema30d)
    {
        bytes32 id = PoolId.unwrap(poolId);
        PoolState storage pool = _pools[id];
        if (!pool.initialized) revert PoolNotInitialized();

        return (pool.volState.currentVol, pool.volState.regime, pool.volState.ema7d, pool.volState.ema30d);
    }

    /// @notice Get the current dynamic fee for a pool
    function getCurrentFee(PoolId poolId) external view returns (uint24 feeBps) {
        bytes32 id = PoolId.unwrap(poolId);
        PoolState storage pool = _pools[id];
        if (!pool.initialized) revert PoolNotInitialized();

        if (pool.volState.lastUpdate == 0) return 30;
        return FeeCurve.getFee(pool.feeConfig, pool.volState.currentVol);
    }

    /// @notice Get vol-adjusted LP range recommendation
    /// @dev Wider range in high vol, tighter in low vol
    function getRecommendedRange(PoolId poolId, int24 currentTick)
        external
        view
        returns (int24 lowerTick, int24 upperTick)
    {
        bytes32 id = PoolId.unwrap(poolId);
        PoolState storage pool = _pools[id];
        if (!pool.initialized) revert PoolNotInitialized();

        // Range width based on regime:
        // VeryLow: ±200 ticks (~2% range)
        // Low: ±500 ticks (~5% range)
        // Normal: ±1000 ticks (~10% range)
        // High: ±2000 ticks (~20% range)
        // Extreme: ±4000 ticks (~40% range)
        int24 halfWidth;
        VolatilityEngine.Regime regime = pool.volState.regime;

        if (regime == VolatilityEngine.Regime.VeryLow) halfWidth = 200;
        else if (regime == VolatilityEngine.Regime.Low) halfWidth = 500;
        else if (regime == VolatilityEngine.Regime.Normal) halfWidth = 1000;
        else if (regime == VolatilityEngine.Regime.High) halfWidth = 2000;
        else halfWidth = 4000;

        lowerTick = currentTick - halfWidth;
        upperTick = currentTick + halfWidth;
    }

    /// @notice Get observation buffer length for a pool
    function getObservationCount(PoolId poolId) external view returns (uint16) {
        bytes32 id = PoolId.unwrap(poolId);
        return _pools[id].observations.length();
    }

    /// @notice Get full vol state for a pool
    function getVolState(PoolId poolId) external view returns (VolatilityEngine.VolState memory) {
        bytes32 id = PoolId.unwrap(poolId);
        return _pools[id].volState;
    }

    /// @notice Check if a pool is registered with this hook
    function isPoolInitialized(PoolId poolId) external view returns (bool) {
        bytes32 id = PoolId.unwrap(poolId);
        return _pools[id].initialized;
    }

    // ─── Governance Functions ──────────────────────────────────────────────

    /// @notice Update fee curve for a specific pool
    function setFeeConfig(PoolId poolId, FeeCurve.FeeConfig calldata config) external onlyGovernance {
        if (!FeeCurve.validate(config)) revert InvalidFeeConfig();

        bytes32 id = PoolId.unwrap(poolId);
        PoolState storage pool = _pools[id];
        if (!pool.initialized) revert PoolNotInitialized();

        pool.feeConfig = config;
        emit FeeConfigUpdated(poolId);
    }

    /// @notice Update keeper reward
    function setKeeperReward(uint256 _reward) external onlyGovernance {
        keeperReward = _reward;
        emit KeeperRewardUpdated(_reward);
    }

    /// @notice Update minimum update interval
    function setMinUpdateInterval(uint32 _interval) external onlyGovernance {
        minUpdateInterval = _interval;
        emit MinUpdateIntervalUpdated(_interval);
    }

    /// @notice Transfer governance
    function transferGovernance(address newGovernance) external onlyGovernance {
        emit GovernanceTransferred(governance, newGovernance);
        governance = newGovernance;
    }

    /// @notice Accept ETH for keeper rewards
    receive() external payable {}

    // ─── Unused Hook Stubs ─────────────────────────────────────────────────

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert OnlyPoolManager();
    }

    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert OnlyPoolManager();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert OnlyPoolManager();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert OnlyPoolManager();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert OnlyPoolManager();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert OnlyPoolManager();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert OnlyPoolManager();
    }
}
