# AGENTS.md — rules for AI coding agents

finpro: song cover recording with auto-rewind and auto-comping. The real project built from the PoC "C6".
Stack: iOS 18, iPhone only, portrait, Swift 5 language mode, SwiftUI, Clean Architecture + MVVM (`@Observable` ViewModels).

## Migration from the PoC
This project is migrated from the PoC at /Users/zildjianvito/Documents/apple-academy/challenge-6/poc-c6 (read-only reference).
Before migration work, read `docs/MIGRATION-GUIDE.md` and `docs/MIGRATION-STATUS.md`. Never modify the PoC repo.

## Read first
1. `docs/prd.md` — the spec (still worded as the PoC spec; update it with the user, not alone).
2. `docs/COLLABORATION.md` — folder ownership, contract-change process, conventions (team/branch parts are from the PoC, see `docs/MIGRATION-GUIDE.md` §8).
3. Everything in `finpro/Domain/` — the shared data contracts. Use these types; never create parallel versions (e.g. no new `Segment` when `SongSegment` exists).
4. `docs/DESIGN-SOURCE.md` — where the design lives (Sketch file "[C6] Project Besar", read through the Sketch MCP configured in `.mcp.json`) and how to read exact colors, fonts and sizes from it. Screenshots in `docs/design/` are only a snapshot; when Sketch is reachable, it wins.

## Do not modify without explicit permission from the user
- `finpro/Domain/Entities/`, `finpro/Domain/Repositories/`, `finpro/Domain/Contracts/` — shared contracts. If you believe a contract must change, STOP and explain the proposal instead of editing. Never change a contract to make a build error go away.
- `finpro.xcodeproj/` — build settings are owned by one person.
- `scripts/` and `.githooks/`.
- Folders owned by other team members (see `docs/COLLABORATION.md` §2).

## Code rules
- UI Slicing workflow (Mandatory): For every UI slicing task, always build, deploy to the booted iOS simulator (`xcrun simctl install booted <app>` & `launch`), capture automated screenshots (`xcrun simctl io booted screenshot <path.png>`), perform multimodal visual inspection against the Sketch design (`docs/DESIGN-SOURCE.md`; screenshots in `docs/design/` if Sketch is not reachable), and iterate on styling/layout until it matches 100% before concluding.
- Every non-UI type (capture, DSP, playback, analysis, composition, use cases, repositories) is declared `nonisolated`. The project defaults to MainActor isolation; realtime audio/video callbacks must never call MainActor code.
- ViewModels: `@Observable`, MainActor (default). Views call ViewModels, ViewModels call Use Cases, never AVFoundation/CoreML directly.
- No magic numbers: thresholds and durations come from `AppConfiguration`.
- Never use `Timer`, `Date()` or a stopwatch for video cut points. Use the capture session clock and file time (`docs/prd.md` §7.1).
- Time units: `TimeInterval` seconds on the song timeline, `CMTime` for the capture clock and video file time.
- Segment indices are zero-based; UI shows `index + 1`.
- `finpro/Domain/` may import only `Foundation` and `CoreMedia`.
- One primary type per file, file name = type name, same file header style as existing files.
- UI text in English. Error wording comes from `UserFacingError` (show it with `ErrorStateView`); add a case there instead of writing a new message.
- Camera/microphone permissions are handled by `PermissionGate` in `RootView`. Feature screens never request permissions themselves.

## Where files go
- Swift code: inside `finpro/` (synchronized folder, picked up by Xcode automatically).
- Docs, scripts, other non-code files: outside `finpro/`. A `.md`/`.json`/`.txt` inside `finpro/` gets bundled into the app.
- Never commit copyrighted songs, recorded videos, or `xcuserdata/`.

## Before you finish
- The app builds: `xcodebuild -project finpro.xcodeproj -scheme finpro -destination 'generic/platform=iOS Simulator' build`
- When slicing UI: run automated visual verification on booted simulator (`xcrun simctl install booted <app>`, `launch`, take screenshot via `xcrun simctl io booted screenshot <path.png>`), visually inspect and compare with Figma design, and iterate until UI matches before finishing.
- If anything in `finpro/Domain/` was touched: `./scripts/check-contracts.sh` passes.
- If anything in `finpro/Data/Composition/` was touched: `./scripts/check-comping.sh` passes.
- At handoff points, call the contract checks (`validate()` / `Contract.assertValid`), see `docs/COLLABORATION.md` §4.

## Branches
- **Never commit or push to `main`.** The branch model for this repo is not decided yet (`docs/MIGRATION-GUIDE.md` §8); ask the user which branch to work on. Before making changes, check the current branch (`git branch --show-current`); if it is `main`, stop and ask the user to switch.
- Contract changes go on a short `contract/<topic>` branch instead (see `docs/COLLABORATION.md` §3).
- Never force-push. Bring in `main` with `git merge origin/main`, not rebase.

## Commits
Every commit message follows **Conventional Commits**: `<type>(<optional scope>): <description>`, e.g. `feat(capture): write raw video with AVAssetWriter`. Allowed types and scopes: `docs/COLLABORATION.md` §6. The `commit-msg` hook in `.githooks/` rejects anything else.
