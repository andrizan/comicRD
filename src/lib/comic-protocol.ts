function shouldUseHttpProtocolWorkaround(userAgent: string): boolean {
  const normalized = userAgent.toLowerCase();
  return normalized.includes("windows") || normalized.includes("android");
}

export function comicPageSrc(
  chapterId: number,
  pageIndex: number,
  options: { targetWidth?: number; profile?: string; userAgent?: string } = {},
): string {
  return comicProtocolSrc("page", chapterId, pageIndex, options);
}

export function comicPagePreviewSrc(
  chapterId: number,
  pageIndex: number,
  options: { targetWidth?: number; userAgent?: string } = {},
): string {
  return comicProtocolSrc("preview", chapterId, pageIndex, {
    targetWidth: options.targetWidth ?? 64,
    profile: "performance",
    userAgent: options.userAgent,
  });
}

function comicProtocolSrc(
  resource: "page" | "preview",
  chapterId: number,
  pageIndex: number,
  options: { targetWidth?: number; profile?: string; userAgent?: string },
): string {
  const runtimeUserAgent =
    options.userAgent ?? (typeof navigator === "undefined" ? "" : navigator.userAgent);
  const path = `/${resource}/${chapterId}/${pageIndex}`;
  const targetWidth =
    typeof options.targetWidth === "number" && Number.isFinite(options.targetWidth)
      ? Math.max(1, Math.round(options.targetWidth))
      : undefined;
  const params = new URLSearchParams();
  if (targetWidth) params.set("w", String(targetWidth));
  if (options.profile) params.set("p", options.profile);
  const query = params.size > 0 ? `?${params.toString()}` : "";

  if (shouldUseHttpProtocolWorkaround(runtimeUserAgent)) {
    return `http://comicrd.localhost${path}${query}`;
  }

  return `comicrd://localhost${path}${query}`;
}
