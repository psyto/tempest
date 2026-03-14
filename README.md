# Tempest

Volatility-responsive dynamic fee hook for Uniswap v4.

Tempest dynamically adjusts swap fees based on real-time realized volatility computed from pool swap data. All existing AMMs use static or manually-adjusted fees — Tempest automates this, protecting LPs during vol spikes and attracting volume during calm markets.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     TempestHook.sol                       │
│            (Uniswap v4 IHooks implementation)            │
│                                                           │
│  afterInitialize ── register pool with oracle             │
│  afterSwap ─────── record tick (with dust filter)         │
│  beforeSwap ────── vol → FeeCurve → momentum → fee        │
│                    (+ staleness fail-safe)                 │
│                                                           │
│  ┌──────────────┐ ┌──────────────┐ ┌───────────────────┐ │
│  │ TickObserver  │ │ VolatilityEng│ │ FeeCurve          │ │
│  │ (lib)        │ │ (lib)        │ │ (lib)             │ │
│  │              │ │              │ │                   │ │
│  │ Circular buf │ │ Realized vol │ │ Vol→Fee piecewise │ │
│  │ 4 obs/slot   │ │ Regime detect│ │ + momentum boost  │ │
│  │              │ │ EMA smoothing│ │                   │ │
│  └──────────────┘ └──────────────┘ └───────────────────┘ │
└─────────────────────────────────────────────────────────┘
         │                    ▲
         │ tick data          │ updateVolatility()
         ▼                    │
    PoolManager          Keeper Service
    (Uniswap v4)         (TypeScript, staleness-aware)
```

## How It Works

1. **Every swap** — `afterSwap` records the current tick into a gas-optimized circular buffer (4 observations packed per storage slot, 1024 capacity). Swaps below the pool's `minSwapSize` are filtered out to prevent dust-trade manipulation.
2. **Periodically** — A keeper calls `updateVolatility()`, which computes annualized realized vol from tick observations and classifies the market regime. The keeper receives a dynamic ETH reward that scales with gas price to ensure profitability.
3. **Next swap** — `beforeSwap` reads the current vol regime and returns a dynamic fee via piecewise linear interpolation, with a momentum boost when vol is accelerating above its 7-day EMA.
4. **If the keeper goes down** — When `block.timestamp - lastUpdate > staleFeeThreshold` (default 1 hour), fees automatically escalate to the cap (500 bps) to protect LPs from arbitrage at stale, low fees.

Since Uniswap v4 ticks are `log₁.₀₀₀₁(price)`, tick differences ARE log returns — no division needed for variance computation.

## Resilience Mechanisms

### Keeper Fail-Safe

If no volatility update occurs within `staleFeeThreshold` (default 3600s), `beforeSwap` automatically returns the cap fee (`feeConfig.fee5`, default 500 bps). This protects LPs during keeper downtime — exactly when arbitrageurs are most active. The fail-safe clears as soon as the keeper submits a fresh `updateVolatility` call.

### Dust Trade Filter

Each pool has a configurable `minSwapSize` (default 0 = disabled). When set, `afterSwap` skips recording observations for swaps where `abs(delta.amount0) < minSwapSize`. This prevents attackers from injecting many tiny swaps at a manipulated tick to artificially suppress volatility.

### Momentum Adjustment

When `currentVol > ema7d`, the base fee from FeeCurve is boosted by up to 50% (capped at `fee5`). This provides faster fee response during vol spikes, partially compensating for the backward-looking nature of realized volatility. When vol is stable or declining, no adjustment is applied.

### Dynamic Keeper Rewards

The keeper reward scales with gas price to ensure profitability at any network congestion level:

```
reward = keeperBaseReward + keeperGasOverhead × tx.gasprice × (10000 + keeperPremiumBps) / 10000
```

| Gas Price | Reward (default params) |
|-----------|------------------------|
| 0 gwei | 0.0005 ETH (base only) |
| 10 gwei | ~0.003 ETH |
| 100 gwei | ~0.023 ETH |
| 500 gwei | ~0.113 ETH |

The keeper also overrides its gas limit when pools are approaching staleness (>80% of threshold), prioritizing LP protection over gas cost.

## Volatility Regimes

| Regime | Vol Range | Annualized | Fee Range | Rationale |
|--------|-----------|------------|-----------|-----------|
| Very Low | 0–2000 bps | < 20% | 5–10 bps | Attract volume in calm markets |
| Low | 2000–3500 bps | 20–35% | 10–30 bps | Standard competitive fee |
| Normal | 3500–5000 bps | 35–50% | 30–60 bps | Moderate LP compensation |
| High | 5000–7500 bps | 50–75% | 60–150 bps | Compensate LPs for IL risk |
| Extreme | > 7500 bps | > 75% | 150–500 bps | Circuit breaker / LP protection |

## Project Structure

```
tempest/
├── contracts/              # Foundry project (Solidity)
│   ├── src/
│   │   ├── TempestHook.sol
│   │   └── libraries/
│   │       ├── TickObserver.sol
│   │       ├── VolatilityEngine.sol
│   │       └── FeeCurve.sol
│   ├── test/               # 102 tests (unit + integration + scenario + fuzz)
│   └── script/             # Deployment & CREATE2 mining
├── packages/
│   ├── core/               # @fabrknt/tempest-core — chain-agnostic types, algorithms & client
│   │   └── src/
│   │       ├── types.ts    # Regime, VolState, FeeConfig, PoolInfo, VolSample
│   │       ├── adapter.ts  # Chain, ChainAdapter interface
│   │       ├── client.ts   # TempestClient (chain-agnostic, accepts any ChainAdapter)
│   │       ├── fees.ts     # classifyRegime(), interpolateFee()
│   │       └── lp.ts       # estimateIL() — concentrated liquidity IL estimation
│   ├── evm/                # @fabrknt/tempest-evm — EVM adapter (depends on @fabrknt/tempest-core + viem)
│   │   └── src/
│   │       ├── EvmAdapter.ts      # ChainAdapter implementation for EVM/viem
│   │       ├── fees.ts            # getCurrentFee()
│   │       ├── oracle.ts          # getVolatility(), getRegime(), getVolState()
│   │       ├── lp.ts              # getRecommendedRange()
│   │       └── abis/              # Contract ABIs
│   ├── solana/              # @fabrknt/tempest-solana — Solana adapter scaffold
│   │   └── src/
│   │       ├── SolanaAdapter.ts   # ChainAdapter implementation (awaiting program deployment)
│   │       ├── pda.ts             # PDA derivation (vol_state, fee_config, tick_buffer)
│   │       └── accounts.ts       # Expected on-chain account structures
│   └── qn-addon/            # @fabrknt/tempest-qn-addon — QuickNode Marketplace add-on
│       ├── addon.json        # QN Marketplace manifest (slug: fabrknt-dynamic-fees)
│       └── src/
│           └── server.ts     # Express API (volatility, fees, LP advisory routes)
├── apps/
│   ├── keeper/             # Off-chain keeper service (TypeScript/viem)
│   └── dashboard/          # Next.js 15 frontend
```

The monorepo is managed with **pnpm** (v10.31.0) and **turbo** for build orchestration. Internal dependencies use the `workspace:*` protocol.

The SDK is split into three packages:

- **`@fabrknt/tempest-core`** — Chain-agnostic types, algorithms, and client with zero dependencies. Defines the `ChainAdapter` interface and a `TempestClient` that accepts any adapter. Use this when you only need volatility types (e.g., `Regime`, `VolState`), pure math (`estimateIL`), or want to build a custom chain adapter.
- **`@fabrknt/tempest-evm`** — EVM adapter implementing `ChainAdapter` via viem. Depends on `@fabrknt/tempest-core` and re-exports all of its types for convenience.
- **`@fabrknt/tempest-solana`** — Solana adapter scaffold implementing `ChainAdapter`. Includes PDA derivation and expected on-chain account structures. Awaiting Solana program deployment.
- **`@fabrknt/tempest-qn-addon`** — QuickNode Marketplace add-on (slug: `fabrknt-dynamic-fees`). An Express server exposing Tempest's volatility engine as a hosted API. Depends on `@fabrknt/tempest-core`.

## Contracts

### TickObserver

Gas-optimized circular buffer storing tick observations. Packs 4 observations per storage slot (56 bits each: 32-bit timestamp + 24-bit tick). Buffer holds 1024 observations.

### VolatilityEngine

Computes annualized realized volatility from tick observations:
- Time-weighted variance of tick differences (log returns)
- Regime classification (VeryLow → Extreme)
- EMA smoothing (7-day and 30-day half-lives)
- Elevated/depressed detection relative to 30d EMA

### FeeCurve

Piecewise linear vol-to-fee mapping with 6 governance-adjustable control points. Pure math, no storage reads.

### TempestHook

Main Uniswap v4 hook tying everything together:
- `afterInitialize` — registers pool, requires `DYNAMIC_FEE_FLAG`
- `beforeSwap` — returns dynamic fee with `OVERRIDE_FEE_FLAG`, staleness fail-safe, momentum boost
- `afterSwap` — records current tick to observation buffer (with dust filter)
- `updateVolatility` — keeper function, computes vol and pays dynamic gas-scaled reward
- `computeKeeperReward` — view function returning current reward amount at current gas price
- View functions for SDK: `getVolatility`, `getCurrentFee`, `getRecommendedRange`, `getVolState`

## Governance Parameters

All parameters are adjustable by the governance address via dedicated setter functions.

| Parameter | Default | Setter | Description |
|-----------|---------|--------|-------------|
| `keeperBaseReward` | 0.0005 ETH | `setKeeperReward()` | Floor ETH reward for keepers |
| `keeperGasOverhead` | 150,000 | `setKeeperReward()` | Estimated gas units per `updateVolatility` call |
| `keeperPremiumBps` | 5000 (50%) | `setKeeperReward()` | Profit margin over gas cost |
| `minUpdateInterval` | 300s (5 min) | `setMinUpdateInterval()` | Min time between vol updates |
| `staleFeeThreshold` | 3600s (1 hr) | `setStaleFeeThreshold()` | Time before fees escalate to cap |
| `feeConfig` | See [Volatility Regimes](#volatility-regimes) | `setFeeConfig()` | Per-pool fee curve control points |
| `minSwapSize` | 0 (disabled) | `setMinSwapSize()` | Per-pool min `abs(amount0)` to record observation |

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+
- [pnpm](https://pnpm.io/installation) 10.31.0+

### Install Dependencies

```bash
pnpm install   # installs all workspace packages
```

### Build

```bash
pnpm build     # runs turbo across all packages
```

### Build & Test Contracts

```bash
cd contracts
forge build
forge test
forge test --gas-report
```

### Run Core Tests

```bash
cd packages/core
pnpm test
```

### Run Keeper

```bash
cd apps/keeper
cp .env.example .env  # Configure RPC_URL, PRIVATE_KEY, HOOK_ADDRESS, POOL_IDS
pnpm start
```

The keeper automatically:
- Checks gas price before each update and compares against `maxGasGwei`
- Estimates reward profitability using on-chain parameters
- Overrides gas limits when pools approach staleness (>80% of `staleFeeThreshold`)
- Logs regime changes, actual gas used vs. estimated overhead, and profit margins
- Warns on low keeper wallet balance

### Run Dashboard

```bash
cd apps/dashboard
pnpm run dev
```

The dashboard runs with mock data by default — connect it to a deployed hook via `@fabrknt/tempest-evm` for live data.

### SDK Usage

Use `@fabrknt/tempest-core` for pure types and algorithms (no chain dependency):

```typescript
import { Regime, REGIME_NAMES, estimateIL } from "@fabrknt/tempest-core";

const il = estimateIL(5000, -1000, 1000, 30); // 30-day IL estimate at 50% vol
console.log(`Estimated IL: ${il.toFixed(2)}%`);
```

Use `@fabrknt/tempest-evm` for on-chain reads via viem:

```typescript
import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";
import { TempestClient, EvmAdapter } from "@fabrknt/tempest-evm";

const viem = createPublicClient({ chain: mainnet, transport: http() });
const adapter = new EvmAdapter(viem, "0x...");
const tempest = new TempestClient(adapter);

const { currentVol, regime } = await tempest.getVolatility(poolId);
const fee = await tempest.getCurrentFee(poolId);
const range = await tempest.getRecommendedRange(poolId, currentTick);
```

To add support for a new chain, implement the `ChainAdapter` interface from `@fabrknt/tempest-core`:

```typescript
import type { ChainAdapter } from "@fabrknt/tempest-core";

class MySvmAdapter implements ChainAdapter {
  readonly chain = "solana";
  async getVolState(poolId: string) { /* ... */ }
  async getCurrentFee(poolId: string) { /* ... */ }
  // ...
}
```

## Deployment

1. **Mine CREATE2 address** — Hook address must encode permission flags in its lower bits:
   ```bash
   DEPLOYER=0x... POOL_MANAGER=0x... GOVERNANCE=0x... forge script script/MineAddress.s.sol
   ```

2. **Deploy** — Use the mined salt:
   ```bash
   POOL_MANAGER=0x... GOVERNANCE=0x... DEPLOY_SALT=0x... forge script script/DeployTempest.s.sol --broadcast
   ```

   Optional deploy-time env vars:
   - `KEEPER_BASE_REWARD` — Floor reward in wei (default: 0.0005 ETH)
   - `KEEPER_GAS_OVERHEAD` — Estimated gas units (default: 150000)
   - `KEEPER_PREMIUM_BPS` — Profit margin bps (default: 5000)
   - `INITIAL_FUNDING` — ETH to seed the hook's reward fund (default: 1 ETH)

3. **Create pool** — Initialize a Uniswap v4 pool with `fee: LPFeeLibrary.DYNAMIC_FEE_FLAG` and `hooks: <tempest_address>`

4. **Configure pool** (optional) — Set per-pool parameters via governance:
   ```solidity
   hook.setMinSwapSize(poolId, 1e16);  // 0.01 ETH dust filter
   hook.setFeeConfig(poolId, customConfig);
   ```

5. **Start keeper** — Run the keeper service to periodically update volatility

## QuickNode Marketplace Add-on

The `packages/qn-addon` package ships Tempest as a hosted add-on on the [QuickNode Marketplace](https://marketplace.quicknode.com/) under the slug **`fabrknt-dynamic-fees`**.

### API Endpoints

| Route | Method | Description |
|-------|--------|-------------|
| `/v1/volatility/compute` | POST | Compute realized volatility from an array of price observations |
| `/v1/volatility/regime` | GET | Get current volatility regime classification for a pool |
| `/v1/volatility/history` | POST | Retrieve historical volatility data points |
| `/v1/fees/calculate` | POST | Calculate the dynamic fee for a given volatility level |
| `/v1/fees/schedule` | GET | Get the full fee schedule mapping regimes to fee tiers |
| `/v1/fees/simulate` | POST | Simulate fee revenue over a historical volatility series |
| `/v1/lp/range` | POST | Get recommended LP tick range based on current volatility |
| `/v1/lp/il-estimate` | POST | Estimate impermanent loss for a concentrated liquidity position |

### Running the Add-on Locally

```bash
cd packages/qn-addon
cp .env.example .env   # Configure as needed
pnpm dev
```

## Key Design Decisions

- **Tick-based vol**: Uniswap v4 ticks are logarithmic, so tick diffs = log returns. No expensive division.
- **Packed storage**: 4 observations per slot cuts storage costs by ~75%.
- **Keeper pattern**: Vol computation is too expensive for every swap. Off-chain keeper amortizes the cost, incentivized by gas-scaled ETH rewards.
- **Dynamic rewards**: Keeper reward = base + gas overhead x gas price x premium. Ensures keeper profitability at any gas price, preventing the "keeper goes down during high gas" failure mode.
- **Staleness fail-safe**: If the keeper stops updating, fees automatically escalate to cap. LPs are never left exposed at stale low fees during market turmoil.
- **Dust filter**: Per-pool `minSwapSize` prevents vol manipulation via cheap tiny swaps that inject artificial tick observations.
- **Momentum boost**: Fee adjusts up to 50% faster when vol is accelerating (currentVol > ema7d), partially compensating for the backward-looking nature of realized volatility.
- **Piecewise linear fees**: Simple, predictable, governance-adjustable. No complex curves or oracles.
- **No external oracles**: All data comes from the pool's own swap history. Fully self-contained.
- **Chain-agnostic core**: Pure types and algorithms in `@fabrknt/tempest-core` can be used without any EVM dependency, enabling reuse in simulations, dashboards, or other chain integrations.

## License

MIT
