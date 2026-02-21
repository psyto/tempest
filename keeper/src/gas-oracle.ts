import { type PublicClient, formatGwei } from "viem";

export async function shouldUpdate(
  client: PublicClient,
  maxGasGwei: number
): Promise<{ proceed: boolean; currentGwei: string }> {
  const gasPrice = await client.getGasPrice();
  const currentGwei = formatGwei(gasPrice);
  const proceed = Number(currentGwei) <= maxGasGwei;

  return { proceed, currentGwei };
}
