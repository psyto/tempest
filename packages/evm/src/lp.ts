import type { PublicClient, Address } from "viem";
import { TempestHookABI } from "./abis/TempestHook.js";
import type { RecommendedRange } from "@fabrknt/tempest-core";

export async function getRecommendedRange(
  client: PublicClient,
  hookAddress: Address,
  poolId: `0x${string}`,
  currentTick: number
): Promise<RecommendedRange> {
  const [lowerTick, upperTick] = await client.readContract({
    address: hookAddress,
    abi: TempestHookABI,
    functionName: "getRecommendedRange",
    args: [poolId, currentTick],
  });

  return {
    lowerTick: Number(lowerTick),
    upperTick: Number(upperTick),
  };
}
