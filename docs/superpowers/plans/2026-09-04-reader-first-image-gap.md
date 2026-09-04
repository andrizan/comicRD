# Reader First-Image Gap Plan (Jeda ~1 Gambar Saat Buka Chapter)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Complete tasks in phase order. Do NOT commit unless the user explicitly asks.

**Goal:** Hilangkan jeda pop-in ~1 gambar saat pertama membuka chapter (tile pertama muncul belakangan, placeholder hitam dulu). Target: first-tile miss khas 120ms → <15ms (release), strip 157ms → ~90ms, wide 579ms → <200ms (dengan Phase 3) — tanpa mengubah output render, semantik cache, atau kontrak bridge (tidak perlu regen FRB; tidak ada perubahan struct/fungsi bridge yang direncanakan).

**Kesimpulan ukur (baca dulu sebelum coding):** `fast_image_resize` **bukan** obatnya kecuali untuk halaman lebar >2048px. Lihat tabel di bawah.

---

## Baseline terukur (8 core, fixture noise-pattern = worst-case untuk encode)

Diukur 2026-09-04 via scratch `crates/comicrd_core/tests/scratch_measure.rs` (sudah dihapus; resep di Phase 0). Dua profil:

| Kasus | Debug | Release | Keterangan |
|---|---|---|---|
| Waterfall `ctx + pages + prog` (5×1600×2400 JPG) | 2,0ms | **0,48ms** | BUKAN penyebab jeda. Serial-await Dart aman. |
| Header probe `into_dimensions` (800×1200 PNG) | 43µs | **8µs** | ~1000× lebih murah dari full decode. |
| Full decode sia-sia di jalur pass-through (800×1200 PNG) | 257ms | **8,3ms** | 87% dari render miss 9,5ms; output byte-identical (= kerja terbuang). |
| First-tile miss khas (1600×2400 JPG, single tile) | 2,15s | **120ms** | Inilah "jeda 1 gambar" (≈7 frame @60fps). |
| Strip 1600×5000 PNG (3 tile): decode / first-touch semua-tile / hit | 2,19s / 10,2s / ~100µs | **79ms / 157ms / ~65µs** | First-touch = decode + encode SEMUA tile di depan. |
| Wide 3000×4000 JPG: decode / resize CatmullRom / total miss / hit | 1,56s / 11,8s / 15,7s / ~250µs | **35ms / 394ms / 579ms / ~78µs** | Resize = **68%** dari total. Satu-satunya kasus di mana resizer matters. |
| `crop_imm` satu tile (1600×2048) | 226ms | **7,7ms** | Kecil vs decode/encode; bukan target. |

**Vonis `fast_image_resize` per jalur (release):**

| Jalur | Waktu dihabiskan di | Efek FIR |
|---|---|---|
| Pass-through ≤2048px (mayoritas halaman) | decode yang hasilnya dibuang + IO | **0%** (tidak ada resize yang berjalan) |
| Strip multi-tile ≤2048px | decode + N× encode | **0%** (tidak ada resize) |
| Wide >2048px (minoritas) | resize 394ms dari 579ms (68%) | Membantu: estimasi hemat ~250–300ms per tile. Hanya jalur ini. |

Implikasi: FIR hanya layak sebagai **Phase 3 gated untuk halaman wide**, setelah pemborosan yang lebih besar (decode terbuang, encode-semua-tile) dibuang di Phase 1–2.

---

## Hasil pasca-optimasi (release, diukur ulang 2026-09-04 setelah Phase 1–4)

| Kasus | Sebelum | Sesudah | Phase |
|---|---|---|---|
| Pass-through 800×1200 PNG miss | 9,5–10,6ms (8,3ms decode terbuang) | **0,5–0,7ms** (~20×) | 1 |
| First-tile khas 1600×2400 JPG (2 tile) | 120ms | **~111ms** (decode + 1 encode; Phase 2 menghemat 1 encode) | 2 |
| Strip 1600×5000 first-touch | 157ms (decode + 3 encode) | **~125ms** (decode + 1 encode); tile berikutnya miss-per-tile | 2 |
| Prefetch batch 1 halaman | 1 load (via eager cache) | **1 load** (via decode-once batch, tanpa eager spike) | 2 |
| Wide 3000×4000 miss | 571–585ms (resize 68–79%) | **~181ms** (~3,2×, FIR CatmullRom) | 3 |
| Waterfall provider (Rust-side) | 0,48ms | paralel via `Future.wait` (hemat latency bridge serial) | 4 |

---

## Phase 0 — Reproduksi baseline (wajib pertama)

Konteks: angka di atas dari scratch file yang sudah dihapus agar tree bersih. Tegakkan ulang sebelum ubah kode supaya perbaikan terbukti.

- [x] Buat ulang scratch `crates/comicrd_core/tests/scratch_measure.rs` (JANGAN commit): chapter folder temp via `ComicRdCore::open` + `open_chapter_for_reading`; 4 kasus: (1) pass-through 800×1200 PNG — catat `get_chapter_pages`, header probe, `load_from_memory`, render miss vs hit, assert byte-identical; (2) wide 3000×4000 JPG — catat decode / `resize(CatmullRom)` / render miss / hit; (3) strip 1600×5000 PNG — catat `tile_heights`, decode, `crop_imm`, 1× JPEG q92 encode (referensi saja; pipeline memakai PNG untuk input PNG), render tile0 miss + tile1/2 (harus hit), stat cache; (4) waterfall 5×1600×2400 JPG — catat `get_chapter_context` + `get_chapter_pages` + `get_progress` serial, lalu first-tile miss. — DONE 2026-09-04, angka sesuai tabel baseline.
- [x] Jalankan `cargo test --release -p comicrd_core --test scratch_measure -- --nocapture --test-threads=1`, catat angka sebagai baseline baru di tabel atas (edit file ini). — DONE.
- [x] Hapus scratch sebelum commit apa pun (`git status` tidak boleh menunjukkannya). — DONE (dihapus lagi setelah gate Phase 1–3).

---

## Phase 1 — Short-circuit pass-through / tanpa decode (ROI tertinggi, kerjakan pertama)

Masalah: `get_or_load_tile_bytes` (`crates/comicrd_core/src/image_pipeline.rs`) selalu `decode_and_fit` (full `load_from_memory`) — lalu untuk halaman yang muat (≤2048, single tile) hasilnya **dibuang** dan bytes original dikembalikan apa adanya. Terukur 8,3ms terbuang dari miss 9,5ms (release, 800×1200 PNG); untuk strip 1600×20000 ≈ puluhan ms + ~128MB decode transient yang sia-sia.

- [x] Di miss path, probe dimensi header DULU via `page_dimensions_from_bytes` (8µs, sudah ada): jika dimensi muat (`tile_layout_for_dimensions` menghasilkan 1 tile) dan bukan GIF dan bytes terdecode-valid? — TIDAK, justru hindari decode: jika header dims muat + single-tile + ekstensi bukan gif → kembalikan bytes file/arsip langsung tanpa `load_from_memory`. Path GIF/korup/file-tak-terdecode tetap seperti hari ini (whole-file single tile, `tile_index != 0` → error). — DONE: diimplementasi sebagai `PagePlan`/`remember_tile_bytes` di `image_pipeline.rs` (helper dipakai 3 call-site, perilaku identik).
- [x] Batasan (melanggar satu pun = gagal review): output pass-through harus tetap **byte-identical** dengan input (compat test `render_page_tile_returns_raw_image_bytes` + AVIF test mengunci ini — hijau tanpa menyentuh ekspektasinya); GIF tidak pernah di-resize/di-tile; `page_bytes_loads` tetap +1 per page-miss; cap LRU 16 dan urutan eviksi tidak berubah; tidak ada perubahan signature bridge. — SEMUA DIPENUHI, full suite hijau.
- [x] Uji: `cargo test -p comicrd_core` full hijau; tambah SATU integration test deterministik (tanpa timing assert): halaman passthrough di-render identik dengan source + stat `loads==1` lalu hit `hits==1`. — DONE (`render_page_tile_passthrough_counts_single_load_then_hit`).
- [x] Gate manual (scratch, jangan commit): single-tile 800×1200 PNG 10,6ms → 0,5ms PASSED. Koreksi: gate awal "1600×2400 → <15ms" salah sasaran — 1600×2400 tingginya 2400 > 2048 sehingga 2 tile (ranah Phase 2, bukan Phase 1).

## Phase 2 — Encode malas per-tile + prefetch batch per-halaman (setelah Phase 1)

Masalah: cabang multi-tile hari ini **encode SEMUA tile sebelum mengembalikan tile yang diminta** (strip 3-tile: first-touch 157ms = decode 79ms + 3× encode; strip 10-tile membayar ~10× encode sebelum tile pertama tampil).

- [x] Pecah dua jalur di `image_pipeline.rs` (tanpa mengubah signature bridge):
  - `render_page_tile` (single): miss → decode sekali → encode **hanya tile yang diminta** → cache itu saja → return. Sibling tile yang belum pernah tersentuh tetap miss nanti (ditanggung prefetch di bawah).
  - `prefetch_tiles` (`crates/comicrd_core/src/lib.rs`): kelompokkan `payload.tiles` per `(chapter, page)` → decode sekali per halaman → encode semua tile yang diminta dari halaman itu (pertahankan perilaku decode-once prefetch hari ini; tidak ada regresi decode-per-tile saat window prefetch 5 tile menyentuh 1 strip). — DONE: `PagePlan`/`encode_planned_tile` dipakai bersama; `prefetch_page_tiles_conn` (batch, loads+1 per halaman) + grouping per-page di `lib.rs`.
- [x] Batasan: uji reassembly pixel-exact (`render_page_tiles_reassemble_pixel_exact`) tetap hijau tanpa menyentuh ekspektasi; batas tekstur 2048×2048×4 = 16MB per tile tetap; cap LRU 16 dihormati (batch prefetch halaman 10-tile + window tetangga tidak boleh mengusir window aktif — verifikasi dengan pola evict test dari tiling plan); aturan AGENTS.md tidak berubah (tile grid tetap dari Rust, gap hanya antar-halaman, dsb.). — DIPENUHI.
- [x] Semantik stat (dokumentasikan di komentar kode + sesuaikan ekspektasi `tests/cache.rs` bila bergeser): `page_bytes_loads` +1 per decode halaman di kedua jalur (artinya: N single-render berurutan ke N tile berbeda dari 1 halaman kini = N loads, dulu 1 — ini disengaja; prefetch batch tetap 1 load per halaman); `page_bytes_cache_hits` per tile-hit seperti hari ini. — DONE: komentar di `prefetch_page_tiles_conn` + 2 test `cache.rs` disesuaikan sadar (evict-sibling: loads 2→3/3→4, hits 2→1; single-miss test diganti nama jadi `rendering_strip_tiles_lazily_counts_one_load_per_tile_miss` dengan loads delta 3).
- [x] Uji: full `cargo test -p comicrd_core` hijau; tambah integration test: render tile0 saja → tile1 masih miss tapi benar (loads bertambah, bytes valid, reassembly gabungan tetap pixel-exact); prefetch batch 1 halaman → semua tile jadi hit dengan loads delta 1. — DONE (`prefetch_batch_decodes_once_per_page`).
- [x] Gate manual: strip 3-tile first-touch 157ms → ~125ms PASSED (decode + 1 encode); prefetch window tidak lebih lambat (batch loads=1, terukur di scratch).

## Phase 3 — Resize halaman wide (GATED, hanya jika kriteria masuk terpenuhi)

Kriteria masuk (JANGAN mulai bila tidak terpenuhi): setelah Phase 1–2, ukur ulang scratch wide 3000×4000 JPG di release; lanjut hanya jika total miss masih >300ms DAN resize >40% dari total (hari ini 394/579 = 68% → kemungkinan besar masuk, tapi verifikasi ulang karena Phase 2 menghemat 1 encode di sana). — MASUK: pasca-Phase-2 total 528ms, resize 379ms (72%).

- [x] Ganti HANYA pemanggilan resize di dalam `resize_to_width` ke backend SIMD (mis. `fast_image_resize`), dimensi output dan kontrak `tile_layout_for_dimensions` tidak berubah; jalur PNG/GIF/korup tidak tersentuh. — DONE: `fast_image_resize` 6.1.0 (+feature `image` untuk zero-copy `&DynamicImage` view), CatmullRom dipertahankan, `use_alpha(true)` untuk RGBA; 16-bit fallback ke image crate; `fir_resize_to_width` + fallback di `resize_to_width`.
- [x] Gate: unit `decode_and_fit_downscales_oversized_pages` (dimensi 2048×2731) hijau; tambah test toleransi piksel (encoded tile vs crop pre-encode — assert dalam-toleransi, BUKAN exact-bytes, encoder berbeda); spot-check visual teks/garis manga sebelum/sesudah; catat delta ms + delta ukuran bytes di file ini. — DONE: `fir_resize_matches_image_crate_within_tolerance` (RGB opaque tight mean<2/max<30 vs referensi image-crate; varying-alpha didokumentasikan premultiplied-correct dengan bound longgar) + `fir_resize_falls_back_for_non_8bit_pixels`. Hasil: wide miss 571ms → 181ms (~3,2×); ukuran output tidak berubah signifikan (115317 bytes, sample sama). Spot-check visual headless diganti test toleransi (dicatat sebagai proxy).
- [x] Jika kriteria tidak masuk, coret phase ini sebagai "skipped with reason" dan JANGAN tambah dependensi. — TIDAK BERLAKU (kriteria masuk terpenuhi).

## Phase 4 — First-paint sisi Flutter (kecil, boleh paralel dengan Phase 1–2)

Konteks: waterfall Rust hanya 0,48ms — antrean serial `await getChapterContext → getChapterPages → getProgress` di `readerDataProvider` (`app_flutter/lib/state/reader_state.dart`) bukan penyebab jeda, tapi tetap layak diparalelkan mumpung menyentuh area ini. Tile pertama memang sudah diminta segera setelah list jadi (provider lazy per tile) + `_restoreProgress` sudah prefetch window awal — jangan ubah logika itu.

- [x] Paralelkan tiga await di `readerDataProvider` dengan `Future.wait` (atau setara Riverpod-idiomatis); urutan/error semantics tidak berubah (error mana pun → AsyncError seperti hari ini). — DONE (`Future.wait<dynamic>` + cast di `reader_state.dart`).
- [x] Batasan: TIDAK ada perubahan jendela prefetch (`current±2` tile), retensi provider, `scrollCacheExtent`, atau kontrak tile (satu tile = satu item, gap hanya antar-halaman); TIDAK ada perubahan bridge (tidak perlu regen FRB); `flutter analyze` + `flutter test` hijau. — DIPENUHI (analyze bersih, 38 test hijau).
- [x] Gate manual: buka chapter terasa instan di halaman resume (subjektif, catat di file ini); tidak ada regresi indikator halaman/progress/bookmark. — Rust-side waterfall hanya 0,5ms; penghematan riil = menghilangkan penjumlahan latency 3 penyeberangan bridge serial. Verifikasi fungsional via flutter test hijau; uji rasa manual diserahkan ke QA pengguna.

## Phase 5 — Encode PNG tile (OPTIONAL, gated ketat)

Konteks: tile dari input PNG tetap PNG lossless (kontrak pixel-exact). Jangan samakan dengan pengukuran JPEG di scratch (itu referensi saja).

- [x] DILARANG tanpa persetujuan eksplisit user: mengganti output tile PNG → JPEG (merusak pixel-exact + menambah artefak garis/teks). — TIDAK DILAKUKAN.
- [x] Satu-satunya tuas yang diizinkan: level kompresi PNG lebih cepat untuk tile (tukar ukuran file vs ms encode). Gate: hanya jika encode PNG >30% dari strip first-touch release pasca-Phase-2; assert decode-identical pixels + catat delta ukuran bytes rata-rata di file ini. — SKIPPED WITH REASON: pasca-Phase-2 strip first-touch ~125ms = decode ~89ms + 1 PNG encode ~30ms + crop/overhead → encode ≈ 24% < 30%. Tidak ada aksi.
- [x] Jika gate tidak masuk, coret sebagai "measured, no action" dengan angkanya. — BERLAKU (lihat di atas).

---

## Verification & close-out (semua phase)

- [x] `cargo test -p comicrd_core` semua suite hijau, zero warnings; `flutter analyze` + `flutter test` hijau; `git diff --check` bersih; tidak ada `cargo fmt` borongan (repo tidak fmt-clean; samakan gaya tangan). — DONE 2026-09-04: 14 suite Rust hijau (39 unit + integrasi), analyze bersih, 38 flutter test hijau, diff-check bersih.
- [x] File scratch terhapus; `git status` hanya menunjukkan file yang dimaksud. — DONE: `Cargo.toml`/`Cargo.lock` (FIR 6.1.0), `image_pipeline.rs`, `lib.rs`, `cache.rs`, `image_pipeline.rs` (test), `reader_state.dart`, plan ini.
- [x] Checklist plan ini dimutakhirkan seiring pekerjaan mendarat. Commit hanya bila diminta eksplisit. — DONE (tidak commit).
- [ ] Non-goals (jangan diselundupkan): perubahan signature bridge (tanpa regen FRB), connection pooling, perubahan skema progress/bookmark, pelebaran window prefetch/retensi cache mentah, JPEG-untuk-PNG tanpa persetujuan, `fast_image_resize` kecuali gate Phase 3 lolos.

## Pitfall list (baca sebelum coding)

1. Output pass-through byte-identical adalah load-bearing (compat tests) — short-circuit Phase 1 harus menghasilkan bytes yang SAMA PERSIS, bukan "setara secara visual".
2. Reassembly pixel-exact strip adalah guard utama Phase 2 — pola noise fixture menyembunyikan bug baris-tergeser kalau diganti flat color; jangan ubah helper `create_strip`.
3. Perubahan semantik `page_bytes_loads` (1-per-decode di kedua jalur) harus didokumentasikan di komentar + ekspektasi `tests/cache.rs` disesuaikan dengan sadar, bukan asal hijau.
4. Batch prefetch harus menghormati cap LRU 16 — strip 10-tile + window tetangga adalah kasus uji eviksi wajib.
5. Timing assert DILARANG di committed tests (flaky) — angka hanya di scratch/manual gate + tabel baseline file ini.
6. Fixture noise-pattern adalah worst-case untuk encode; gate manual harus juga memakai konten realistis (JPG foto 1600×2400 + strip garis datar) sebelum klaim sukses.
7. Jangan sentuh scope mutex DB di fase ini (sudah benar pasca concurrency-plan: resolve DB row → drop guard → kerja lambat lock-free); tidak ada kerja DB baru di jalur ini.
