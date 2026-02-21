"use client";

import { REGIME_COLORS, REGIME_NAMES, type Regime } from "@/hooks/useVolatility";

interface Props {
  regime: Regime;
  history: { time: string; regime: Regime }[];
}

export function RegimeIndicator({ regime, history }: Props) {
  const color = REGIME_COLORS[regime];

  // Get last 5 regime transitions
  const transitions: { time: string; from: Regime; to: Regime }[] = [];
  for (let i = 1; i < history.length && transitions.length < 5; i++) {
    if (history[i].regime !== history[i - 1].regime) {
      transitions.push({
        time: history[i].time,
        from: history[i - 1].regime,
        to: history[i].regime,
      });
    }
  }

  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--bg-card)] p-6">
      <h3 className="mb-4 text-sm font-medium text-[var(--text-secondary)]">
        Current Regime
      </h3>

      <div className="flex items-center gap-3">
        <div
          className="h-4 w-4 rounded-full"
          style={{
            backgroundColor: color,
            boxShadow: `0 0 12px ${color}60`,
            animation: "pulse-glow 2s ease-in-out infinite",
          }}
        />
        <span className="text-2xl font-bold" style={{ color }}>
          {REGIME_NAMES[regime]}
        </span>
      </div>

      {transitions.length > 0 && (
        <div className="mt-4">
          <p className="mb-2 text-xs text-[var(--text-muted)]">
            Recent Transitions
          </p>
          <div className="space-y-1">
            {transitions.slice(-3).map((t, i) => (
              <div
                key={i}
                className="flex items-center gap-2 text-xs text-[var(--text-secondary)]"
              >
                <span className="text-[var(--text-muted)]">{t.time}</span>
                <span style={{ color: REGIME_COLORS[t.from] }}>
                  {REGIME_NAMES[t.from]}
                </span>
                <span className="text-[var(--text-muted)]">&rarr;</span>
                <span style={{ color: REGIME_COLORS[t.to] }}>
                  {REGIME_NAMES[t.to]}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
