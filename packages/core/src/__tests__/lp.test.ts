import { describe, it, expect } from "vitest";
import { estimateIL } from "../lp.js";

describe("estimateIL", () => {
  it("returns 0 for zero or negative range width", () => {
    expect(estimateIL(5000, 100, 100)).toBe(0);
    expect(estimateIL(5000, 200, 100)).toBe(0);
  });

  it("returns higher IL for higher volatility", () => {
    const lowVol = estimateIL(2000, -1000, 1000, 30);
    const highVol = estimateIL(8000, -1000, 1000, 30);
    expect(highVol).toBeGreaterThan(lowVol);
  });

  it("returns lower IL for wider ranges", () => {
    const narrow = estimateIL(5000, -500, 500, 30);
    const wide = estimateIL(5000, -2000, 2000, 30);
    expect(narrow).toBeGreaterThan(wide);
  });

  it("returns higher IL for longer holding periods", () => {
    const short = estimateIL(5000, -1000, 1000, 7);
    const long = estimateIL(5000, -1000, 1000, 90);
    expect(long).toBeGreaterThan(short);
  });

  it("caps at 100%", () => {
    const il = estimateIL(50000, -1, 1, 365);
    expect(il).toBe(100);
  });

  it("defaults to 30-day holding period", () => {
    const explicit = estimateIL(5000, -1000, 1000, 30);
    const defaulted = estimateIL(5000, -1000, 1000);
    expect(explicit).toBe(defaulted);
  });
});
