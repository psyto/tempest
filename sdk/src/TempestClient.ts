import type { PublicClient, Address } from "viem";
import { TempestHookABI } from "./abis/TempestHook.js";
import { getVolatility, getRegime, getVolState } from "./oracle.js";
import { getCurrentFee } from "./fees.js";
import { getRecommendedRange, estimateIL } from "./lp.js";
import type { VolState, RecommendedRange } from "./types.js";
import { Regime } from "./types.js";

export class TempestClient {
  private client: PublicClient;
  private hookAddress: Address;

  constructor(client: PublicClient, hookAddress: Address) {
    this.client = client;
    this.hookAddress = hookAddress;
  }

  // ─── Oracle reads ──────────────────────────────────────────────────

  async getVolatility(poolId: `0x${string}`) {
    return getVolatility(this.client, this.hookAddress, poolId);
  }

  async getRegime(poolId: `0x${string}`): Promise<Regime> {
    return getRegime(this.client, this.hookAddress, poolId);
  }

  async getVolState(poolId: `0x${string}`): Promise<VolState> {
    return getVolState(this.client, this.hookAddress, poolId);
  }

  // ─── Fee queries ───────────────────────────────────────────────────

  async getCurrentFee(poolId: `0x${string}`): Promise<number> {
    return getCurrentFee(this.client, this.hookAddress, poolId);
  }

  // ─── LP tools ──────────────────────────────────────────────────────

  async getRecommendedRange(
    poolId: `0x${string}`,
    currentTick: number
  ): Promise<RecommendedRange> {
    return getRecommendedRange(this.client, this.hookAddress, poolId, currentTick);
  }

  estimateIL(
    volBps: number,
    rangeLower: number,
    rangeUpper: number,
    holdingPeriodDays?: number
  ): number {
    return estimateIL(volBps, rangeLower, rangeUpper, holdingPeriodDays);
  }

  // ─── Pool info ─────────────────────────────────────────────────────

  async getObservationCount(poolId: `0x${string}`): Promise<number> {
    const count = await this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "getObservationCount",
      args: [poolId],
    });
    return Number(count);
  }

  async isPoolInitialized(poolId: `0x${string}`): Promise<boolean> {
    return this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "isPoolInitialized",
      args: [poolId],
    });
  }

  // ─── Protocol info ─────────────────────────────────────────────────

  async getGovernance(): Promise<Address> {
    return this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "governance",
    });
  }

  async getKeeperReward(): Promise<bigint> {
    return this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "keeperReward",
    });
  }

  async getMinUpdateInterval(): Promise<number> {
    const interval = await this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "minUpdateInterval",
    });
    return Number(interval);
  }
}
