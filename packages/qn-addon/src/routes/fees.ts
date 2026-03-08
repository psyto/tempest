import { Router, Request, Response } from "express";
import { instanceLookup } from "../middleware/instance-lookup";
import { Regime, REGIME_NAMES } from "@tempest/core";

const router: import("express").Router = Router();

/* ------------------------------------------------------------------ */
/*  Shared middleware: all fee routes require an active instance       */
/* ------------------------------------------------------------------ */
router.use(instanceLookup);

/* ------------------------------------------------------------------ */
/*  Default fee schedule — piecewise linear vol-to-fee mapping        */
/* ------------------------------------------------------------------ */
const DEFAULT_FEE_SCHEDULE = [
  { regime: Regime.VeryLow, volFloorBps: 0, volCeilBps: 200, feeBps: 1 },
  { regime: Regime.Low, volFloorBps: 200, volCeilBps: 500, feeBps: 5 },
  { regime: Regime.Normal, volFloorBps: 500, volCeilBps: 1500, feeBps: 30 },
  { regime: Regime.High, volFloorBps: 1500, volCeilBps: 3000, feeBps: 60 },
  { regime: Regime.Extreme, volFloorBps: 3000, volCeilBps: 10000, feeBps: 100 },
];

function interpolateFee(volBps: number): number {
  for (const tier of DEFAULT_FEE_SCHEDULE) {
    if (volBps >= tier.volFloorBps && volBps < tier.volCeilBps) {
      return tier.feeBps;
    }
  }
  // Above all tiers — use max fee
  return DEFAULT_FEE_SCHEDULE[DEFAULT_FEE_SCHEDULE.length - 1].feeBps;
}

function classifyRegime(volBps: number): Regime {
  if (volBps < 200) return Regime.VeryLow;
  if (volBps < 500) return Regime.Low;
  if (volBps < 1500) return Regime.Normal;
  if (volBps < 3000) return Regime.High;
  return Regime.Extreme;
}

/* ------------------------------------------------------------------ */
/*  POST /calculate — Calculate dynamic fee for given volatility      */
/* ------------------------------------------------------------------ */
router.post("/calculate", (req: Request, res: Response) => {
  try {
    const { volBps, poolId } = req.body as {
      volBps: number;
      poolId?: string;
    };

    if (volBps === undefined || typeof volBps !== "number") {
      res.status(400).json({ error: "volBps is required and must be a number" });
      return;
    }

    const feeBps = interpolateFee(volBps);
    const regime = classifyRegime(volBps);

    res.json({
      volBps,
      feeBps,
      feePercent: parseFloat((feeBps / 100).toFixed(4)),
      regime: Regime[regime],
      regimeLabel: REGIME_NAMES[regime],
      poolId: poolId ?? null,
    });
  } catch (err) {
    console.error("[fees/calculate] error:", err);
    res.status(500).json({ error: "Fee calculation failed" });
  }
});

/* ------------------------------------------------------------------ */
/*  GET /schedule — Get fee schedule (all regime -> fee mappings)      */
/* ------------------------------------------------------------------ */
router.get("/schedule", (_req: Request, res: Response) => {
  try {
    const schedule = DEFAULT_FEE_SCHEDULE.map((tier) => ({
      regime: Regime[tier.regime],
      regimeLabel: REGIME_NAMES[tier.regime],
      volFloorBps: tier.volFloorBps,
      volCeilBps: tier.volCeilBps,
      feeBps: tier.feeBps,
      feePercent: parseFloat((tier.feeBps / 100).toFixed(4)),
    }));

    res.json({ schedule });
  } catch (err) {
    console.error("[fees/schedule] error:", err);
    res.status(500).json({ error: "Failed to retrieve fee schedule" });
  }
});

/* ------------------------------------------------------------------ */
/*  POST /simulate — Simulate fee over historical vol data            */
/* ------------------------------------------------------------------ */
router.post("/simulate", (req: Request, res: Response) => {
  try {
    const { volSeriesBps, volumePerPeriod } = req.body as {
      volSeriesBps: number[];
      volumePerPeriod?: number;
    };

    if (
      !volSeriesBps ||
      !Array.isArray(volSeriesBps) ||
      volSeriesBps.length === 0
    ) {
      res.status(400).json({
        error: "volSeriesBps must be a non-empty array of numbers",
      });
      return;
    }

    const volume = volumePerPeriod ?? 1_000_000; // default $1M per period

    const periods = volSeriesBps.map((vol, i) => {
      const feeBps = interpolateFee(vol);
      const regime = classifyRegime(vol);
      const feeRevenue = (feeBps / 10000) * volume;
      return {
        period: i,
        volBps: vol,
        feeBps,
        regime: Regime[regime],
        feeRevenue: parseFloat(feeRevenue.toFixed(2)),
      };
    });

    const totalRevenue = periods.reduce((sum, p) => sum + p.feeRevenue, 0);
    const avgFeeBps =
      periods.reduce((sum, p) => sum + p.feeBps, 0) / periods.length;

    res.json({
      periodCount: periods.length,
      volumePerPeriod: volume,
      totalRevenue: parseFloat(totalRevenue.toFixed(2)),
      avgFeeBps: parseFloat(avgFeeBps.toFixed(2)),
      periods,
    });
  } catch (err) {
    console.error("[fees/simulate] error:", err);
    res.status(500).json({ error: "Fee simulation failed" });
  }
});

export { router as feeRoutes };
