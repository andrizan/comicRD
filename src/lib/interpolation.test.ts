import { describe, expect, it } from "vitest";
import { INTERPOLATION_OPTIONS, interpolationToCss, normalizeInterpolation } from "./interpolation";

describe("interpolation helpers", () => {
  it("normalizes unknown values to linear", () => {
    expect(normalizeInterpolation("random")).toBe("linear");
    expect(normalizeInterpolation(undefined)).toBe("linear");
  });

  it("normalizes case-insensitively", () => {
    expect(normalizeInterpolation("Spline36")).toBe("spline36");
    expect(normalizeInterpolation("NEAREST")).toBe("nearest");
  });

  it("maps nearest to pixelated css", () => {
    expect(interpolationToCss("nearest")).toBe("pixelated");
    expect(interpolationToCss("lanczos3")).toBe("auto");
  });

  it("contains required interpolation methods", () => {
    expect(INTERPOLATION_OPTIONS).toContain("spline36");
    expect(INTERPOLATION_OPTIONS).toContain("mitchell");
    expect(INTERPOLATION_OPTIONS).toContain("lanczos2");
  });
});
