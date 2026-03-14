export { EvmAdapter } from "./EvmAdapter.js";

// Keep standalone functions for backwards compatibility
export { getVolatility, getRegime, getVolState } from "./oracle.js";
export { getCurrentFee } from "./fees.js";
export { getRecommendedRange } from "./lp.js";
export { TempestHookABI } from "./abis/TempestHook.js";

// Re-export core types and the chain-agnostic client
export {
  TempestClient,
  estimateIL,
  Regime,
  REGIME_NAMES,
  REGIME_COLORS,
  type Chain,
  type ChainAdapter,
  type VolState,
  type FeeConfig,
  type PoolInfo,
  type VolSample,
  type RecommendedRange,
} from "@fabrknt/tempest-core";
