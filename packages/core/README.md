# @fabrknt/tempest-core

Chain-agnostic types, algorithms, and client for Tempest -- volatility-responsive dynamic fee management for AMMs.

Not every DeFi protocol needs TradFi compliance -- but if yours does, you shouldn't have to rebuild from scratch. Fabrknt plugs into your existing protocol with composable SDKs and APIs. No permissioned forks, no separate deployments.

## Install

```bash
npm install @fabrknt/tempest-core
```

## Quick Start

```typescript
import {
  TempestClient,
  classifyRegime,
  interpolateFee,
  estimateIL,
  Regime,
  DEFAULT_FEE_CONFIG,
} from "@fabrknt/tempest-core";

// Pure math -- no chain connection required
const regime = classifyRegime(4500n); // Regime.Normal
const fee = interpolateFee(4500n, DEFAULT_FEE_CONFIG); // fee in bps
const il = estimateIL(5000, -1000, 1000, 30); // 30-day IL estimate

// With a chain adapter (e.g., @fabrknt/tempest-evm)
const client = new TempestClient(adapter);
const vol = await client.getVolatility(poolId);
const currentFee = await client.getCurrentFee(poolId);
```

## Features

- Zero runtime dependencies -- pure TypeScript
- Volatility regime classification (VeryLow through Extreme)
- Piecewise linear vol-to-fee interpolation with configurable breakpoints
- Concentrated liquidity impermanent loss estimation
- Chain-agnostic `TempestClient` that accepts any `ChainAdapter` implementation
- Default fee configuration matching on-chain Uniswap v4 hook parameters
- ESM module with full TypeScript type exports
- Plug-in architecture: bring your own chain adapter (EVM, SVM, or custom)

## API Summary

### Functions

| Export | Description |
|--------|-------------|
| `classifyRegime(volBps)` | Map volatility (bps) to a `Regime` enum |
| `interpolateFee(volBps, config)` | Compute dynamic fee from volatility via piecewise linear curve |
| `estimateIL(volBps, rangeLower, rangeUpper, days)` | Estimate impermanent loss for a concentrated LP position |

### Classes

| Export | Description |
|--------|-------------|
| `TempestClient` | Chain-agnostic client wrapping any `ChainAdapter`. Methods: `getVolatility()`, `getCurrentFee()`, `getRecommendedRange()`, `estimateIL()` |

### Types

| Export | Description |
|--------|-------------|
| `Regime` | Enum: `VeryLow`, `Low`, `Normal`, `High`, `Extreme` |
| `VolState` | Current volatility state (vol, regime, EMAs, timestamps) |
| `FeeConfig` | Six-point piecewise linear fee curve configuration |
| `PoolInfo` | Pool metadata |
| `VolSample` | Historical volatility data point |
| `RecommendedRange` | Suggested LP tick range |
| `Chain` / `ChainAdapter` | Interface for plugging in chain-specific adapters |

### Constants

| Export | Description |
|--------|-------------|
| `DEFAULT_FEE_CONFIG` | Default fee curve matching on-chain defaults |
| `REGIME_NAMES` | Human-readable regime labels |
| `REGIME_COLORS` | Display colors per regime |

## Chain Adapters

This package defines the `ChainAdapter` interface. Implementations are provided by separate packages:

- `@fabrknt/tempest-evm` -- EVM/viem adapter
- `@fabrknt/tempest-solana` -- Solana adapter

To build a custom adapter, implement the `ChainAdapter` interface from this package.

## Documentation

See the [main repository README](https://github.com/fabrknt/tempest) for full architecture docs, contract details, deployment instructions, and keeper configuration.

## License

MIT
