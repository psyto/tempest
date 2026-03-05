import "dotenv/config";

export interface KeeperConfig {
  rpcUrl: string;
  privateKey: `0x${string}`;
  hookAddress: `0x${string}`;
  pollIntervalMs: number;
  maxGasGwei: number;
  poolIds: `0x${string}`[];
  chainId: number;
}

export function loadConfig(): KeeperConfig {
  const rpcUrl = requireEnv("RPC_URL");
  const privateKey = requireEnv("PRIVATE_KEY") as `0x${string}`;
  const hookAddress = requireEnv("HOOK_ADDRESS") as `0x${string}`;

  const pollIntervalMs = parseInt(process.env.POLL_INTERVAL_MS ?? "300000", 10);
  const maxGasGwei = parseInt(process.env.MAX_GAS_GWEI ?? "50", 10);
  const chainId = parseInt(process.env.CHAIN_ID ?? "1", 10);

  const poolIdsRaw = process.env.POOL_IDS ?? "";
  const poolIds = poolIdsRaw
    .split(",")
    .map((id) => id.trim())
    .filter((id) => id.length > 0) as `0x${string}`[];

  if (poolIds.length === 0) {
    throw new Error("POOL_IDS must contain at least one pool ID");
  }

  return {
    rpcUrl,
    privateKey,
    hookAddress,
    pollIntervalMs,
    maxGasGwei,
    poolIds,
    chainId,
  };
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}
