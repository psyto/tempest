import type { PublicClient, Address } from "viem";
import { TempestHookABI } from "./abis/TempestHook.js";
import { Regime, type VolState } from "./types.js";

export async function getVolatility(
  client: PublicClient,
  hookAddress: Address,
  poolId: `0x${string}`
): Promise<{ currentVol: bigint; regime: Regime; ema7d: bigint; ema30d: bigint }> {
  const [currentVol, regime, ema7d, ema30d] = await client.readContract({
    address: hookAddress,
    abi: TempestHookABI,
    functionName: "getVolatility",
    args: [poolId],
  });

  return {
    currentVol,
    regime: regime as Regime,
    ema7d,
    ema30d,
  };
}

export async function getRegime(
  client: PublicClient,
  hookAddress: Address,
  poolId: `0x${string}`
): Promise<Regime> {
  const { regime } = await getVolatility(client, hookAddress, poolId);
  return regime;
}

export async function getVolState(
  client: PublicClient,
  hookAddress: Address,
  poolId: `0x${string}`
): Promise<VolState> {
  const result = await client.readContract({
    address: hookAddress,
    abi: TempestHookABI,
    functionName: "getVolState",
    args: [poolId],
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
