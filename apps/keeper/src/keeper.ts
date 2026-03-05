import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  type PublicClient,
  type WalletClient,
  type Chain,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { mainnet, sepolia } from "viem/chains";
import { TempestHookABI, REGIME_NAMES } from "@tempest/evm";
import type { KeeperConfig } from "./config.js";
import { shouldUpdate } from "./gas-oracle.js";

function getChain(chainId: number): Chain {
  switch (chainId) {
    case 1:
      return mainnet;
    case 11155111:
      return sepolia;
    default:
      return mainnet;
  }
}

export class TempestKeeper {
  private publicClient: PublicClient;
  private walletClient: WalletClient;
  private chain: Chain;
  private account: Account;
  private config: KeeperConfig;
  private intervalId: ReturnType<typeof setInterval> | null = null;
  private lastRegimes: Map<string, number> = new Map();

  constructor(config: KeeperConfig) {
    this.config = config;
    this.chain = getChain(config.chainId);
    this.account = privateKeyToAccount(config.privateKey);

    this.publicClient = createPublicClient({
      chain: this.chain,
      transport: http(config.rpcUrl),
    });

    this.walletClient = createWalletClient({
      chain: this.chain,
      transport: http(config.rpcUrl),
      account: this.account,
    });
  }

  async start(): Promise<void> {
    console.log("=== Tempest Keeper Starting ===");
    console.log(`Hook: ${this.config.hookAddress}`);
    console.log(`Pools: ${this.config.poolIds.length}`);
    console.log(`Poll interval: ${this.config.pollIntervalMs}ms`);
    console.log(`Max gas: ${this.config.maxGasGwei} gwei`);

    await this.checkBalance();

    // Run immediately, then on interval
    await this.poll();
    this.intervalId = setInterval(() => this.poll(), this.config.pollIntervalMs);

    console.log("Keeper running. Press Ctrl+C to stop.");
  }

  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
    console.log("Keeper stopped.");
  }

  private async poll(): Promise<void> {
    const timestamp = new Date().toISOString();
    console.log(`\n[${timestamp}] Polling...`);

    // Check gas
    const gas = await shouldUpdate(
      this.publicClient,
      this.config.maxGasGwei
    );
    if (!gas.proceed) {
      console.log(`  Gas too high: ${gas.currentGwei} gwei (max: ${this.config.maxGasGwei})`);
      return;
    }
    console.log(`  Gas: ${gas.currentGwei} gwei ✓`);

    for (const poolId of this.config.poolIds) {
      try {
        await this.updatePool(poolId);
      } catch (err) {
        console.error(`  Error updating pool ${poolId}:`, err instanceof Error ? err.message : err);
      }
    }

    await this.checkBalance();
  }

  private async updatePool(poolId: `0x${string}`): Promise<void> {
    // Check if pool is initialized
    const initialized = await this.publicClient.readContract({
      address: this.config.hookAddress,
      abi: TempestHookABI,
      functionName: "isPoolInitialized",
      args: [poolId],
    });

    if (!initialized) {
      console.log(`  Pool ${poolId.slice(0, 10)}... not initialized, skipping`);
      return;
    }

    // Check vol state
    const volState = await this.publicClient.readContract({
      address: this.config.hookAddress,
      abi: TempestHookABI,
      functionName: "getVolState",
      args: [poolId],
    });

    const lastUpdate = Number(volState.lastUpdate);
    const now = Math.floor(Date.now() / 1000);

    const minInterval = await this.publicClient.readContract({
      address: this.config.hookAddress,
      abi: TempestHookABI,
      functionName: "minUpdateInterval",
    });

    if (lastUpdate > 0 && now - lastUpdate < Number(minInterval)) {
      const waitTime = Number(minInterval) - (now - lastUpdate);
      console.log(`  Pool ${poolId.slice(0, 10)}... update too recent, wait ${waitTime}s`);
      return;
    }

    // Execute update
    console.log(`  Updating pool ${poolId.slice(0, 10)}...`);

    const hash = await this.walletClient.writeContract({
      chain: this.chain,
      account: this.account,
      address: this.config.hookAddress,
      abi: TempestHookABI,
      functionName: "updateVolatility",
      args: [poolId],
    });

    console.log(`  TX submitted: ${hash}`);

    const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
    console.log(`  TX confirmed in block ${receipt.blockNumber}, gas used: ${receipt.gasUsed}`);

    // Read updated vol state
    const [currentVol, regime] = await this.publicClient.readContract({
      address: this.config.hookAddress,
      abi: TempestHookABI,
      functionName: "getVolatility",
      args: [poolId],
    });

    const regimeName = REGIME_NAMES[Number(regime) as keyof typeof REGIME_NAMES] ?? "Unknown";
    const volPct = (Number(currentVol) / 100).toFixed(2);

    // Detect regime change
    const prevRegime = this.lastRegimes.get(poolId);
    if (prevRegime !== undefined && prevRegime !== Number(regime)) {
      console.log(`  ⚡ REGIME CHANGE: ${REGIME_NAMES[prevRegime as keyof typeof REGIME_NAMES]} → ${regimeName}`);
    }
    this.lastRegimes.set(poolId, Number(regime));

    console.log(`  Vol: ${volPct}% | Regime: ${regimeName}`);
  }

  private async checkBalance(): Promise<void> {
    const balance = await this.publicClient.getBalance({
      address: this.account.address,
    });
    const ethBalance = formatEther(balance);
    console.log(`  Keeper balance: ${ethBalance} ETH`);

    if (balance < BigInt(0.01e18)) {
      console.warn("  ⚠️  Low keeper balance! Fund the keeper wallet.");
    }
  }
}
