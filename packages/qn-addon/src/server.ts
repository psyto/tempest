import express from "express";
import cors from "cors";
import morgan from "morgan";
import { config } from "./config";
import { requestId } from "./middleware/request-id";
import { apiLimiter } from "./middleware/rate-limit";
import { errorHandler } from "./middleware/error-handler";

import provisionRoutes from "./routes/provision";
import { volatilityRoutes } from "./routes/volatility";
import { feeRoutes } from "./routes/fees";
import { lpRoutes } from "./routes/lp";

const app: import("express").Express = express();

/* ------------------------------------------------------------------ */
/*  Global middleware                                                   */
/* ------------------------------------------------------------------ */
app.use(cors());
app.use(express.json());
app.use(morgan("short"));
app.use(requestId);
app.use(apiLimiter);

/* ------------------------------------------------------------------ */
/*  Routes                                                             */
/* ------------------------------------------------------------------ */

// Healthcheck (public, no auth)
app.get("/healthcheck", (_req, res) => {
  res.json({ status: "ok", service: "fabrknt-dynamic-fees", version: "0.1.0" });
});

// QuickNode provisioning (basic auth)
app.use(provisionRoutes);

// API routes
app.use("/v1/volatility", volatilityRoutes);
app.use("/v1/fees", feeRoutes);
app.use("/v1/lp", lpRoutes);

/* ------------------------------------------------------------------ */
/*  Error handler (must be last)                                       */
/* ------------------------------------------------------------------ */
app.use(errorHandler);

app.listen(config.port, () => {
  console.log(`Tempest QN Add-On running on port ${config.port}`);
});

export default app;
