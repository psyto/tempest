"use client";

import { REGIME_COLORS, REGIME_NAMES, type Regime } from "@/hooks/useVolatility";

interface Props {
  vol: number;
  regime: Regime;
}

export function VolatilityGauge({ vol, regime }: Props) {
  const color = REGIME_COLORS[regime];
  const volPct = (vol / 100).toFixed(1);
  // Map vol 0-15000 bps to gauge angle 0-270 degrees
  const angle = Math.min((vol / 15000) * 270, 270);

  const cx = 100;
  const cy = 100;
  const r = 80;
  const startAngle = 135; // degrees, starting from bottom-left
  const endAngle = startAngle + angle;

  const toRadians = (deg: number) => (deg * Math.PI) / 180;

  const arcStart = {
    x: cx + r * Math.cos(toRadians(startAngle)),
    y: cy + r * Math.sin(toRadians(startAngle)),
  };
  const arcEnd = {
    x: cx + r * Math.cos(toRadians(endAngle)),
    y: cy + r * Math.sin(toRadians(endAngle)),
  };
  const largeArc = angle > 180 ? 1 : 0;

  const bgArcEnd = {
    x: cx + r * Math.cos(toRadians(startAngle + 270)),
    y: cy + r * Math.sin(toRadians(startAngle + 270)),
  };

  return (
    <div className="flex flex-col items-center rounded-2xl border border-[var(--border)] bg-[var(--bg-card)] p-6">
      <h3 className="mb-4 text-sm font-medium text-[var(--text-secondary)]">
        Realized Volatility
      </h3>
      <svg viewBox="0 0 200 160" className="h-48 w-48">
        {/* Background arc */}
        <path
          d={`M ${arcStart.x} ${arcStart.y} A ${r} ${r} 0 1 1 ${bgArcEnd.x} ${bgArcEnd.y}`}
          fill="none"
          stroke="#27272a"
          strokeWidth="12"
          strokeLinecap="round"
        />
        {/* Value arc */}
        {angle > 0 && (
          <path
            d={`M ${arcStart.x} ${arcStart.y} A ${r} ${r} 0 ${largeArc} 1 ${arcEnd.x} ${arcEnd.y}`}
            fill="none"
            stroke={color}
            strokeWidth="12"
            strokeLinecap="round"
            style={{
              filter: `drop-shadow(0 0 8px ${color}40)`,
              transition: "d 0.5s ease-out",
            }}
          />
        )}
        {/* Center text */}
        <text
          x={cx}
          y={cy - 8}
          textAnchor="middle"
          className="text-3xl font-bold"
          fill={color}
          style={{ fontSize: "28px", fontWeight: 700 }}
        >
          {volPct}%
        </text>
        <text
          x={cx}
          y={cy + 16}
          textAnchor="middle"
          fill="#a1a1aa"
          style={{ fontSize: "12px" }}
        >
          annualized
        </text>
      </svg>
      <div
        className="mt-2 rounded-full px-3 py-1 text-xs font-semibold"
        style={{ backgroundColor: `${color}20`, color }}
      >
        {REGIME_NAMES[regime]}
      </div>
    </div>
  );
}
