import { Connection, PublicKey } from "@solana/web3.js";
import type { ChainAdapter, Chain, VolState, RecommendedRange } from "@fabrknt/tempest-core";
import { Regime } from "@fabrknt/tempest-core";
import { TEMPEST_PROGRAM_ID, findVolStatePDA, findFeeConfigPDA } from "./pda.js";
import type { OnChainVolState } from "./accounts.js";

/**
 * Solana implementation of the Tempest ChainAdapter.
 * Reads volatility and fee state from the Tempest Solana program.
 *
 * NOTE: This is a scaffold — the Tempest Solana program has not been
 * deployed yet. Account deserialization will be wired once the program
 * IDL is available.
 */
export class SolanaAdapter implements ChainAdapter {
  readonly chain: Chain = "solana";
  private connection: Connection;
  private programId: PublicKey;

  constructor(
    connection: Connection,
    programId: PublicKey = TEMPEST_PROGRAM_ID,
  ) {
    this.connection = connection;
    this.programId = programId;
  }

  async getVolState(poolId: string): Promise<VolState> {
    const pool = new PublicKey(poolId);
    const [pda] = findVolStatePDA(pool, this.programId);
    const accountInfo = await this.connection.getAccountInfo(pda);

    if (!accountInfo) {
      throw new Error(`Vol state not found for pool ${poolId}`);
    }

    // Account deserialization will be implemented once the
    // Tempest Solana program is deployed and its IDL is available.
    // For now, this throws to make the limitation explicit.
    throw new Error(
      "Tempest Solana program not yet deployed. " +
      "Account deserialization will be available after deployment.",
    );
  }

  async getCurrentFee(poolId: string): Promise<number> {
    const state = await this.getVolState(poolId);
    // Once we can read vol state, use @fabrknt/tempest-core's interpolateFee()
    // to compute the fee locally (same math as the on-chain program).
    const { interpolateFee } = await import("@fabrknt/tempest-core");
    return interpolateFee(Number(state.currentVol));
  }

  async getRecommendedRange(
    poolId: string,
    currentTick: number,
  ): Promise<RecommendedRange> {
    const state = await this.getVolState(poolId);
    // Range recommendation based on vol — wider range for higher vol.
    // This mirrors the Solidity contract's getRecommendedRange logic.
    const volBps = Number(state.currentVol);
    const halfWidth = Math.max(100, Math.floor(volBps / 2));
    return {
      lowerTick: currentTick - halfWidth,
      upperTick: currentTick + halfWidth,
    };
  }

  async getObservationCount(poolId: string): Promise<number> {
    const state = await this.getVolState(poolId);
    return state.sampleCount;
  }

  async isPoolInitialized(poolId: string): Promise<boolean> {
    const pool = new PublicKey(poolId);
    const [pda] = findVolStatePDA(pool, this.programId);
    const accountInfo = await this.connection.getAccountInfo(pda);
    return accountInfo !== null;
  }
}
