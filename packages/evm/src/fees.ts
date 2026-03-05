import type { PublicClient, Address } from "viem";
import { TempestHookABI } from "./abis/TempestHook.js";

export async function getCurrentFee(
  client: PublicClient,
  hookAddress: Address,
  poolId: `0x${string}`
): Promise<number> {
  const feeBps = await client.readContract({
    address: hookAddress,
    abi: TempestHookABI,
    functionName: "getCurrentFee",
    args: [poolId],
  });

  return Number(feeBps);
}
