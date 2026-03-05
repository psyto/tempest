export { TempestClient } from "./TempestClient.js";
export { getVolatility, getRegime, getVolState } from "./oracle.js";
export { getCurrentFee } from "./fees.js";
export { getRecommendedRange } from "./lp.js";
export { TempestHookABI } from "./abis/TempestHook.js";

// Re-export core types so consumers don't need to depend on @tempest/core directly
export {
  estimateIL,
  Regime,
  REGIME_NAMES,
  REGIME_COLORS,
  type VolState,
  type FeeConfig,
  type PoolInfo,
  type VolSample,
  type RecommendedRange,
} from "@tempest/core";
