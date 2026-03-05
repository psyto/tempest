"use client";

import { REGIME_COLORS, REGIME_NAMES, type Regime } from "@/hooks/useVolatility";

interface Props {
  regime: Regime;
  recommendedRange: { lower: number; upper: number };
  currentVol: number;
}

export function LPRangeAdvisor({ regime, recommendedRange, currentVol }: Props) {
  const color = REGIME_COLORS[regime];
  const rangeWidth = recommendedRange.upper - recommendedRange.lower;
  // Each tick ≈ 0.01% price change, so range width in % ≈ rangeWidth * 0.01
  const rangePct = (rangeWidth * 0.01).toFixed(1);

  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--bg-card)] p-6">
      <h3 className="mb-4 text-sm font-medium text-[var(--text-secondary)]">
        LP Range Advisor
      </h3>

      <div className="mb-4 rounded-xl border border-[var(--border)] bg-[var(--bg-primary)] p-4">
        <div className="mb-3 flex items-center justify-between">
          <span className="text-xs text-[var(--text-muted)]">
            Recommended Range
          </span>
          <span
            className="rounded-full px-2 py-0.5 text-xs font-medium"
            style={{ backgroundColor: `${color}20`, color }}
          >
            {REGIME_NAMES[regime]} Vol
          </span>
        </div>

        <div className="flex items-center justify-between gap-4">
          <div className="text-center">
            <p className="text-xs text-[var(--text-muted)]">Lower Tick</p>
            <p className="mt-1 font-mono text-lg font-bold text-[var(--text-primary)]">
              {recommendedRange.lower.toLocaleString()}
            </p>
          </div>

          <div className="flex-1">
            <div className="relative h-2 rounded-full bg-[var(--border)]">
              <div
                className="absolute inset-y-0 rounded-full"
                style={{
                  left: "10%",
                  right: "10%",
                  backgroundColor: `${color}40`,
                  border: `1px solid ${color}`,
                }}
              />
              <div
                className="absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white"
                style={{ left: "50%" }}
              />
            </div>
          </div>

          <div className="text-center">
            <p className="text-xs text-[var(--text-muted)]">Upper Tick</p>
            <p className="mt-1 font-mono text-lg font-bold text-[var(--text-primary)]">
              {recommendedRange.upper.toLocaleString()}
            </p>
          </div>
        </div>

        <p className="mt-3 text-center text-xs text-[var(--text-muted)]">
          Range width: <span className="font-medium text-[var(--text-secondary)]">{rangePct}%</span> ({rangeWidth.toLocaleString()} ticks)
        </p>
      </div>

      <div className="space-y-2 text-xs text-[var(--text-muted)]">
        <p>
          {regime <= 1
            ? "Low volatility environment. Tighter ranges capture more fees with lower IL risk."
            : regime <= 2
              ? "Normal volatility. Moderate range balances fee capture against rebalancing frequency."
              : "Elevated volatility. Wider ranges protect against impermanent loss from large price swings."}
        </p>
      </div>
    </div>
  );
}
