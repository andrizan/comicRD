import type { ReaderMode } from "../types";

export type SaveProgressPayload = {
  chapter_id: number;
  last_page: number;
  total_pages: number;
  mode: ReaderMode;
  is_read: boolean;
};

export function buildProgressPayload(
  chapterId: number,
  page: number,
  totalPages: number,
): SaveProgressPayload {
  const lastPage = totalPages <= 0 ? 0 : Math.max(0, Math.min(totalPages - 1, page));
  return {
    chapter_id: chapterId,
    last_page: lastPage,
    total_pages: totalPages,
    mode: "webtoon",
    is_read: totalPages > 0 && lastPage >= totalPages - 1,
  };
}
