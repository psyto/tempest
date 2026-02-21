// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title VolatilityEngine — Realized volatility computation and regime detection
/// @notice Computes annualized realized volatility from tick observations.
/// @dev Uniswap v4 ticks are log_1.0001(price), so tick differences ARE log returns.
///      This eliminates division and makes variance computation cheaper.
///
///      Vol calculation:
///      1. Δtick_i = tick_i - tick_{i-1} (these are log returns)
///      2. variance = Σ(Δtick²) / N
///      3. Annualize: vol = sqrt(variance * secondsPerYear / avgInterval)
///      4. Convert to bps: volBps = sqrt(variance_annualized) * 10000 / log1.0001_scale
library VolatilityEngine {
    enum Regime {
        VeryLow, // < 20% annualized
        Low, // 20-35%
        Normal, // 35-50%
        High, // 50-75%
        Extreme // > 75%
    }

    struct VolState {
        uint64 currentVol; // Annualized vol in bps (4500 = 45%)
        uint64 ema30d; // 30-day EMA
        uint64 ema7d; // 7-day EMA
        uint32 lastUpdate; // Timestamp of last vol computation
        Regime regime; // Current regime
        uint16 sampleCount; // Observations used in last calc
    }

    // Regime thresholds in bps (matching Sigma)
    uint64 constant VERY_LOW_CEILING = 2000; // 20%
    uint64 constant LOW_CEILING = 3500; // 35%
    uint64 constant NORMAL_CEILING = 5000; // 50%
    uint64 constant HIGH_CEILING = 7500; // 75%

    // EMA half-lives
    uint32 constant EMA_7D_HALF_LIFE = 7 days;
    uint32 constant EMA_30D_HALF_LIFE = 30 days;

    // Seconds per year for annualization
    uint256 constant SECONDS_PER_YEAR = 365.25 days;

    // Scaling factor: tick = log_1.0001(price)
    // log_1.0001(1 + 0.0001) = 1 tick
    // 1 tick ≈ 0.01% price change = 1 bps
    // So tick difference directly gives bps of price change
    // For annualized vol: volBps = sqrt(sum_sq / n * SECONDS_PER_YEAR / avgInterval)
    // Since each tick ≈ 1 bps, we just need to annualize the standard deviation of tick changes

    error InsufficientSamples();

    /// @notice Compute annualized realized volatility from tick observations
    /// @param ticks Array of tick values, ordered oldest to newest
    /// @param timestamps Array of timestamps corresponding to ticks
    /// @param count Number of valid observations
    /// @return annualizedVolBps Annualized volatility in basis points
    function computeRealizedVol(
        int24[] memory ticks,
        uint32[] memory timestamps,
        uint16 count
    ) internal pure returns (uint64 annualizedVolBps) {
        if (count < 2) revert InsufficientSamples();

        // Compute sum of squared tick differences and total time elapsed
        uint256 sumSq;
        uint256 totalElapsed;
        uint16 validPairs;

        for (uint16 i = 1; i < count; i++) {
            int256 delta = int256(ticks[i]) - int256(ticks[i - 1]);
            uint32 dt = timestamps[i] - timestamps[i - 1];

            // Skip zero-time intervals
            if (dt == 0) continue;

            // Time-weight the squared returns: normalize to per-second variance
            // variance_per_second += delta^2 / dt
            // We scale up to preserve precision: multiply by 1e18 first
            sumSq += (uint256(delta >= 0 ? delta : -delta) * uint256(delta >= 0 ? delta : -delta) * 1e18) / uint256(dt);
            totalElapsed += dt;
            validPairs++;
        }

        if (validPairs == 0) return 0;

        // Average per-second variance (still scaled by 1e18)
        uint256 variancePerSecond = sumSq / validPairs;

        // Annualize: variance_annual = variance_per_second * SECONDS_PER_YEAR
        uint256 varianceAnnual = variancePerSecond * SECONDS_PER_YEAR;

        // volBps = sqrt(varianceAnnual) / sqrt(1e18) * (bps_per_tick)
        // Since 1 tick ≈ 1 bps, bps_per_tick = 1
        // sqrt(varianceAnnual / 1e18) gives us the vol in tick-units = bps
        uint256 volScaled = sqrt(varianceAnnual);
        // Divide by sqrt(1e18) = 1e9
        annualizedVolBps = uint64(volScaled / 1e9);
    }

    /// @notice Classify volatility into a regime
    /// @param volBps Annualized vol in basis points
    /// @return regime The classified regime
    function classifyRegime(uint64 volBps) internal pure returns (Regime regime) {
        if (volBps <= VERY_LOW_CEILING) return Regime.VeryLow;
        if (volBps <= LOW_CEILING) return Regime.Low;
        if (volBps <= NORMAL_CEILING) return Regime.Normal;
        if (volBps <= HIGH_CEILING) return Regime.High;
        return Regime.Extreme;
    }

    /// @notice Update an exponential moving average
    /// @param currentEma Current EMA value
    /// @param newValue New observation
    /// @param elapsed Seconds since last update
    /// @param halfLife Half-life in seconds
    /// @return Updated EMA value
    function updateEMA(
        uint64 currentEma,
        uint64 newValue,
        uint32 elapsed,
        uint32 halfLife
    ) internal pure returns (uint64) {
        if (currentEma == 0) return newValue;
        if (elapsed == 0) return currentEma;

        // Approximate: alpha = 1 - 0.5^(elapsed/halfLife)
        // For small elapsed/halfLife, alpha ≈ elapsed * ln(2) / halfLife
        // We use a fixed-point approximation:
        // weight = min(elapsed * 1000 / halfLife, 1000) for parts-per-thousand
        uint256 weight = (uint256(elapsed) * 693) / uint256(halfLife); // ln(2) * 1000 ≈ 693
        if (weight > 1000) weight = 1000;

        // EMA = (1 - alpha) * currentEma + alpha * newValue
        uint256 result = ((1000 - weight) * uint256(currentEma) + weight * uint256(newValue)) / 1000;
        return uint64(result);
    }

    /// @notice Check if current vol is elevated relative to the 30d EMA
    /// @param state Current vol state
    /// @return True if currentVol > 1.5x ema30d
    function isElevated(VolState memory state) internal pure returns (bool) {
        return state.currentVol > (state.ema30d * 3) / 2;
    }

    /// @notice Check if current vol is depressed relative to the 30d EMA
    /// @param state Current vol state
    /// @return True if currentVol < 0.5x ema30d
    function isDepressed(VolState memory state) internal pure returns (bool) {
        return state.currentVol < state.ema30d / 2;
    }

    /// @notice Full vol state update — compute vol, classify regime, update EMAs
    /// @param state Current vol state (will be updated in memory)
    /// @param ticks Tick observations
    /// @param timestamps Corresponding timestamps
    /// @param count Number of observations
    /// @param currentTimestamp Current block timestamp
    /// @return Updated vol state
    function updateVolState(
        VolState memory state,
        int24[] memory ticks,
        uint32[] memory timestamps,
        uint16 count,
        uint32 currentTimestamp
    ) internal pure returns (VolState memory) {
        uint64 vol = computeRealizedVol(ticks, timestamps, count);

        uint32 elapsed = state.lastUpdate > 0 ? currentTimestamp - state.lastUpdate : 0;

        state.currentVol = vol;
        state.regime = classifyRegime(vol);
        state.sampleCount = count;
        state.lastUpdate = currentTimestamp;

        state.ema7d = updateEMA(state.ema7d, vol, elapsed, EMA_7D_HALF_LIFE);
        state.ema30d = updateEMA(state.ema30d, vol, elapsed, EMA_30D_HALF_LIFE);

        return state;
    }

    /// @notice Integer square root (Babylonian method)
    /// @param x The value to compute sqrt of
    /// @return y The integer square root
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
