# Migration status (source: poc-c6@751e71b, branch `integration`)

Guide: `docs/MIGRATION-GUIDE.md` (copy) — the original lives at
`/Users/zildjianvito/Documents/apple-academy/challenge-6/poc-c6/docs/MIGRATION-GUIDE.md`.

- [ ] 1. Xcode project + build settings + .gitignore + LFS + hooks
  - [x] build settings aligned with the PoC (iOS 18.0, iPhone only, portrait, permission strings, docs/scripts folders)
  - [x] `.gitignore`, `.githooks/`, `.github/` copied
  - [x] `git init -b main`, `git config core.hooksPath .githooks` (2026-11-04)
  - [ ] Git LFS installed by the user (`brew install git-lfs`), then `git lfs track` before the first commit
- [x] 2. Domain imported, check-contracts + check-domain pass (2026-11-04)
- [x] 3. Shared + Data + Resources + Licenses imported, check-comping + check-prep pass (2026-11-04)
- [x] 4. Presentation + Fakes + Debug imported, simulator build succeeds (2026-11-04)
  - [x] Fakes, `SimulatedSinger`, Debug Settings and the sync click test are `#if DEBUG` only; `LoggingStemSeparationRepository` is wired in Debug builds only. Debug and Release simulator builds succeed; the Release binary has no Fake/Debug symbols (2026-11-04)
  - [x] `ConfigurationStore` restarts at schema version 1 with no PoC migration steps; `PlaceholderScreen` removed (guide §4: not migrated)
  - [x] `Tests/*.swift` stay standalone scripts (no test target yet): VocalKeyChecks 44, RealtimeRegressionChecks 83, RealtimePitchChecks 25 pass. The VocalKeyChecks recipe (PoC `docs/test-reports/vocal-key-selection.md`) now needs `-D DEBUG`, because it compiles `FakeVocalRangeRepository`
- [ ] 5. App shell runs end to end on iPhone (PoC views for now) — copied and builds, not yet run on a device
- [ ] 6. Parity test on iPhone vs PoC passed (song: ___, date: ___)
- [x] 7. Renames approved and done (2026-11-04)
  - `PoCConfiguration` → `AppConfiguration` (type, 3 files, UserDefaults keys), 148 file headers `//  poc-c6` → `//  finpro`, Logger fallback subsystem `finpro`, LRCLIB user agent `finpro/1.0 (Apple Developer Academy)`. No behavior or threshold changes; all checks pass
  - Still open: add the repo URL to the LRCLIB user agent once the GitHub repo exists; `docs/prd.md` still says `PoCConfiguration` (update with the user)
- [ ] 8. New UI: import / key selection / vocal range / recording / export
- [ ] 9. PoC tagged poc-final (by user)

## Decisions log
- 2026-11-04: new repo, logic same + new UI, single target, temporary name.
- 2026-11-04: project named `finpro`, bundle ID `pakenanya.finpro`. All PoC code copied as is (Views included, to be replaced later); only the entry point was renamed `poc_c6App` → `FinproApp`. Xcode template `ContentView.swift` removed.
- 2026-11-04: Fakes and debug screens excluded from Release builds. A Release build on the simulator runs the real repositories (no simulated singer).
- 2026-11-04: user approved the step 7 rename. `scripts/` Swift files were updated only for the type name and headers.
- 2026-11-04: bootstrap commits (project + imported layers + rename) go on `main` as the base; all later work, starting with step 8, goes on a separate branch. GitHub repo comes later. Steps 5–6 (device run, parity test) postponed; step 8 starts from design screenshots/files from the user.
