export type ImagePipelineProfile = "performance" | "balanced" | "quality";
export type ScrollDirection = "forward" | "backward";

type ProfilePolicy = {
  maxWidth: number;
  maxDpr: number;
  forwardPages: number;
  backwardPages: number;
};

const PROFILE_POLICIES: Record<ImagePipelineProfile, ProfilePolicy> = {
  performance: {
    maxWidth: 1280,
    maxDpr: 1,
    forwardPages: 6,
    backwardPages: 1,
  },
  balanced: {
    maxWidth: 1600,
    maxDpr: 1.25,
    forwardPages: 5,
    backwardPages: 1,
  },
  quality: {
    maxWidth: 2400,
    maxDpr: 1.75,
    forwardPages: 4,
    backwardPages: 2,
  },
};

export const DEFAULT_IMAGE_PIPELINE_PROFILE: ImagePipelineProfile = "balanced";
export const DEFAULT_READER_IMAGE_WIDTH = 1280;

export function parseImagePipelineProfile(value: unknown): ImagePipelineProfile {
  if (value === "performance" || value === "balanced" || value === "quality") {
    return value;
  }
  return DEFAULT_IMAGE_PIPELINE_PROFILE;
}

export function imagePipelineProfileOptions() {
  return Object.keys(PROFILE_POLICIES) as ImagePipelineProfile[];
}

export function targetReaderImageWidth(
  containerWidth: number,
  zoom: number,
  pixelRatio: number,
  profile: ImagePipelineProfile,
): number {
  const policy = PROFILE_POLICIES[profile];
  const cssWidth = Math.min(Math.max(1, containerWidth), Math.round(980 * zoom));
  const physicalWidth = cssWidth * Math.max(1, Math.min(pixelRatio, policy.maxDpr));
  return Math.max(480, Math.min(policy.maxWidth, Math.ceil(physicalWidth / 160) * 160));
}

export function computePrefetchRange(
  currentPage: number,
  totalPages: number,
  direction: ScrollDirection,
  profile: ImagePipelineProfile,
) {
  const policy = PROFILE_POLICIES[profile];
  const forwardPages = direction === "forward" ? policy.forwardPages : policy.backwardPages;
  const backwardPages = direction === "forward" ? policy.backwardPages : policy.forwardPages;
  return {
    startPage: Math.max(0, currentPage - backwardPages),
    endPage: Math.min(Math.max(0, totalPages - 1), currentPage + forwardPages),
  };
}
