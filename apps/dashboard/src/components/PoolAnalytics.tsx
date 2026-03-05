"use client";

interface Props {
  observationCount: number;
  volume24h: number;
  feesEarned24h: number;
  lastUpdate: Date;
  currentFee: number;
  ema7d: number;
  ema30d: number;
}

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000) return `$${(n / 1_000).toFixed(1)}K`;
  return `$${n.toFixed(2)}`;
}

export function PoolAnalytics({
  observationCount,
  volume24h,
  feesEarned24h,
  lastUpdate,
  currentFee,
  ema7d,
  ema30d,
}: Props) {
  const stats = [
    {
      label: "24h Volume",
      value: formatNumber(volume24h),
    },
    {
      label: "24h Fees",
      value: formatNumber(feesEarned24h),
    },
    {
      label: "Dynamic Fee",
      value: `${(currentFee / 100).toFixed(2)}%`,
    },
    {
      label: "Observations",
      value: `${observationCount} / 1024`,
    },
    {
      label: "7d EMA",
      value: `${(ema7d / 100).toFixed(1)}%`,
    },
    {
      label: "30d EMA",
      value: `${(ema30d / 100).toFixed(1)}%`,
    },
  ];

  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--bg-card)] p-6">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-sm font-medium text-[var(--text-secondary)]">
          Pool Analytics
        </h3>
        <span className="text-xs text-[var(--text-muted)]">
          Updated{" "}
          {lastUpdate.toLocaleTimeString(undefined, {
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
          })}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
        {stats.map((stat) => (
          <div key={stat.label}>
            <p className="text-xs text-[var(--text-muted)]">{stat.label}</p>
            <p className="mt-1 text-lg font-semibold text-[var(--text-primary)]">
              {stat.value}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
