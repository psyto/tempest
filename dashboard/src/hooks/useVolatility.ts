"use client";

import { useState, useEffect, useCallback } from "react";

export enum Regime {
  VeryLow = 0,
  Low = 1,
  Normal = 2,
  High = 3,
  Extreme = 4,
}

export const REGIME_NAMES: Record<Regime, string> = {
  [Regime.VeryLow]: "Very Low",
  [Regime.Low]: "Low",
  [Regime.Normal]: "Normal",
  [Regime.High]: "High",
  [Regime.Extreme]: "Extreme",
};

export const REGIME_COLORS: Record<Regime, string> = {
  [Regime.VeryLow]: "#22c55e",
  [Regime.Low]: "#3b82f6",
  [Regime.Normal]: "#eab308",
  [Regime.High]: "#f97316",
  [Regime.Extreme]: "#ef4444",
};

export interface VolData {
  vol: number;
  regime: Regime;
  ema7d: number;
  ema30d: number;
  loading: boolean;
  history: { time: string; vol: number; regime: Regime }[];
}

function classifyRegime(vol: number): Regime {
  if (vol <= 2000) return Regime.VeryLow;
  if (vol <= 3500) return Regime.Low;
  if (vol <= 5000) return Regime.Normal;
  if (vol <= 7500) return Regime.High;
  return Regime.Extreme;
}

// Mock data generator for demo purposes
function generateMockVol(prevVol: number): number {
  const change = (Math.random() - 0.48) * 400;
  return Math.max(100, Math.min(12000, prevVol + change));
}

export function useVolatility(pollIntervalMs: number = 5000): VolData {
  const [vol, setVol] = useState(3200);
  const [ema7d, setEma7d] = useState(3000);
  const [ema30d, setEma30d] = useState(2800);
  const [loading, setLoading] = useState(true);
  const [history, setHistory] = useState<
    { time: string; vol: number; regime: Regime }[]
  >([]);

  const update = useCallback(() => {
    setVol((prev) => {
      const newVol = generateMockVol(prev);
      setEma7d((e) => e + (newVol - e) * 0.1);
      setEma30d((e) => e + (newVol - e) * 0.03);

      const now = new Date();
      const timeStr = `${now.getHours().toString().padStart(2, "0")}:${now.getMinutes().toString().padStart(2, "0")}:${now.getSeconds().toString().padStart(2, "0")}`;

      setHistory((h) => {
        const entry = { time: timeStr, vol: Math.round(newVol), regime: classifyRegime(newVol) };
        const updated = [...h, entry];
        return updated.slice(-60);
      });

      setLoading(false);
      return newVol;
    });
  }, []);

  useEffect(() => {
    // Initialize with some history
    const now = Date.now();
    let mockVol = 3200;
    const initialHistory = [];
    for (let i = 59; i >= 0; i--) {
      mockVol = generateMockVol(mockVol);
      const time = new Date(now - i * pollIntervalMs);
      initialHistory.push({
        time: `${time.getHours().toString().padStart(2, "0")}:${time.getMinutes().toString().padStart(2, "0")}:${time.getSeconds().toString().padStart(2, "0")}`,
        vol: Math.round(mockVol),
        regime: classifyRegime(mockVol),
      });
    }
    setHistory(initialHistory);
    setVol(mockVol);
    setLoading(false);

    const interval = setInterval(update, pollIntervalMs);
    return () => clearInterval(interval);
  }, [pollIntervalMs, update]);

  return {
    vol: Math.round(vol),
    regime: classifyRegime(vol),
    ema7d: Math.round(ema7d),
    ema30d: Math.round(ema30d),
    loading,
    history,
  };
}
