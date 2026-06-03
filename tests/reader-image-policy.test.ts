import { describe, expect, it } from "vitest";
import {
  computePrefetchRange,
  parseImagePipelineProfile,
  targetReaderImageWidth,
} from "../src/lib/reader-image-policy";

describe("reader image policy", () => {
  it("parses unknown profile values as balanced", () => {
    expect(parseImagePipelineProfile("performance")).toBe("performance");
    expect(parseImagePipelineProfile("quality")).toBe("quality");
    expect(parseImagePipelineProfile("other")).toBe("balanced");
    expect(parseImagePipelineProfile(undefined)).toBe("balanced");
  });

  it("caps target width by profile", () => {
    expect(targetReaderImageWidth(1800, 3, 2, "performance")).toBe(1280);
    expect(targetReaderImageWidth(1800, 3, 2, "balanced")).toBe(1600);
    expect(targetReaderImageWidth(1800, 3, 2, "quality")).toBe(2400);
  });

  it("prefetches more pages in the scroll direction", () => {
    expect(computePrefetchRange(10, 40, "forward", "balanced")).toEqual({
      startPage: 9,
      endPage: 15,
    });
    expect(computePrefetchRange(10, 40, "backward", "balanced")).toEqual({
      startPage: 5,
      endPage: 11,
    });
  });
});
