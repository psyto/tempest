import type { PublicKey } from "@solana/web3.js";

/**
 * On-chain regime enum (matches @fabrknt/tempest-core Regime).
 */
export enum OnChainRegime {
  VeryLow = 0,
  Low = 1,
  Normal = 2,
  High = 3,
  Extreme = 4,
}

/**
 * On-chain volatility state for a pool.
 * Mirrors VolatilityEngine state from the Solidity contract.
 */
export interface OnChainVolState {
  pool: PublicKey;
  currentVol: bigint;      // Annualized vol in bps (1e6 precision)
  ema7d: bigint;            // 7-day EMA
  ema30d: bigint;           // 30-day EMA
  lastUpdate: bigint;       // Unix timestamp
  regime: OnChainRegime;
  sampleCount: number;
  isInitialized: boolean;
  bump: number;
}

/**
 * On-chain fee configuration for a pool.
 * Mirrors FeeCurve breakpoints from the Solidity contract.
 */
export interface OnChainFeeConfig {
  pool: PublicKey;
  vol0: bigint;
  fee0: number;
  vol1: bigint;
  fee1: number;
  vol2: bigint;
  fee2: number;
  vol3: bigint;
  fee3: number;
  vol4: bigint;
  fee4: number;
  vol5: bigint;
  fee5: number;
  bump: number;
}

/**
 * Global Tempest protocol configuration.
 */
export interface OnChainTempestConfig {
  authority: PublicKey;
  keeperReward: bigint;
  minUpdateInterval: bigint;
  totalPools: number;
  isPaused: boolean;
  bump: number;
}
