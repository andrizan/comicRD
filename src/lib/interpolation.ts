export const INTERPOLATION_OPTIONS = [
  "linear",
  "cubic",
  "nearest",
  "mitchell",
  "lanczos2",
  "lanczos3",
  "spline36",
] as const;

export type InterpolationMethod = (typeof INTERPOLATION_OPTIONS)[number];

export function interpolationToCss(method: string): "auto" | "pixelated" {
  if (method.toLowerCase() === "nearest") return "pixelated";
  return "auto";
}

export function normalizeInterpolation(method: string | null | undefined): InterpolationMethod {
  const normalized = (method ?? "linear").toLowerCase();
  if ((INTERPOLATION_OPTIONS as readonly string[]).includes(normalized)) {
    return normalized as InterpolationMethod;
  }
  return "linear";
}
