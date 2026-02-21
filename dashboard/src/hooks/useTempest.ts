"use client";

import { useState, useEffect } from "react";
import { useVolatility, type Regime } from "./useVolatility";

export interface TempestData {
  currentFee: number;
  observationCount: number;
  isInitialized: boolean;
  recommendedRange: { lower: number; upper: number };
  volume24h: number;
  feesEarned24h: number;
  lastUpdate: Date;
}

function getFeeForVol(vol: number): number {
  // Piecewise linear interpolation matching FeeCurve defaults
  const points = [
    [0, 5],
    [2000, 10],
    [3500, 30],
    [5000, 60],
    [7500, 150],
    [15000, 500],
  ];

  if (vol <= points[0][0]) return points[0][1];
  if (vol >= points[points.length - 1][0]) return points[points.length - 1][1];

  for (let i = 1; i < points.length; i++) {
    if (vol <= points[i][0]) {
      const [v0, f0] = points[i - 1];
      const [v1, f1] = points[i];
      return f0 + ((f1 - f0) * (vol - v0)) / (v1 - v0);
    }
  }
  return 500;
}

function getRangeForRegime(regime: Regime, currentTick: number = 0) {
  const halfWidths: Record<number, number> = {
    0: 200,
    1: 500,
    2: 1000,
    3: 2000,
    4: 4000,
  };
  const hw = halfWidths[regime] ?? 1000;
  return { lower: currentTick - hw, upper: currentTick + hw };
}

export function useTempest(): TempestData & ReturnType<typeof useVolatility> {
  const volData = useVolatility(3000);
  const [observationCount, setObservationCount] = useState(847);

  useEffect(() => {
    const interval = setInterval(() => {
      setObservationCount((c) => Math.min(c + 1, 1024));
    }, 15000);
    return () => clearInterval(interval);
  }, []);

  return {
    ...volData,
    currentFee: Math.round(getFeeForVol(volData.vol)),
    observationCount,
    isInitialized: true,
    recommendedRange: getRangeForRegime(volData.regime),
    volume24h: 2_430_000 + Math.random() * 100_000,
    feesEarned24h: 7_290 + Math.random() * 500,
    lastUpdate: new Date(),
  };
}
