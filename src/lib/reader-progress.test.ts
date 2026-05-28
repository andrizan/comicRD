import { describe, expect, it } from "vitest";
import { buildProgressPayload } from "./reader-progress";

describe("reader progress payload", () => {
  it("marks a chapter read when the last page is persisted", () => {
    expect(buildProgressPayload(8, 35, 36)).toEqual({
      chapter_id: 8,
      last_page: 35,
      total_pages: 36,
      mode: "webtoon",
      is_read: true,
    });
  });

  it("keeps an in-progress chapter unread", () => {
    expect(buildProgressPayload(8, 19, 36)).toMatchObject({
      last_page: 19,
      total_pages: 36,
      is_read: false,
    });
  });
});
