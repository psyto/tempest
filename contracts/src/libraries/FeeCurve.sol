// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title FeeCurve — Piecewise linear volatility-to-fee mapping
/// @notice Maps realized volatility to a dynamic swap fee using 6 control points
///         with linear interpolation between them. Governance-adjustable.
/// @dev Target: ~200 gas (pure math, no storage reads)
library FeeCurve {
    struct FeeConfig {
        // Control points: (vol_bps, fee_bps)
        // Must be sorted by vol ascending
        uint64 vol0;
        uint24 fee0; // e.g., (0, 5)        — floor fee
        uint64 vol1;
        uint24 fee1; // e.g., (2000, 10)    — VeryLow ceiling
        uint64 vol2;
        uint24 fee2; // e.g., (3500, 30)    — Low→Normal
        uint64 vol3;
        uint24 fee3; // e.g., (5000, 60)    — Normal→High
        uint64 vol4;
        uint24 fee4; // e.g., (7500, 150)   — High→Extreme
        uint64 vol5;
        uint24 fee5; // e.g., (15000, 500)  — cap
    }

    error InvalidFeeConfig();

    /// @notice Compute the fee for a given volatility using piecewise linear interpolation
    /// @param config The fee curve control points
    /// @param volBps Current annualized volatility in basis points
    /// @return feeBps The computed fee in basis points
    function getFee(FeeConfig memory config, uint64 volBps) internal pure returns (uint24 feeBps) {
        // Below first control point: return floor fee
        if (volBps <= config.vol0) {
            return config.fee0;
        }

        // Above last control point: return cap fee
        if (volBps >= config.vol5) {
            return config.fee5;
        }

        // Find which segment we're in and interpolate
        if (volBps <= config.vol1) {
            return _interpolate(config.vol0, config.fee0, config.vol1, config.fee1, volBps);
        }
        if (volBps <= config.vol2) {
            return _interpolate(config.vol1, config.fee1, config.vol2, config.fee2, volBps);
        }
        if (volBps <= config.vol3) {
            return _interpolate(config.vol2, config.fee2, config.vol3, config.fee3, volBps);
        }
        if (volBps <= config.vol4) {
            return _interpolate(config.vol3, config.fee3, config.vol4, config.fee4, volBps);
        }
        return _interpolate(config.vol4, config.fee4, config.vol5, config.fee5, volBps);
    }

    /// @notice Linear interpolation between two control points
    /// @dev fee = feeA + (feeB - feeA) * (vol - volA) / (volB - volA)
    function _interpolate(
        uint64 volA,
        uint24 feeA,
        uint64 volB,
        uint24 feeB,
        uint64 vol
    ) private pure returns (uint24) {
        // Both increasing and decreasing fee curves supported
        uint256 volRange = uint256(volB) - uint256(volA);
        uint256 volOffset = uint256(vol) - uint256(volA);

        if (feeB >= feeA) {
            uint256 feeRange = uint256(feeB) - uint256(feeA);
            return uint24(uint256(feeA) + (feeRange * volOffset) / volRange);
        } else {
            uint256 feeRange = uint256(feeA) - uint256(feeB);
            return uint24(uint256(feeA) - (feeRange * volOffset) / volRange);
        }
    }

    /// @notice Validate that a fee config has monotonically increasing vol points
    function validate(FeeConfig memory config) internal pure returns (bool) {
        return config.vol0 < config.vol1 && config.vol1 < config.vol2 && config.vol2 < config.vol3
            && config.vol3 < config.vol4 && config.vol4 < config.vol5;
    }

    /// @notice Return the default fee configuration
    /// @return config The default fee curve
    function defaultConfig() internal pure returns (FeeConfig memory config) {
        config = FeeConfig({
            vol0: 0,
            fee0: 5, // 0.05% floor
            vol1: 2000,
            fee1: 10, // 0.10% at 20% vol
            vol2: 3500,
            fee2: 30, // 0.30% at 35% vol
            vol3: 5000,
            fee3: 60, // 0.60% at 50% vol
            vol4: 7500,
            fee4: 150, // 1.50% at 75% vol
            vol5: 15000,
            fee5: 500 // 5.00% cap at 150% vol
        });
    }
}
