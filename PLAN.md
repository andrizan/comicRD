# Plan Aplikasi Komik Reader (Tauri 2)

## Status Implementasi (Update)

- [x] Tauri 2 + React Vite + Tailwind + TanStack Router + TanStack Query
- [x] Database `rusqlite` + schema `libraries/comics/chapters/progress/bookmarks/settings`
- [x] Scan sumber komik `folder`, `zip`, `cbz`
- [x] Auto-detect komik setelah set folder library (model Hakuneko) + auto-detect saat startup jika library sudah ada
- [x] Library list + sort `name/date/date_modified` + folder view
- [x] Manga mode + webtoon mode
- [x] Keyboard prev/next page + prev/next chapter
- [x] Progress page, continue reading, bookmark, read/unread
- [x] Page indicator bawah + chapter indicator
- [x] Zoom + interpolation (`lanczos3`, `lanczos2`, `spline36`, `mitchell`, `cubic`, `linear`, `nearest`)
- [x] Settings global untuk reader mode, interpolation, smooth scroll, zoom default, page margin/gap
- [x] Smooth scrolling + lazy image + prefetch tetangga page
- [x] Cache render terpisah `thumbnail` dan `preview` dengan budget memori eksplisit + LRU by bytes
- [x] UX hardening awal: skeleton, empty state, error boundary/retry
- [ ] E2E smoke test UI end-to-end (masih pending sesuai prioritas)
- [ ] CI release/distribution pipeline lengkap untuk installer lintas platform

Catatan: unit test tambahan ditunda sesuai arahan user, kecuali test fondasi yang sudah ada.

## 1) Tujuan Produk

Membangun aplikasi komik reader desktop yang ringan dan cepat, berbasis **Tauri 2 + React (Vite)**, untuk membaca komik lokal dari **folder, ZIP, dan CBZ** dengan dua mode baca:

- **Manga mode** (paging / per halaman)
- **Webtoon mode** (vertical scrolling)

Fitur utama:

- Bookmark & continue reading
- Status read/unread per chapter
- Simpan progress sampai page terakhir per chapter
- Indikator chapter & indikator page di bawah (gaya MangaDex)
- Zoom + pilihan interpolation method (`lanczos3`, `lanczos2`, `mitchell`, `cubic`, `linear`, `nearest`, dll)
- Prev/next via keyboard arrow (opsional toggle)
- Smooth scrolling
- Pengaturan folder library komik
- Daftar semua folder/komik + sorting (`name`, `date`, `date_modified`)
- Fokus performa: lazy load image dan lazy list komik/folder
- Semua menu/setting bersifat serializable

---

## 2) Stack Teknis

- **Desktop shell**: Tauri 2
- **Backend core**: Rust
- **Database**: SQLite via `rusqlite`
- **Frontend**: React + Vite
- **UI**: TailwindCSS + shadcn/ui + Lucide Icons
- **Routing**: TanStack Router
- **Data fetching/cache state**: TanStack Query
- **Arsip**: ZIP/CBZ reader di Rust

---

## 3) Arsitektur High-Level

### Rust (Tauri Commands + Service Layer)

- `library_service`: add/remove folder library, scan file/folder komik
- `archive_service`: baca ZIP/CBZ, daftar entry image, ekstrak page on-demand
- `image_service`: decode + resize + interpolation + cache thumbnail/page
- `progress_service`: update last page, read/unread, continue
- `settings_service`: simpan/load setting serializable (JSON)

### React App

- Halaman:
  - Library list (folder/komik)
  - Comic detail + chapter list
  - Reader view (manga/webtoon)
  - Settings
- State:
  - Server state pakai TanStack Query
  - UI state lokal (reader controls, panel, hotkeys)
- Navigasi:
  - TanStack Router dengan route-level code splitting (lazy route)

---

## 4) Skema Database (rusqlite)

Tabel minimum:

- `libraries(id, path, created_at, updated_at)`
- `comics(id, library_id, title, source_path, source_type, created_at, updated_at, date_modified)`
- `chapters(id, comic_id, title, chapter_index, source_path, source_type, page_count, created_at, updated_at, date_modified)`
- `reading_progress(id, chapter_id, last_page, total_pages, mode, is_read, updated_at)`
- `bookmarks(id, chapter_id, page, created_at, note)`
- `settings(key PRIMARY KEY, value_json, updated_at)`

Catatan:

- `source_type`: `folder` | `zip` | `cbz`
- `mode`: `manga` | `webtoon`
- `value_json` menyimpan setting serialized JSON agar fleksibel.

---

## 5) Rencana Implementasi Bertahap

## Fase 0 - Bootstrap Proyek

- Inisialisasi Tauri 2 + React Vite + Tailwind + shadcn + Lucide
- Setup TanStack Router + TanStack Query
- Setup crate Rust dan dependency `rusqlite`
- Setup struktur folder modular (`src-tauri/src/services/*`, `src/features/*`)

Deliverable:

- App bisa jalan (desktop window), routing dasar siap.

## Fase 1 - Library & Scanner (Folder/ZIP/CBZ)

- Buat settings lokasi folder library
- Implement scanner recursive:
  - deteksi komik folder
  - deteksi `.zip` / `.cbz`
- Simpan metadata comic/chapter ke DB
- Halaman list komik/folder + sorting (`name/date/date_modified`)
- Lazy list/virtualized rendering untuk list besar

Deliverable:

- User bisa memilih folder, melihat seluruh komik, sort, dan metadata tersimpan.

## Fase 2 - Reader Engine (Manga + Webtoon)

- Implement load halaman chapter dari folder/zip/cbz (on-demand)
- Manga mode:
  - next/prev page
  - keyboard arrow navigation (dengan toggle enable/disable)
- Webtoon mode:
  - vertical scroll
  - smooth scrolling
- Zoom system:
  - zoom in/out/reset
  - interpolation method selector
- Bottom page indicator (style seperti MangaDex)

Deliverable:

- Chapter bisa dibaca dalam dua mode dengan kontrol dasar lengkap.

## Fase 3 - Progress, Bookmark, Continue, Read Status

- Simpan auto-progress saat user pindah halaman/scroll
- Continue reading dari halaman terakhir
- Bookmark create/delete per halaman
- Mark read/unread otomatis + manual toggle
- Chapter indicator (current chapter + status)

Deliverable:

- Progress persistent, bookmark berfungsi, status baca akurat.

## Fase 4 - Settings & UX Hardening

- Settings serializable:
  - default reader mode
  - keyboard enable/disable
  - interpolation default
  - smooth scroll speed
  - folder library paths
- UI/UX polish:
  - loading skeleton
  - empty states
  - error boundary & retry
- Shortcut map documentasi di UI

Deliverable:

- Konfigurasi lengkap, UX stabil, dan mudah dipakai.

## Fase 5 - Performance Pass (Wajib)

- Lazy image loading + prefetch terbatas (current, prev, next)
- Virtualized list komik/chapter panjang
- Caching:
  - thumbnail cache
  - decoded image cache terbatas memory budget
- Hindari re-render besar di React (route split + granular queries)
- Benchmark startup, open chapter, dan scroll FPS

Deliverable:

- Reader ringan pada library besar dan chapter panjang.

---

## 6) Strategi Performa (Kritis)

- Jangan ekstrak seluruh ZIP/CBZ sekaligus; ekstrak page saat dibutuhkan.
- Terapkan windowing pada webtoon page list.
- Batasi jumlah image decoded di memori (LRU-style cache).
- Semua query data list paginated/lazy.
- Debounce scan folder & update metadata batch per transaksi SQLite.

---

## 7) Testing Plan

- **Rust unit test**:
  - scanner folder/zip/cbz
  - progress persistence
  - sorting logic
- **Frontend test**:
  - reader controls (next/prev/hotkey toggle)
  - mode switch manga/webtoon
  - bookmark + continue flow
- **E2E smoke**:
  - add library -> open chapter -> read -> close -> continue works
  - mark read status tersimpan

---

## 8) MVP Scope (Rilis Pertama)

MVP wajib:

- Library folder + zip/cbz scan
- List komik + sorting
- Manga mode + webtoon mode
- Keyboard prev/next
- Zoom + interpolation selector
- Bookmark + continue + progress page
- Read/unread chapter
- Bottom page indicator
- Serializable settings
- Optimasi lazy loading dasar

Out-of-scope MVP (masuk backlog):

- Cloud sync
- Multi-device progress sync
- Plugin/theme marketplace

---

## 9) Urutan Eksekusi yang Disarankan

1. Fase 0
2. Fase 1
3. Fase 2
4. Fase 3
5. Fase 4
6. Fase 5 (wajib sebelum rilis)

Estimasi awal: **2-4 minggu** untuk MVP, tergantung kompleksitas arsip dan tuning performa.
