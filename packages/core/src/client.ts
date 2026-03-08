import type { Chain, ChainAdapter } from "./adapter.js";
import type { VolState, RecommendedRange } from "./types.js";
import { Regime } from "./types.js";
import { estimateIL } from "./lp.js";

/**
 * Chain-agnostic Tempest client.
 * Accepts any ChainAdapter implementation (EVM, SVM, etc.).
 *
 * Follows the injectable-interface pattern from @stratum/core.
 */
export class TempestClient {
  constructor(private readonly adapter: ChainAdapter) {}

  /** Which chain this client is connected to */
  get chain(): Chain {
    return this.adapter.chain;
  }

  // ─── Oracle reads ──────────────────────────────────────────────────

  async getVolatility(poolId: string) {
    const state = await this.adapter.getVolState(poolId);
    return {
      currentVol: state.currentVol,
      regime: state.regime,
      ema7d: state.ema7d,
      ema30d: state.ema30d,
    };
  }

  async getRegime(poolId: string): Promise<Regime> {
    const state = await this.adapter.getVolState(poolId);
    return state.regime;
  }

  async getVolState(poolId: string): Promise<VolState> {
    return this.adapter.getVolState(poolId);
  }

  // ─── Fee queries ───────────────────────────────────────────────────

  async getCurrentFee(poolId: string): Promise<number> {
    return this.adapter.getCurrentFee(poolId);
  }

  // ─── LP tools ──────────────────────────────────────────────────────

  async getRecommendedRange(
    poolId: string,
    currentTick: number,
  ): Promise<RecommendedRange> {
    return this.adapter.getRecommendedRange(poolId, currentTick);
  }

  estimateIL(
    volBps: number,
    rangeLower: number,
    rangeUpper: number,
    holdingPeriodDays?: number,
  ): number {
    return estimateIL(volBps, rangeLower, rangeUpper, holdingPeriodDays);
  }

  // ─── Pool info ─────────────────────────────────────────────────────

  async getObservationCount(poolId: string): Promise<number> {
    return this.adapter.getObservationCount(poolId);
  }

  async isPoolInitialized(poolId: string): Promise<boolean> {
    return this.adapter.isPoolInitialized(poolId);
  }
}
