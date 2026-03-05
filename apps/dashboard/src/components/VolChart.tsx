"use client";

import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceArea,
} from "recharts";
import { REGIME_COLORS, type Regime } from "@/hooks/useVolatility";

interface Props {
  history: { time: string; vol: number; regime: Regime }[];
}

export function VolChart({ history }: Props) {
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--bg-card)] p-6">
      <h3 className="mb-4 text-sm font-medium text-[var(--text-secondary)]">
        Volatility Over Time
      </h3>

      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={history}>
            {/* Regime bands */}
            <ReferenceArea y1={0} y2={2000} fill="#22c55e" fillOpacity={0.05} />
            <ReferenceArea
              y1={2000}
              y2={3500}
              fill="#3b82f6"
              fillOpacity={0.05}
            />
            <ReferenceArea
              y1={3500}
              y2={5000}
              fill="#eab308"
              fillOpacity={0.05}
            />
            <ReferenceArea
              y1={5000}
              y2={7500}
              fill="#f97316"
              fillOpacity={0.05}
            />
            <ReferenceArea
              y1={7500}
              y2={15000}
              fill="#ef4444"
              fillOpacity={0.05}
            />

            <XAxis
              dataKey="time"
              tick={{ fill: "#71717a", fontSize: 10 }}
              axisLine={{ stroke: "#27272a" }}
              tickLine={false}
              interval="preserveStartEnd"
            />
            <YAxis
              tick={{ fill: "#71717a", fontSize: 10 }}
              axisLine={{ stroke: "#27272a" }}
              tickLine={false}
              domain={[0, "auto"]}
              tickFormatter={(v: number) => `${(v / 100).toFixed(0)}%`}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: "#111118",
                border: "1px solid #27272a",
                borderRadius: "8px",
                color: "#fafafa",
              }}
              formatter={(value: number) => [
                `${(value / 100).toFixed(1)}%`,
                "Vol",
              ]}
            />
            <defs>
              <linearGradient id="volGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3} />
                <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
              </linearGradient>
            </defs>
            <Area
              type="monotone"
              dataKey="vol"
              stroke="#3b82f6"
              fill="url(#volGradient)"
              strokeWidth={2}
              dot={false}
              animationDuration={300}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Legend */}
      <div className="mt-3 flex flex-wrap gap-3">
        {(
          [
            ["Very Low", "#22c55e"],
            ["Low", "#3b82f6"],
            ["Normal", "#eab308"],
            ["High", "#f97316"],
            ["Extreme", "#ef4444"],
          ] as const
        ).map(([name, color]) => (
          <div key={name} className="flex items-center gap-1.5 text-xs">
            <div
              className="h-2 w-2 rounded-full"
              style={{ backgroundColor: color }}
            />
            <span className="text-[var(--text-muted)]">{name}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
