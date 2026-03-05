import { describe, it, expect } from "vitest";
import { Regime, REGIME_NAMES, REGIME_COLORS } from "../types.js";

describe("Regime", () => {
  it("has correct numeric values", () => {
    expect(Regime.VeryLow).toBe(0);
    expect(Regime.Low).toBe(1);
    expect(Regime.Normal).toBe(2);
    expect(Regime.High).toBe(3);
    expect(Regime.Extreme).toBe(4);
  });

  it("has names for all regimes", () => {
    expect(REGIME_NAMES[Regime.VeryLow]).toBe("Very Low");
    expect(REGIME_NAMES[Regime.Low]).toBe("Low");
    expect(REGIME_NAMES[Regime.Normal]).toBe("Normal");
    expect(REGIME_NAMES[Regime.High]).toBe("High");
    expect(REGIME_NAMES[Regime.Extreme]).toBe("Extreme");
  });

  it("has colors for all regimes", () => {
    for (const regime of [Regime.VeryLow, Regime.Low, Regime.Normal, Regime.High, Regime.Extreme]) {
      expect(REGIME_COLORS[regime]).toMatch(/^#[0-9a-f]{6}$/);
    }
  });
});
