# finpro — Song Cover Recording & Auto-Comping

iOS 18 app (iPhone, portrait, SwiftUI). Sing a song segment by segment: the app rewinds a segment until your pitch passes, keeps one uninterrupted camera recording, then cuts the passed takes together with the instrumental into one cover video.

Migrated from the PoC `poc-c6` (commit `751e71b`). Migration progress: [docs/MIGRATION-STATUS.md](docs/MIGRATION-STATUS.md).

## Start here
| Doc | What it is |
|---|---|
| [docs/prd.md](docs/prd.md) | The spec |
| [docs/COLLABORATION.md](docs/COLLABORATION.md) | How we work: folders, contracts, git, conventions |
| [docs/MIGRATION-GUIDE.md](docs/MIGRATION-GUIDE.md) | How the PoC is moved into this project |
| [AGENTS.md](AGENTS.md) | Rules for AI coding agents |

## Setup
```bash
git config core.hooksPath .githooks   # enforces Conventional Commits
```
Open `finpro.xcodeproj`, run on a physical iPhone for camera and microphone.

## Checks (run on the Mac, no simulator needed)
```bash
./scripts/check-contracts.sh   # Domain contracts and handoff rules
./scripts/check-domain.sh      # use cases and the evaluation loop
./scripts/check-comping.sh     # comping: cut accuracy, sync, crossfades, partial export
./scripts/check-prep.sh        # song preparation: separation, guide, transposition, lyrics
```
