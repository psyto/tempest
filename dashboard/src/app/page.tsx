"use client";

import { useTempest } from "@/hooks/useTempest";
import { VolatilityGauge } from "@/components/VolatilityGauge";
import { RegimeIndicator } from "@/components/RegimeIndicator";
import { VolChart } from "@/components/VolChart";
import { FeeSchedule } from "@/components/FeeSchedule";
import { PoolAnalytics } from "@/components/PoolAnalytics";
import { LPRangeAdvisor } from "@/components/LPRangeAdvisor";

export default function Dashboard() {
  const data = useTempest();

  if (data.loading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <div className="text-[var(--text-muted)]">Loading...</div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-3xl font-bold tracking-tight text-[var(--text-primary)]">
          Tempest
        </h1>
        <p className="mt-1 text-sm text-[var(--text-muted)]">
          Volatility-responsive dynamic fee hook for Uniswap v4
        </p>
      </div>

      {/* Top row: Gauge + Regime */}
      <div className="mb-6 grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
        <VolatilityGauge vol={data.vol} regime={data.regime} />
        <RegimeIndicator regime={data.regime} history={data.history} />
        <LPRangeAdvisor
          regime={data.regime}
          recommendedRange={data.recommendedRange}
          currentVol={data.vol}
        />
      </div>

      {/* Middle row: Charts */}
      <div className="mb-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <VolChart history={data.history} />
        <FeeSchedule currentVol={data.vol} currentFee={data.currentFee} />
      </div>

      {/* Bottom: Analytics */}
      <PoolAnalytics
        observationCount={data.observationCount}
        volume24h={data.volume24h}
        feesEarned24h={data.feesEarned24h}
        lastUpdate={data.lastUpdate}
        currentFee={data.currentFee}
        ema7d={data.ema7d}
        ema30d={data.ema30d}
      />
    </div>
  );
}
