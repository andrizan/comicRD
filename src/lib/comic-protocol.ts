function shouldUseHttpProtocolWorkaround(userAgent: string): boolean {
  const normalized = userAgent.toLowerCase();
  return normalized.includes("windows") || normalized.includes("android");
}

export function comicPageSrc(chapterId: number, pageIndex: number, userAgent?: string): string {
  const runtimeUserAgent =
    userAgent ?? (typeof navigator === "undefined" ? "" : navigator.userAgent);
  const path = `/page/${chapterId}/${pageIndex}`;

  if (shouldUseHttpProtocolWorkaround(runtimeUserAgent)) {
    return `http://comicrd.localhost${path}`;
  }

  return `comicrd://localhost${path}`;
}
