"use client";

import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceDot,
} from "recharts";

interface Props {
  currentVol: number;
  currentFee: number;
}

const FEE_CURVE_DATA = [
  { vol: 0, fee: 5 },
  { vol: 500, fee: 6 },
  { vol: 1000, fee: 7 },
  { vol: 1500, fee: 9 },
  { vol: 2000, fee: 10 },
  { vol: 2500, fee: 17 },
  { vol: 3000, fee: 23 },
  { vol: 3500, fee: 30 },
  { vol: 4000, fee: 40 },
  { vol: 4500, fee: 50 },
  { vol: 5000, fee: 60 },
  { vol: 5500, fee: 78 },
  { vol: 6000, fee: 96 },
  { vol: 6500, fee: 114 },
  { vol: 7000, fee: 132 },
  { vol: 7500, fee: 150 },
  { vol: 8500, fee: 197 },
  { vol: 10000, fee: 267 },
  { vol: 12000, fee: 360 },
  { vol: 15000, fee: 500 },
];

export function FeeSchedule({ currentVol, currentFee }: Props) {
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--bg-card)] p-6">
      <h3 className="mb-1 text-sm font-medium text-[var(--text-secondary)]">
        Fee Curve
      </h3>
      <p className="mb-4 text-xs text-[var(--text-muted)]">
        Current fee:{" "}
        <span className="font-semibold text-[var(--text-primary)]">
          {(currentFee / 100).toFixed(2)}%
        </span>{" "}
        ({currentFee} bps)
      </p>

      <div className="h-48">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={FEE_CURVE_DATA}>
            <XAxis
              dataKey="vol"
              tick={{ fill: "#71717a", fontSize: 10 }}
              axisLine={{ stroke: "#27272a" }}
              tickLine={false}
              tickFormatter={(v: number) => `${(v / 100).toFixed(0)}%`}
              label={{
                value: "Volatility",
                position: "insideBottom",
                offset: -5,
                fill: "#71717a",
                fontSize: 10,
              }}
            />
            <YAxis
              tick={{ fill: "#71717a", fontSize: 10 }}
              axisLine={{ stroke: "#27272a" }}
              tickLine={false}
              tickFormatter={(v: number) => `${v}bp`}
              label={{
                value: "Fee",
                angle: -90,
                position: "insideLeft",
                fill: "#71717a",
                fontSize: 10,
              }}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: "#111118",
                border: "1px solid #27272a",
                borderRadius: "8px",
                color: "#fafafa",
              }}
              formatter={(value: number, name: string) => [
                name === "fee"
                  ? `${value} bps (${(value / 100).toFixed(2)}%)`
                  : value,
                "Fee",
              ]}
              labelFormatter={(v: number) =>
                `Vol: ${(v / 100).toFixed(1)}%`
              }
            />
            <Line
              type="monotone"
              dataKey="fee"
              stroke="#8b5cf6"
              strokeWidth={2}
              dot={false}
            />
            <ReferenceDot
              x={currentVol}
              y={currentFee}
              r={6}
              fill="#8b5cf6"
              stroke="#fafafa"
              strokeWidth={2}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
