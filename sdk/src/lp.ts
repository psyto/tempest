import type { PublicClient, Address } from "viem";
import { TempestHookABI } from "./abis/TempestHook.js";
import type { RecommendedRange } from "./types.js";

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

/**
 * Estimate impermanent loss for a concentrated liquidity position
 * based on current volatility and tick range.
 *
 * Uses the simplified IL formula for concentrated liquidity:
 * IL ≈ volBps² * timeInYears / (2 * rangeWidth²)
 *
 * @param volBps Annualized vol in basis points
 * @param rangeLower Lower tick of position
 * @param rangeUpper Upper tick of position
 * @param holdingPeriodDays How long the position will be held
 * @returns Estimated IL as a percentage (e.g., 2.5 = 2.5%)
 */
export function estimateIL(
  volBps: number,
  rangeLower: number,
  rangeUpper: number,
  holdingPeriodDays: number = 30
): number {
  const rangeWidth = rangeUpper - rangeLower;
  if (rangeWidth <= 0) return 0;

  const volFraction = volBps / 10000; // Convert bps to fraction
  const timeInYears = holdingPeriodDays / 365.25;

  // Simplified IL for concentrated liquidity
  // Wider ranges have less IL, higher vol increases IL
  const il = (volFraction * volFraction * timeInYears * 100) / (2 * (rangeWidth / 10000) * (rangeWidth / 10000));

  return Math.min(il, 100); // Cap at 100%
}
