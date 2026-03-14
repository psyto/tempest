import { Router, Request, Response } from "express";
import { instanceLookup } from "../middleware/instance-lookup";
import { Regime, REGIME_NAMES, estimateIL, classifyRegime } from "@fabrknt/tempest-core";

const router: import("express").Router = Router();

/* ------------------------------------------------------------------ */
/*  Shared middleware: all LP routes require an active instance        */
/* ------------------------------------------------------------------ */
router.use(instanceLookup);

/* ------------------------------------------------------------------ */
/*  POST /range — Get recommended LP range based on current vol       */
/* ------------------------------------------------------------------ */
router.post("/range", (req: Request, res: Response) => {
  try {
    const { currentTick, volBps, poolId } = req.body as {
      currentTick: number;
      volBps: number;
      poolId?: string;
    };

    if (currentTick === undefined || typeof currentTick !== "number") {
      res.status(400).json({ error: "currentTick is required and must be a number" });
      return;
    }

    if (volBps === undefined || typeof volBps !== "number") {
      res.status(400).json({ error: "volBps is required and must be a number" });
      return;
    }

    // --- Range recommendation logic ---
    // Higher vol => wider range to reduce rebalancing frequency
    // Lower vol => tighter range for more capital efficiency
    const regime = classifyRegime(volBps);

    const RANGE_MULTIPLIERS: Record<Regime, number> = {
      [Regime.VeryLow]: 0.5,
      [Regime.Low]: 1.0,
      [Regime.Normal]: 2.0,
      [Regime.High]: 4.0,
      [Regime.Extreme]: 8.0,
    };
    const rangeMultiplier = RANGE_MULTIPLIERS[regime];

    // Base range width in ticks (1 tick ~= 1 bps price movement)
    const baseWidth = 200;
    const halfWidth = Math.round((baseWidth * rangeMultiplier) / 2);

    const lowerTick = currentTick - halfWidth;
    const upperTick = currentTick + halfWidth;

    res.json({
      poolId: poolId ?? null,
      currentTick,
      volBps,
      regime: Regime[regime],
      regimeLabel: REGIME_NAMES[regime],
      recommendedRange: {
        lowerTick,
        upperTick,
        widthTicks: upperTick - lowerTick,
      },
      capitalEfficiency: parseFloat(
        (1 / rangeMultiplier).toFixed(4),
      ),
    });
  } catch (err) {
    console.error("[lp/range] error:", err);
    res.status(500).json({ error: "Range recommendation failed" });
  }
});

/* ------------------------------------------------------------------ */
/*  POST /il-estimate — Estimate impermanent loss for a position      */
/* ------------------------------------------------------------------ */
router.post("/il-estimate", (req: Request, res: Response) => {
  try {
    const { volBps, rangeLower, rangeUpper, holdingPeriodDays } = req.body as {
      volBps: number;
      rangeLower: number;
      rangeUpper: number;
      holdingPeriodDays?: number;
    };

    if (volBps === undefined || typeof volBps !== "number") {
      res.status(400).json({ error: "volBps is required and must be a number" });
      return;
    }
    if (rangeLower === undefined || typeof rangeLower !== "number") {
      res.status(400).json({ error: "rangeLower is required and must be a number" });
      return;
    }
    if (rangeUpper === undefined || typeof rangeUpper !== "number") {
      res.status(400).json({ error: "rangeUpper is required and must be a number" });
      return;
    }
    if (rangeLower >= rangeUpper) {
      res.status(400).json({ error: "rangeLower must be less than rangeUpper" });
      return;
    }

    const days = holdingPeriodDays ?? 30;

    // Use @fabrknt/tempest-core estimateIL
    const ilPercent = estimateIL(volBps, rangeLower, rangeUpper, days);

    // Classify regime for context
    const regime = classifyRegime(volBps);

    res.json({
      volBps,
      rangeLower,
      rangeUpper,
      rangeWidthTicks: rangeUpper - rangeLower,
      holdingPeriodDays: days,
      estimatedILPercent: parseFloat(ilPercent.toFixed(4)),
      regime: Regime[regime],
      regimeLabel: REGIME_NAMES[regime],
      riskLevel:
        ilPercent < 1
          ? "low"
          : ilPercent < 5
            ? "medium"
            : ilPercent < 15
              ? "high"
              : "extreme",
    });
  } catch (err) {
    console.error("[lp/il-estimate] error:", err);
    res.status(500).json({ error: "IL estimation failed" });
  }
});

export { router as lpRoutes };
