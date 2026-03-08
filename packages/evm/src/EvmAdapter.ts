import type { PublicClient, Address } from "viem";
import type { Chain, ChainAdapter } from "@tempest/core";
import { TempestHookABI } from "./abis/TempestHook.js";
import type { VolState, RecommendedRange } from "@tempest/core";
import { Regime } from "@tempest/core";

/**
 * EVM implementation of the Tempest ChainAdapter.
 * Uses viem to read Uniswap v4 hook contract state.
 */
export class EvmAdapter implements ChainAdapter {
  readonly chain: Chain = "evm";

  constructor(
    private readonly client: PublicClient,
    private readonly hookAddress: Address,
  ) {}

  async getVolState(poolId: string): Promise<VolState> {
    const result = await this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "getVolState",
      args: [poolId as `0x${string}`],
    });

    return {
      currentVol: result.currentVol,
      ema7d: result.ema7d,
      ema30d: result.ema30d,
      lastUpdate: Number(result.lastUpdate),
      regime: Number(result.regime) as Regime,
      sampleCount: Number(result.sampleCount),
    };
  }

  async getCurrentFee(poolId: string): Promise<number> {
    const feeBps = await this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "getCurrentFee",
      args: [poolId as `0x${string}`],
    });
    return Number(feeBps);
  }

  async getRecommendedRange(
    poolId: string,
    currentTick: number,
  ): Promise<RecommendedRange> {
    const [lowerTick, upperTick] = await this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "getRecommendedRange",
      args: [poolId as `0x${string}`, currentTick],
    });
    return {
      lowerTick: Number(lowerTick),
      upperTick: Number(upperTick),
    };
  }

  async getObservationCount(poolId: string): Promise<number> {
    const count = await this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "getObservationCount",
      args: [poolId as `0x${string}`],
    });
    return Number(count);
  }

  async isPoolInitialized(poolId: string): Promise<boolean> {
    return this.client.readContract({
      address: this.hookAddress,
      abi: TempestHookABI,
      functionName: "isPoolInitialized",
      args: [poolId as `0x${string}`],
    });
  }

  // ─── EVM-specific helpers (not part of ChainAdapter) ──────────────

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
