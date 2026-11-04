# Migration guide: PoC C6 → real project

> Dibuat 4 Nov 2026 dari PoC di branch `integration`, commit `751e71b`.
> **Pembaca utama: AI agent (Claude Code) yang bekerja di repo real project yang baru.** Manusia juga boleh baca.
> Semua path di sini absolut karena PoC dan real project ada di Mac yang sama.

## 0. Cara pakai dokumen ini (untuk agent)

1. Baca dokumen ini sampai habis sebelum mengubah apa pun di real project.
2. **PoC hanya untuk dibaca.** Jangan edit, commit, checkout branch, atau jalankan `git` yang mengubah state di repo PoC. Ambil kode dengan `cp`/`rsync`, bukan `git mv`.
3. Progres migrasi dicatat di real project, di `docs/MIGRATION-STATUS.md` (checklist §9 disalin ke sana di langkah pertama). Setiap sesi baru: baca file status itu dulu, lalu lanjut dari item yang belum dicentang.
4. Kalau PoC sudah berubah setelah commit `751e71b` (cek `git -C <POC_ROOT> log --oneline 751e71b..integration`), beri tahu user dan tanyakan apakah perubahan itu ikut dimigrasi.
5. Kalau ada keputusan di §8 (pertanyaan terbuka) yang belum dijawab, tanyakan ke user dan jangan menebak.

### Path penting
| Nama | Path |
|---|---|
| `POC_ROOT` | `/Users/zildjianvito/Documents/apple-academy/challenge-6/poc-c6` |
| Kode PoC | `POC_ROOT/poc-c6/` |
| Spec | `POC_ROOT/docs/prd.md` (v3.3), sumber kebenaran perilaku app |
| Aturan tim | `POC_ROOT/docs/COLLABORATION.md`, `POC_ROOT/AGENTS.md` |
| Laporan tes | `POC_ROOT/docs/test-reports/` |
| Lagu uji lokal (ber-copyright, jangan pernah di-commit) | `POC_ROOT/local-songs/` |
| Real project | **belum ada**, rencananya folder baru di `/Users/zildjianvito/Documents/apple-academy/challenge-6/`. Tanyakan nama folder ke user |

Supaya baca file PoC tidak memicu prompt izin terus, user bisa menambahkan folder `POC_ROOT` ke sesi Claude di real project (desktop app: tambah folder ke sesi; CLI: `/add-dir`).

## 1. Tentang user dan tim

- User: **Zildjian Vito** (GitHub `zildjianvitoo`), Apple Developer Academy challenge 6. Jawab dalam **bahasa Indonesia santai**.
- Tim PoC bertiga: Ikzaz (song preparation), Takin (recording session), Zildjian (comping/export, integrasi, pemilik PRD). Sejak 1 Nov 2026 Zildjian mengambil alih semua backlog yang tersisa.
- Jangan lakukan aksi GitHub atas nama teman tim (buat branch, setting repo). Tulis langkahnya saja, biar mereka yang jalankan.
- Repo GitHub real project dibuat sendiri oleh user. Agent tidak membuat repo dan tidak push sebelum user minta.

## 2. Keputusan migrasi (4 Nov 2026)

| Topik | Keputusan |
|---|---|
| Repo | **Repo dan Xcode project baru.** PoC dibekukan sebagai referensi. History git PoC tidak ikut |
| Scope | **Logic sama, UI baru.** Domain/Data/Shared dipindah apa adanya. ViewModel dipertahankan kalau alurnya sama. View dibuat ulang mengikuti desain final |
| Struktur | **Satu target app** (belum dipecah jadi Swift Package). Batas layer tetap dijaga dengan script check |
| Nama app / bundle ID | **Belum ditentukan.** Pakai nama sementara, lalu tanya user sebelum TestFlight |
| Tim / branch | Belum dibahas untuk real project. Lihat §8 |

## 3. Setup project Xcode baru

Buat project iOS App (SwiftUI, Swift Testing) dan samakan setting dengan PoC. Setting lengkap PoC ada di `POC_ROOT/poc-c6.xcodeproj/project.xcproj`. Project ini memakai format JSON Xcode baru dengan folder tersinkron, jadi folder yang disalin ke folder target langsung terbaca otomatis.

Setting target yang wajib sama:
```
IPHONEOS_DEPLOYMENT_TARGET          = 18.0
TARGETED_DEVICE_FAMILY              = 1            (iPhone only)
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait
SWIFT_VERSION                       = 5.0
SWIFT_DEFAULT_ACTOR_ISOLATION       = MainActor
SWIFT_APPROACHABLE_CONCURRENCY      = YES
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
STRING_CATALOG_GENERATE_SYMBOLS     = YES
GENERATE_INFOPLIST_FILE             = YES
DEVELOPMENT_TEAM                    = YU8G545MR2   (konfirmasi ke user)
INFOPLIST_KEY_NSCameraUsageDescription       = "Record your cover video with the front camera."
INFOPLIST_KEY_NSMicrophoneUsageDescription   = "Hear your voice to check your pitch and record your cover."
INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Save your finished cover video to Photos."
```
- **Jangan** pakai bundle ID PoC (`pakenanya.poc-c6`).
- Folder `docs/` dan `scripts/` ada di luar folder target app. File `.md`/`.json`/`.txt` di dalam folder target ikut ter-bundle ke app.

### Git LFS (sebelum commit pertama)
Di PoC, model CoreML di-commit langsung tanpa LFS (HTDemucs ±58 MB). Di repo baru:
```bash
brew install git-lfs
```
```bash
git lfs install && git lfs track "*.mlpackage/**" "*.mlmodel" && git add .gitattributes
```
Git LFS belum terpasang di Mac ini per 4 Nov 2026. Instalasi lewat brew dijalankan sendiri oleh user.

`.gitignore`: salin dari `POC_ROOT/.gitignore` (sudah mencakup `xcuserdata/`, `*.mov`, `*.mp4`, `local-songs/`, `.claude/worktrees/`).

## 4. Peta file: apa yang dipindah

Notasi: **Salin** = salin apa adanya, hanya header file dan nama yang disesuaikan. **Adaptasi** = salin lalu sesuaikan. **Ulang** = tulis ulang mengikuti desain baru, file PoC jadi referensi perilaku. **Tinggal** = tidak dimigrasi.

### Domain (`poc-c6/Domain/`, 41 file): Salin semua
`Entities/`, `Repositories/`, `Contracts/`, `UseCases/`. Ini kontrak bersama dan sumber kebenaran tipe data. Jangan buat tipe tandingan. Domain hanya boleh `import Foundation` dan `CoreMedia`.

### Data (`poc-c6/Data/`, 28 file): Salin semua
`Audio/`, `Capture/`, `Composition/`, `Lyrics/`, `Separation/`, `Session/`. Catatan:
- `Separation/DemoAudioSynthesizer.swift` dan `SynthesizedDemoRepository.swift` dipakai untuk lagu demo bawaan. Tanya user apakah lagu demo masih ada di real project.
- `Separation/LoggingStemSeparationRepository.swift` adalah pembungkus untuk debug. Pertahankan, tapi pasang hanya di build DEBUG.

### Shared (`poc-c6/Shared/`, 9 file): Salin semua
`DSP/` (CREPE, STFT, spektrogram Demucs, PitchMath), `Storage/SessionFiles.swift`, `DebugOptions.swift`, `MemoryFootprint.swift`.

### Resources dan lisensi: Salin
- `poc-c6/Resources/CrepeTiny.mlmodel`, `poc-c6/Resources/HTDemucs.mlpackage` (lewat LFS)
- `POC_ROOT/Licenses/` (CREPE dan Demucs). **Wajib ikut**, dan nantinya ditampilkan di layar lisensi/about app
- `poc-c6/Assets.xcassets`: hanya kalau user tidak punya aset baru dari desain

### App (`poc-c6/App/`): Adaptasi
| File | Tindakan |
|---|---|
| `AppContainer.swift` | Adaptasi. Composition root: menyambungkan repository asli ke use case. Bagian yang memakai `Fake*` (sekitar baris 90 dan 134) harus tetap di belakang `#if DEBUG` / preview |
| `AppFlow.swift` | Adaptasi mengikuti alur layar di desain baru |
| `ConfigurationStore.swift` | Salin. Menyimpan konfigurasi dengan versi skema. Di real project, mulai dari versi baru dan tanpa migrasi data PoC (belum ada user) |
| `ModelPrewarmer.swift` | Salin |
| `RootView.swift` | Adaptasi. `PermissionGate` tetap di sini |
| `poc_c6App.swift` | Ulang dengan nama app baru |

### Presentation (`poc-c6/Presentation/`): campuran. **Hati-hati, tidak semua isinya UI**
Beberapa file di Presentation berisi logic atau protokol, bukan View. File seperti ini **wajib ikut**, dan beberapa di antaranya dikompilasi oleh script check.

| File | Isinya | Tindakan |
|---|---|---|
| `Recording/LoopStateController.swift` | State machine loop evaluasi/rewind (logic murni, dites `check-domain.sh`) | **Salin** |
| `Recording/RecordingViewModel.swift` | Alur sesi rekam | Salin, sesuaikan bila desain mengubah alur |
| `Recording/CameraPreviewSource.swift` | Protokol preview kamera | Salin |
| `Recording/CameraPreviewView.swift` | Bridge `AVCaptureVideoPreviewLayer` | Salin (bisa di-style ulang) |
| `Recording/PianoRollView.swift`, `CorrectionOverlayView.swift`, `RecordingView.swift` | UI | **Ulang**, perilaku sesuai PRD §5 |
| `VocalRange/LivePitchSource.swift` | Protokol | Salin |
| `VocalRange/VocalRangeViewModel.swift` | Alur tes vocal range | Salin |
| `VocalRange/VocalRangeTestView.swift` | UI | Ulang |
| `Import/ImportSongViewModel.swift`, `KeySelectionViewModel.swift` | Alur import/trim/pilih key | Salin |
| `Import/LyricsProviding.swift`, `AudioFileInspecting.swift`, `AudioPreviewing.swift` | Protokol (`LyricsProviding` dikompilasi `check-prep.sh`) | **Salin** |
| `Import/PreparationErrors.swift` | Tipe error | Salin |
| `Import/ImportSongView.swift`, `KeySelectionView.swift`, `ReadyView.swift` | UI | Ulang |
| `Export/CompingViewModel.swift` | Alur comping/export | Salin |
| `Export/VideoLibrarySaving.swift`, `PhotoLibraryVideoSaver.swift` | Protokol dan implementasi simpan ke Photos | Salin |
| `Export/ExportPreviewView.swift` | UI | Ulang |
| `Common/UserFacingError.swift`, `UserFacingConvertible.swift`, `HeadsetMicrophoneErrors.swift` | Semua teks error yang tampil ke user | Salin |
| `Common/PermissionGate.swift`, `PermissionGateModel.swift`, `MediaPermissionProviding.swift`, `SystemMediaPermissions.swift`, `MicrophoneInputProviding.swift` | Izin kamera/mikrofon | Salin. `PermissionGate` boleh di-style ulang |
| `Common/ErrorStateView.swift` | UI error | Salin, lalu style ulang |
| `Common/PlaceholderScreen.swift` | Placeholder PoC | Tinggal |
| `Debug/*` (DebugSettingsView, SyncCalibration*, MicrophoneSampleSource) | Layar tuning threshold dan kalibrasi sync | Salin, bungkus `#if DEBUG` |

### Fakes (`poc-c6/Fakes/`, 13 file): Salin
Dipakai `AppContainer` untuk SwiftUI Preview dan mode simulator (`SimulatedSinger`). Bungkus `#if DEBUG` supaya tidak masuk build Release.

### Tests, scripts, hooks: Adaptasi
| Item | Tindakan |
|---|---|
| `POC_ROOT/scripts/check-*.sh` + `contract-check/`, `domain-checks/`, `comping-check/`, `prep-checks/` | Salin. Ganti semua `"$ROOT/poc-c6/..."` dengan nama folder target baru. Kalau ada file yang pindah folder (misalnya `LoopStateController`, `LyricsProviding`, `SessionFiles`, file DSP), update daftar file di `check-domain.sh`, `check-prep.sh`, dan `check-comping.sh` |
| `POC_ROOT/Tests/*.swift` | Regression check standalone (lihat `docs/test-reports/`). Pindahkan ke test target Swift Testing, atau tetap jalankan sebagai script |
| `POC_ROOT/.githooks/commit-msg` | Salin. Setelah clone: `git config core.hooksPath .githooks` |
| `POC_ROOT/.github/pull_request_template.md` | Salin, ganti ID backlog |

### Docs
| Doc PoC | Tindakan |
|---|---|
| `docs/prd.md` | Salin sebagai spec awal. Bagian "PoC", "Out of Scope (PoC)", dan rencana dua track diperbarui bersama user, jangan diubah sepihak |
| `docs/COLLABORATION.md`, `AGENTS.md` | Adaptasi: ganti nama repo/folder dan model branch (§8) |
| `docs/roadmap-akurasi.md` | Salin (rencana akurasi masih relevan) |
| `docs/test-reports/` | Tinggal. Rujuk lewat path PoC |
| `docs/archive/`, `docs/review-*.md`, `docs/STATUS-*.md`, `docs/backlog/` | Tinggal. Backlog real project dibuat baru |
| `POC_ROOT/prototypes/` | Tinggal (spike Demucs, Whisper, KeyRehearsal) |

## 5. Rename yang disarankan (minta persetujuan user dulu)

Lakukan **sekali**, di commit `refactor` tersendiri, setelah semua layer ter-build dan sebelum tim mulai bercabang:
- `PoCConfiguration` → misalnya `AppConfiguration` (dipakai di 29 file, termasuk `PoCConfiguration+LivePitch.swift` dan `PoCConfiguration+VocalRange.swift`). Ini **tipe kontrak**: tanya user dulu.
- Header file `//  poc-c6` → nama project baru.
- `poc_c6App` → `<NamaApp>App`.
- Hapus kata "PoC" dari teks UI kalau ada.

Jangan ubah perilaku atau threshold saat rename.

## 6. Aturan kode yang tetap berlaku
Diambil dari `POC_ROOT/AGENTS.md`. Baca file aslinya untuk detail.
- Semua tipe non-UI (capture, DSP, playback, analysis, composition, use case, repository) dideklarasikan `nonisolated`. Callback audio/video realtime tidak boleh memanggil kode MainActor.
- MVVM: View → `@Observable` ViewModel → Use Case. ViewModel tidak memanggil AVFoundation/CoreML langsung.
- Tidak ada magic number: threshold dan durasi diambil dari konfigurasi (`PoCConfiguration`, nanti nama barunya).
- Titik potong video memakai clock capture session dan waktu file (`CMTime`), **bukan** `Timer`/`Date()` (PRD §7.1).
- Waktu di timeline lagu memakai `TimeInterval` (detik). Index segmen mulai dari 0, UI menampilkan `index + 1`.
- Satu tipe utama per file, nama file sama dengan nama tipe.
- Teks UI dalam bahasa Inggris. Teks error berasal dari `UserFacingError`.
- Izin kamera/mikrofon hanya lewat `PermissionGate`.
- Panggil `validate()` / `Contract.assertValid` di titik handoff.
- Conventional Commits (type dan scope ada di `POC_ROOT/docs/COLLABORATION.md` §6).

## 7. Urutan kerja dan titik cek

Build setelah setiap langkah:
```bash
xcodebuild -project <Nama>.xcodeproj -scheme <Nama> -destination 'generic/platform=iOS Simulator' build
```

1. **Kerangka**: project baru + setting §3, `.gitignore`, LFS, hook, dan `docs/MIGRATION-STATUS.md`. Commit: `build: add xcode project`.
2. **Domain**: salin, lalu build dan jalankan `check-contracts.sh` + `check-domain.sh` (`LoopStateController` ikut disalin di langkah ini). Commit: `chore(domain): import domain from poc-c6@751e71b`.
3. **Shared + Data + Resources + Licenses**: salin, lalu build dan jalankan `check-comping.sh` + `check-prep.sh`. Commit: `chore: import data layer from poc-c6@751e71b`.
4. **Presentation non-UI + Fakes + Debug**: semua ViewModel, protokol, error, dan permission (§4). Build.
5. **App shell**: `AppContainer`, `AppFlow`, `RootView`, dan entry point. Untuk sementara pakai View PoC atau placeholder supaya app bisa jalan end to end.
6. **Verifikasi kesetaraan dengan PoC** di iPhone fisik: pakai lagu uji yang sama dari `local-songs/`, jalani alur yang sama, lalu bandingkan hasil export (durasi, titik potong, sync vokal). Tidak boleh ada perbedaan perilaku sebelum UI diganti.
7. **Rename** (§5), setelah disetujui user.
8. **UI baru**: ganti View satu per satu mengikuti desain. ViewModel jangan diubah kecuali desain memang mengubah alur.
9. **Bekukan PoC**: user yang membuat tag `poc-final` di repo PoC dan menambahkan catatan di README PoC. Agent tidak melakukannya tanpa diminta.

## 8. Pertanyaan terbuka (tanyakan ke user)
- Nama app, bundle ID, nama folder/repo, dan apakah `DEVELOPMENT_TEAM` tetap `YU8G545MR2`.
- Model kerja tim di real project: tetap bertiga dan satu branch per orang, atau feature branch + PR?
- Apakah lagu demo bawaan (synthesized demo) masih dipakai?
- Apakah protokol yang sekarang ada di Presentation (`LivePitchSource`, `LyricsProviding`, `CameraPreviewSource`, dll.) mau dipindah ke `Domain/Repositories`? Ini perubahan kontrak, jadi butuh persetujuan.
- Apakah Git LFS bisa dipakai (kuota GitHub LFS gratis 1 GB storage)?
- Fitur yang di PoC out of scope (PRD §2.2) dan sekarang masuk scope.

## 9. Checklist (salin ke `docs/MIGRATION-STATUS.md` di real project)
```markdown
# Migration status (source: poc-c6@751e71b)
- [ ] 1. Xcode project + build settings + .gitignore + LFS + hooks
- [ ] 2. Domain imported, check-contracts + check-domain pass
- [ ] 3. Shared + Data + Resources + Licenses imported, check-comping + check-prep pass
- [ ] 4. Presentation non-UI + Fakes + Debug imported, builds
- [ ] 5. App shell runs end to end (old/placeholder views)
- [ ] 6. Parity test on iPhone vs PoC passed (song: ___, date: ___)
- [ ] 7. Renames approved and done
- [ ] 8. New UI: import / key selection / vocal range / recording / export
- [ ] 9. PoC tagged poc-final (by user)

## Decisions log
- 2026-11-04: new repo, logic same + new UI, single target, temporary name.
```

## 10. Potongan untuk `CLAUDE.md` / `AGENTS.md` real project
Tempel di awal file agar agent di real project selalu membaca panduan ini:
```markdown
## Migration from the PoC
This project is migrated from the PoC at /Users/zildjianvito/Documents/apple-academy/challenge-6/poc-c6 (read-only reference).
Before migration work, read /Users/zildjianvito/Documents/apple-academy/challenge-6/poc-c6/docs/MIGRATION-GUIDE.md and docs/MIGRATION-STATUS.md in this repo.
Never modify the PoC repo.
```
