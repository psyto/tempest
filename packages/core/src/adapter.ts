import type { VolState, FeeConfig, RecommendedRange } from "./types.js";

/**
 * Supported chain identifiers.
 * Follows the Chain union pattern from @sentinel/core and @accredit/core.
 */
export type Chain = "solana" | "evm";

/**
 * Chain-agnostic adapter interface for reading Tempest hook state.
 * Implement this for each chain (EVM, SVM, etc.).
 *
 * Follows the injectable-interface pattern from @stratum/core.
 */
export interface ChainAdapter {
  /** Chain identifier */
  readonly chain: Chain;

  /** Read current volatility state for a pool */
  getVolState(poolId: string): Promise<VolState>;

  /** Read current dynamic fee (in bps) for a pool */
  getCurrentFee(poolId: string): Promise<number>;

  /** Get recommended LP tick range based on current volatility */
  getRecommendedRange(poolId: string, currentTick: number): Promise<RecommendedRange>;

  /** Get observation count for a pool */
  getObservationCount(poolId: string): Promise<number>;

  /** Check if a pool is initialized */
  isPoolInitialized(poolId: string): Promise<boolean>;
}
