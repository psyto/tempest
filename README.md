# Tempest

Volatility-responsive dynamic fee hook for Uniswap v4.

Tempest dynamically adjusts swap fees based on real-time realized volatility computed from pool swap data. All existing AMMs use static or manually-adjusted fees — Tempest automates this, protecting LPs during vol spikes and attracting volume during calm markets.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  TempestHook.sol                  │
│         (Uniswap v4 IHooks implementation)       │
│                                                   │
│  afterInitialize ── register pool with oracle     │
│  afterSwap ─────── record tick to TickObserver    │
│  beforeSwap ────── read vol → FeeCurve → fee      │
│                                                   │
│  ┌──────────────┐ ┌──────────────┐ ┌───────────┐ │
│  │ TickObserver  │ │ VolatilityEng│ │ FeeCurve  │ │
│  │ (lib)        │ │ (lib)        │ │ (lib)     │ │
│  │              │ │              │ │           │ │
│  │ Circular buf │ │ Realized vol │ │ Vol→Fee   │ │
│  │ 4 obs/slot   │ │ Regime detect│ │ Piecewise │ │
│  │              │ │ EMA smoothing│ │ linear    │ │
│  └──────────────┘ └──────────────┘ └───────────┘ │
└─────────────────────────────────────────────────┘
         │                    ▲
         │ tick data          │ updateVolatility()
         ▼                    │
    PoolManager          Keeper Service
    (Uniswap v4)         (TypeScript)
```

## How It Works

1. **Every swap** — `afterSwap` records the current tick into a gas-optimized circular buffer (4 observations packed per storage slot, 1024 capacity)
2. **Periodically** — A keeper calls `updateVolatility()`, which computes annualized realized vol from tick observations and classifies the market regime
3. **Next swap** — `beforeSwap` reads the current vol regime and returns a dynamic fee via piecewise linear interpolation

Since Uniswap v4 ticks are `log₁.₀₀₀₁(price)`, tick differences ARE log returns — no division needed for variance computation.

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
│   ├── test/               # 80 tests (unit + integration + fuzz)
│   └── script/             # Deployment & CREATE2 mining
├── packages/
│   ├── core/               # @tempest/core — pure types & algorithms (no dependencies)
│   │   └── src/
│   │       ├── types.ts    # Regime, VolState, FeeConfig, PoolInfo, VolSample
│   │       └── lp.ts       # estimateIL() — concentrated liquidity IL estimation
│   ├── evm/                # @tempest/evm — EVM client (depends on @tempest/core + viem)
│   │   └── src/
│   │       ├── TempestClient.ts   # PublicClient facade
│   │       ├── fees.ts            # getCurrentFee()
│   │       ├── oracle.ts          # getVolatility(), getRegime(), getVolState()
│   │       ├── lp.ts              # getRecommendedRange()
│   │       └── abis/              # Contract ABIs
│   └── qn-addon/            # @tempest/qn-addon — QuickNode Marketplace add-on
│       ├── addon.json        # QN Marketplace manifest (slug: fabrknt-dynamic-fees)
│       └── src/
│           └── server.ts     # Express API (volatility, fees, LP advisory routes)
├── apps/
│   ├── keeper/             # Off-chain keeper service (TypeScript/viem)
│   └── dashboard/          # Next.js 15 frontend
```

The monorepo is managed with **pnpm** (v10.31.0) and **turbo** for build orchestration. Internal dependencies use the `workspace:*` protocol.

The SDK is split into two packages:

- **`@tempest/core`** — Pure TypeScript types and algorithms with zero dependencies. Use this when you only need volatility types (e.g., `Regime`, `VolState`) or pure math (`estimateIL`) without any chain interaction.
- **`@tempest/evm`** — EVM-specific client built on viem. Depends on `@tempest/core` and re-exports all of its types for convenience.
- **`@tempest/qn-addon`** — QuickNode Marketplace add-on (slug: `fabrknt-dynamic-fees`). An Express server exposing Tempest's volatility engine as a hosted API. Depends on `@tempest/core`.

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
- `beforeSwap` — returns dynamic fee with `OVERRIDE_FEE_FLAG`
- `afterSwap` — records current tick to observation buffer
- `updateVolatility` — keeper function, computes vol and pays reward
- View functions for SDK: `getVolatility`, `getCurrentFee`, `getRecommendedRange`

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

### Run Dashboard

```bash
cd apps/dashboard
pnpm run dev
```

The dashboard runs with mock data by default — connect it to a deployed hook via `@tempest/evm` for live data.

### SDK Usage

Use `@tempest/core` for pure types and algorithms (no chain dependency):

```typescript
import { Regime, REGIME_NAMES, estimateIL } from "@tempest/core";

const il = estimateIL(5000, -1000, 1000, 30); // 30-day IL estimate at 50% vol
console.log(`Estimated IL: ${il.toFixed(2)}%`);
```

Use `@tempest/evm` for on-chain reads via viem:

```typescript
import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";
import { TempestClient } from "@tempest/evm";

const client = createPublicClient({ chain: mainnet, transport: http() });
const tempest = new TempestClient(client, "0x...");

const { currentVol, regime } = await tempest.getVolatility(poolId);
const fee = await tempest.getCurrentFee(poolId);
const range = await tempest.getRecommendedRange(poolId, currentTick);
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

3. **Create pool** — Initialize a Uniswap v4 pool with `fee: LPFeeLibrary.DYNAMIC_FEE_FLAG` and `hooks: <tempest_address>`

4. **Start keeper** — Run the keeper service to periodically update volatility

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
- **Keeper pattern**: Vol computation is too expensive for every swap. Off-chain keeper amortizes the cost, incentivized by ETH rewards.
- **Piecewise linear fees**: Simple, predictable, governance-adjustable. No complex curves or oracles.
- **No external oracles**: All data comes from the pool's own swap history. Fully self-contained.
- **Chain-agnostic core**: Pure types and algorithms in `@tempest/core` can be used without any EVM dependency, enabling reuse in simulations, dashboards, or other chain integrations.

## License

MIT
