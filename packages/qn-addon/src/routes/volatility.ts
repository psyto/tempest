import { Router, Request, Response } from "express";
import { instanceLookup } from "../middleware/instance-lookup";
import { Regime, REGIME_NAMES, classifyRegime } from "@fabrknt/tempest-core";

const router: import("express").Router = Router();

/* ------------------------------------------------------------------ */
/*  Shared middleware: all volatility routes require an active instance */
/* ------------------------------------------------------------------ */
router.use(instanceLookup);

/* ------------------------------------------------------------------ */
/*  POST /compute — Compute realized volatility from price observations */
/* ------------------------------------------------------------------ */
router.post("/compute", (req: Request, res: Response) => {
  try {
    const { prices, windowSeconds } = req.body as {
      prices: number[];
      windowSeconds?: number;
    };

    if (!prices || !Array.isArray(prices) || prices.length < 2) {
      res.status(400).json({
        error: "prices must be an array of at least 2 numeric observations",
      });
      return;
    }

    const window = windowSeconds ?? 86400; // default 24h

    // --- Mock computation ---
    // In production this delegates to @fabrknt/tempest-core vol computation
    const logReturns: number[] = [];
    for (let i = 1; i < prices.length; i++) {
      logReturns.push(Math.log(prices[i] / prices[i - 1]));
    }
    const mean = logReturns.reduce((a, b) => a + b, 0) / logReturns.length;
    const variance =
      logReturns.reduce((a, r) => a + (r - mean) ** 2, 0) /
      (logReturns.length - 1);
    const stdDev = Math.sqrt(variance);

    // Annualize: assume observations are evenly spaced within windowSeconds
    const periodsPerYear = (365.25 * 86400) / window;
    const annualizedVol = stdDev * Math.sqrt(periodsPerYear);
    const volBps = Math.round(annualizedVol * 10000);

    // Classify regime
    const regime = classifyRegime(volBps);

    res.json({
      volBps,
      annualizedVol: parseFloat(annualizedVol.toFixed(6)),
      regime: Regime[regime],
      regimeLabel: REGIME_NAMES[regime],
      sampleCount: prices.length,
      windowSeconds: window,
    });
  } catch (err) {
    console.error("[volatility/compute] error:", err);
    res.status(500).json({ error: "Volatility computation failed" });
  }
});

/* ------------------------------------------------------------------ */
/*  GET /regime — Get current regime classification for a pool        */
/* ------------------------------------------------------------------ */
router.get("/regime", (req: Request, res: Response) => {
  try {
    const poolId = req.query.poolId as string | undefined;

    if (!poolId) {
      res.status(400).json({ error: "Missing poolId query parameter" });
      return;
    }

    // --- Mock: return a placeholder regime ---
    // In production this reads from on-chain state or cached vol data
    const mockRegime = Regime.Normal;

    res.json({
      poolId,
      regime: Regime[mockRegime],
      regimeLabel: REGIME_NAMES[mockRegime],
      currentVolBps: 850,
      ema7dBps: 920,
      ema30dBps: 780,
      lastUpdate: Math.floor(Date.now() / 1000),
    });
  } catch (err) {
    console.error("[volatility/regime] error:", err);
    res.status(500).json({ error: "Regime lookup failed" });
  }
});

/* ------------------------------------------------------------------ */
/*  POST /history — Get historical vol data points                    */
/* ------------------------------------------------------------------ */
router.post("/history", (req: Request, res: Response) => {
  try {
    const { poolId, startTime, endTime, granularity } = req.body as {
      poolId: string;
      startTime: number;
      endTime?: number;
      granularity?: "1h" | "4h" | "1d";
    };

    if (!poolId || !startTime) {
      res.status(400).json({ error: "Missing poolId or startTime" });
      return;
    }

    const end = endTime ?? Math.floor(Date.now() / 1000);
    const gran = granularity ?? "1h";
    const stepSeconds = gran === "1d" ? 86400 : gran === "4h" ? 14400 : 3600;

    // --- Mock: generate sample data points ---
    const samples: Array<{
      timestamp: number;
      volBps: number;
      regime: string;
    }> = [];

    for (let t = startTime; t <= end; t += stepSeconds) {
      const mockVol = 500 + Math.round(Math.sin(t / 10000) * 300);
      const regime = classifyRegime(mockVol);

      samples.push({
        timestamp: t,
        volBps: mockVol,
        regime: Regime[regime],
      });

      if (samples.length >= 500) break; // cap response size
    }

    res.json({
      poolId,
      granularity: gran,
      startTime,
      endTime: end,
      count: samples.length,
      samples,
    });
  } catch (err) {
    console.error("[volatility/history] error:", err);
    res.status(500).json({ error: "History retrieval failed" });
  }
});

export { router as volatilityRoutes };
