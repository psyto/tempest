import { Router, Request, Response } from "express";
import { instanceLookup } from "../middleware/instance-lookup";
import {
  Regime,
  REGIME_NAMES,
  classifyRegime,
  interpolateFee,
  DEFAULT_FEE_CONFIG,
  type FeeConfig,
} from "@fabrknt/tempest-core";

const router: import("express").Router = Router();

/* ------------------------------------------------------------------ */
/*  Shared middleware: all fee routes require an active instance       */
/* ------------------------------------------------------------------ */
router.use(instanceLookup);

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
    // Derive schedule from DEFAULT_FEE_CONFIG breakpoints
    const cfg = DEFAULT_FEE_CONFIG;
    const breakpoints: Array<{ vol: number; fee: number }> = [
      { vol: Number(cfg.vol0), fee: cfg.fee0 },
      { vol: Number(cfg.vol1), fee: cfg.fee1 },
      { vol: Number(cfg.vol2), fee: cfg.fee2 },
      { vol: Number(cfg.vol3), fee: cfg.fee3 },
      { vol: Number(cfg.vol4), fee: cfg.fee4 },
      { vol: Number(cfg.vol5), fee: cfg.fee5 },
    ];

    const schedule = breakpoints.map((bp, i) => {
      const regime = classifyRegime(bp.vol);
      const nextVol = i < breakpoints.length - 1 ? breakpoints[i + 1].vol : bp.vol;
      return {
        regime: Regime[regime],
        regimeLabel: REGIME_NAMES[regime],
        volFloorBps: bp.vol,
        volCeilBps: nextVol,
        feeBps: bp.fee,
        feePercent: parseFloat((bp.fee / 100).toFixed(4)),
      };
    });

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
