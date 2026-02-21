export enum Regime {
  VeryLow = 0,
  Low = 1,
  Normal = 2,
  High = 3,
  Extreme = 4,
}

export const REGIME_NAMES: Record<Regime, string> = {
  [Regime.VeryLow]: "Very Low",
  [Regime.Low]: "Low",
  [Regime.Normal]: "Normal",
  [Regime.High]: "High",
  [Regime.Extreme]: "Extreme",
};

export const REGIME_COLORS: Record<Regime, string> = {
  [Regime.VeryLow]: "#22c55e",
  [Regime.Low]: "#3b82f6",
  [Regime.Normal]: "#eab308",
  [Regime.High]: "#f97316",
  [Regime.Extreme]: "#ef4444",
};

export interface VolState {
  currentVol: bigint;
  ema7d: bigint;
  ema30d: bigint;
  lastUpdate: number;
  regime: Regime;
  sampleCount: number;
}

export interface FeeConfig {
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
}

export interface PoolInfo {
  poolId: `0x${string}`;
  initialized: boolean;
}

export interface VolSample {
  vol: bigint;
  timestamp: number;
  regime: Regime;
}

export interface RecommendedRange {
  lowerTick: number;
  upperTick: number;
}
