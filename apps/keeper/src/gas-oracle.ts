import { type PublicClient, formatGwei, formatEther } from "viem";

export interface GasCheck {
  proceed: boolean;
  currentGwei: string;
}

export async function shouldUpdate(
  client: PublicClient,
  maxGasGwei: number
): Promise<GasCheck> {
  const gasPrice = await client.getGasPrice();
  const currentGwei = formatGwei(gasPrice);
  const proceed = Number(currentGwei) <= maxGasGwei;

  return { proceed, currentGwei };
}

export interface ProfitabilityCheck {
  profitable: boolean;
  estimatedReward: bigint;
  estimatedGasCost: bigint;
  profitMargin: string;
  gasPrice: bigint;
}

/**
 * Estimate whether a keeper update will be profitable.
 * Uses the on-chain reward formula: baseReward + gasOverhead * gasPrice * (10000 + premiumBps) / 10000
 * Compares against the actual estimated gas cost.
 */
export async function checkProfitability(
  client: PublicClient,
  params: {
    baseReward: bigint;
    gasOverhead: bigint;
    premiumBps: number;
  }
): Promise<ProfitabilityCheck> {
  const gasPrice = await client.getGasPrice();

  // Mirror the on-chain formula
  const gasCost = params.gasOverhead * gasPrice;
  const gasReward = (gasCost * BigInt(10_000 + params.premiumBps)) / 10_000n;
  const estimatedReward = params.baseReward + gasReward;

  // Actual gas cost to the keeper (gasOverhead is an estimate of units used)
  const estimatedGasCost = params.gasOverhead * gasPrice;

  const profitable = estimatedReward > estimatedGasCost;
  const profit = estimatedReward - estimatedGasCost;
  const profitMargin = formatEther(profit);

  return {
    profitable,
    estimatedReward,
    estimatedGasCost,
    profitMargin,
    gasPrice,
  };
}
